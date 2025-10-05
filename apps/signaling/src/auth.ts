import { Request, Response, NextFunction } from "express";
import jwt from "jsonwebtoken";

export interface AuthPayload {
  roomId: string;
  role: "host" | "participant";
  sub: string;
  perms?: string[];
}

const DEFAULT_TOKEN_TTL =
  process.env.JWT_TTL || (process.env.NODE_ENV === "production" ? "5m" : "12h");

export function signToken(payload: AuthPayload, ttl = DEFAULT_TOKEN_TTL) {
  return jwt.sign(payload, process.env.JWT_SECRET!, { expiresIn: ttl });
}

export function verifyToken<T = AuthPayload>(token: string): T {
  return jwt.verify(token, process.env.JWT_SECRET!) as T;
}

export function requireBearer(req: Request, res: Response, next: NextFunction) {
  const hdr = req.headers.authorization || "";
  const m = hdr.match(/^Bearer\s+(.+)$/i);
  if (!m) return res.status(401).json({ error: "missing bearer" });
  try {
    (req as any).auth = verifyToken(m[1]);
    next();
  } catch {
    return res.status(401).json({ error: "invalid token" });
  }
}

export function requirePerm(perm: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    const auth = (req as any).auth as AuthPayload | undefined;
    if (!auth?.perms || !auth.perms.includes(perm)) {
      return res.status(403).json({ error: "missing permission" });
    }
    next();
  };
}
