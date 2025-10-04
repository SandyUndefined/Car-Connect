import "dotenv/config";
import express from "express";
import http from "http";
import cors from "cors";
import { Server } from "socket.io";
import { StatusCodes } from "http-status-codes";
import Redis from "ioredis";
import jwt from "jsonwebtoken";
import { getTurnCredentials } from "./turn.js";

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

const redis = new Redis(process.env.REDIS_URL);

const membersKey = (roomId: string) => `room:${roomId}:members`;
const socketsKey = (roomId: string) => `room:${roomId}:sockets`;

app.get("/health", (_req, res) => res.status(StatusCodes.OK).json({ ok: true }));
app.post("/turn-cred", getTurnCredentials);

// (stub) Create room
app.post("/v1/rooms", (req, res) => {
  const { hostId, mode } = req.body ?? {};
  const id = "room_" + Math.random().toString(36).slice(2, 10);
  const room = { id, hostId, mode: mode ?? "mesh", createdAt: new Date().toISOString() };
  redis.set(`room:${id}`, JSON.stringify(room));
  const token = jwt.sign({ roomId: id, role: "host" }, process.env.JWT_SECRET!, { expiresIn: "2h" });
  res.json({ room, token });
});

// (stub) Join room
app.post("/v1/rooms/:id/join", async (req, res) => {
  const roomId = req.params.id;
  const room = await redis.get(`room:${roomId}`);
  if (!room) return res.status(StatusCodes.NOT_FOUND).json({ error: "room not found" });
  const token = jwt.sign({ roomId, role: "participant" }, process.env.JWT_SECRET!, { expiresIn: "2h" });
  res.json({ token });
});

// Socket.IO signaling events
io.use((socket, next) => {
  // Expect: { token } from client in connection auth
  const token = socket.handshake.auth?.token as string | undefined;
  if (!token) return next(new Error("missing token"));
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET!) as any;
    (socket as any).auth = payload; // { roomId, role, userId }
    return next();
  } catch {
    return next(new Error("invalid token"));
  }
});

io.on("connection", (socket) => {
  const { roomId, userId } = (socket as any).auth || {};
  if (!roomId || !userId) {
    socket.disconnect(true);
    return;
  }

  // Join the room
  socket.join(roomId);

  // Track presence
  redis.sadd(membersKey(roomId), userId);
  redis.hset(socketsKey(roomId), socket.id, userId);

  // Notify others
  socket.to(roomId).emit("participantJoined", { userId, socketId: socket.id });

  // Heartbeat (optional)
  socket.on("ping", () => socket.emit("pong", { t: Date.now() }));

  // WebRTC signaling pass-through
  // payload: { toSocketId?: string, data: any }
  socket.on("signal", ({ toSocketId, data }) => {
    if (toSocketId) {
      io.to(toSocketId).emit("signal", { fromSocketId: socket.id, fromUserId: userId, data });
    } else {
      socket.to(roomId).emit("signal", { fromSocketId: socket.id, fromUserId: userId, data });
    }
  });

  // Mute / video toggle
  socket.on("mute", ({ muted }) => {
    socket.to(roomId).emit("mute", { userId, muted: !!muted });
  });

  socket.on("videoToggle", ({ enabled }) => {
    socket.to(roomId).emit("videoToggle", { userId, enabled: !!enabled });
  });

  // Active speaker (client sends audio level)
  socket.on("audioLevel", ({ level }) => {
    socket.to(roomId).emit("audioLevel", { userId, level });
  });

  // Leave
  socket.on("leaveRoom", async () => {
    await redis.hdel(socketsKey(roomId), socket.id);
    socket.leave(roomId);
    socket.to(roomId).emit("participantLeft", { userId, socketId: socket.id });

    // if no sockets for room, maybe cleanup members entry for user
    const userStillPresent = (await redis.hvals(socketsKey(roomId))).includes(userId);
    if (!userStillPresent) {
      await redis.srem(membersKey(roomId), userId);
    }
  });

  socket.on("disconnect", async () => {
    await redis.hdel(socketsKey(roomId), socket.id);
    socket.to(roomId).emit("participantLeft", { userId, socketId: socket.id });
    const userStillPresent = (await redis.hvals(socketsKey(roomId))).includes(userId);
    if (!userStillPresent) {
      await redis.srem(membersKey(roomId), userId);
    }
  });
});

const port = Number(process.env.PORT) || 8080;
server.listen(port, () => console.log(`signaling listening on :${port}`));
