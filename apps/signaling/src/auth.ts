import jwt from "jsonwebtoken";
import { Request, Response, NextFunction } from "express";

export interface AuthPayload {
  roomId?: string;
  role?: "host" | "participant";
  userId?: string;
}

export function signToken(payload: AuthPayload, ttl = "2h") {
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
