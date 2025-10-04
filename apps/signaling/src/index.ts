import "dotenv/config";
import crypto from "crypto";
import express from "express";
import http from "http";
import cors from "cors";
import { Server } from "socket.io";
import { StatusCodes } from "http-status-codes";
import { requireBearer, signToken } from "./auth.js";
import { redis, roomKey, membersKey, socketsKey } from "./redis.js";
import type { Room } from "./models.js";
import { getTurnCredentials } from "./turn.js";

const app = express();
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

app.get("/health", (_req, res) => res.status(StatusCodes.OK).json({ ok: true }));
app.post("/turn-cred", getTurnCredentials);

// Create room (host only, no auth required for first create)
app.post("/v1/rooms", async (req, res) => {
  const { hostId, mode } = req.body ?? {};
  if (!hostId) return res.status(StatusCodes.BAD_REQUEST).json({ error: "hostId required" });

  const id = "room_" + crypto.randomBytes(3).toString("hex");
  const room: Room = {
    id,
    hostId,
    mode: mode === "sfu" ? "sfu" : "mesh",
    createdAt: new Date().toISOString(),
  };
  await redis.set(roomKey(id), JSON.stringify(room));
  await redis.del(membersKey(id));
  await redis.del(socketsKey(id));

  const token = signToken({ roomId: id, role: "host", userId: hostId }, "6h");
  res.json({ room, token });
});

// Join room (returns JWT)
app.post("/v1/rooms/:id/join", async (req, res) => {
  const roomId = req.params.id;
  const { userId } = req.body ?? {};
  if (!userId) return res.status(StatusCodes.BAD_REQUEST).json({ error: "userId required" });

  const raw = await redis.get(roomKey(roomId));
  if (!raw) return res.status(StatusCodes.NOT_FOUND).json({ error: "room not found" });

  const token = signToken({ roomId, role: "participant", userId }, "6h");
  res.json({ token });
});

// Protected: room details (debug)
app.get("/v1/rooms/:id", requireBearer, async (req, res) => {
  const roomId = req.params.id;
  const raw = await redis.get(roomKey(roomId));
  if (!raw) return res.status(StatusCodes.NOT_FOUND).json({ error: "room not found" });
  const members = await redis.smembers(membersKey(roomId));
  res.json({ room: JSON.parse(raw), members });
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
