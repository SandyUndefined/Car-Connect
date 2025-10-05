import jwt from "jsonwebtoken";
import { Request, Response, NextFunction } from "express";
import { ROLE_PERMS, Perm, Role, hasPerm } from "./roles.js";

/**
 * Key rotation: support multiple secrets with "kid".
 * ENV: JWT_KEYS='[{"kid":"k1","secret":"<long-random>"},{"kid":"k0","secret":"<old>"}]'
 * Active key is first element.
 */
type Jwk = { kid: string; secret: string };
const KEYSET: Jwk[] = JSON.parse(
  process.env.JWT_KEYS || '[{"kid":"dev","secret":"dev-secret"}]'
);
const ACTIVE = KEYSET[0];

export interface AuthPayload {
  sub: string; // userId
  roomId: string;
  role: Role;
  perms: Perm[];
}

export function signToken(payload: AuthPayload, ttl = "1h") {
  return jwt.sign(payload, ACTIVE.secret, {
    expiresIn: ttl,
    header: { kid: ACTIVE.kid },
  });
}

export function verifyToken<T = AuthPayload>(token: string): T {
  const decoded = jwt.decode(token, { complete: true }) as any;
  const kid = decoded?.header?.kid;
  const key = KEYSET.find((k) => k.kid === kid) || ACTIVE;
  return jwt.verify(token, key.secret) as T;
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

export function requirePerm(p: Perm) {
  return (req: Request, res: Response, next: NextFunction) => {
    const auth = (req as any).auth as AuthPayload | undefined;
    if (!auth) return res.status(401).json({ error: "unauthorized" });
    const perms = auth.perms?.length ? auth.perms : ROLE_PERMS[auth.role];
    if (!perms || !hasPerm(perms, p)) return res.status(403).json({ error: "forbidden" });
    next();
  };
}
