import { Request, Response } from "express";
import crypto from "crypto";

function hmacSha1(key: string, content: string) {
  return crypto.createHmac("sha1", key).update(content).digest("base64");
}

/**
 * TURN REST API (time-limited) credentials:
 * username = `${unixTs}:${userId}`
 * credential = base64(hmac_sha1(shared_secret, username))
 * expiry: client should refresh before ts
 */
export const getTurnCredentials = async (req: Request, res: Response) => {
  const { userId = "anon" } = req.body ?? {};
  const ttlSeconds = 3600; // 1 hour
  const ts = Math.floor(Date.now() / 1000) + ttlSeconds;

  const secret = process.env.TURN_SHARED_SECRET || "my-super-secret";
  const username = `${ts}:${userId}`;
  const credential = hmacSha1(secret, username);

  const host = process.env.TURN_HOST ?? "localhost";
  const port = process.env.TURN_PORT ?? "3478";
  const realm = process.env.TURN_REALM ?? "example.com";

  const iceServers = [
    { urls: [`stun:${host}:${port}`] },
    {
      urls: [`turn:${host}:${port}?transport=udp`, `turn:${host}:${port}?transport=tcp`],
      username,
      credential
    }
  ];

  res.json({ iceServers, ttlSeconds, realm });
};
