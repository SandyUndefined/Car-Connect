import { Request, Response } from "express";

export const getTurnCredentials = async (_req: Request, res: Response) => {
  // For now, return static TURN creds (replace with dynamic/temporary).
  const iceServers = [
    { urls: ["stun:stun.l.google.com:19302"] },
    {
      urls: ["turn:localhost:3478?transport=udp", "turn:localhost:3478?transport=tcp"],
      username: process.env.TURN_STATIC_USERNAME || "demo",
      credential: process.env.TURN_STATIC_CREDENTIAL || "demo"
    }
  ];
  res.json({ iceServers });
};
