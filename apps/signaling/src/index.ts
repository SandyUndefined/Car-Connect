import "dotenv/config";
import crypto from "crypto";
import express from "express";
import http from "http";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import { Server } from "socket.io";
import { StatusCodes } from "http-status-codes";
import { requireBearer, requirePerm, signToken, verifyToken } from "./auth.js";
import { ROLE_PERMS } from "./roles.js";
import { redis, roomKey, membersKey, socketsKey } from "./redis.js";
import type { Room } from "./models.js";
import { getTurnCredentials } from "./turn.js";

const RT_PREFIX = "rt:"; // refresh token key
async function setRefreshToken(userId: string, token: string, ttlSec = 60 * 60 * 24 * 7) {
  await redis.setex(RT_PREFIX + userId, ttlSec, token);
}
async function checkRefreshToken(userId: string, token: string) {
  const v = await redis.get(RT_PREFIX + userId);
  return v === token;
}

const app = express();
app.use(helmet());
app.use(rateLimit({ windowMs: 60_000, max: 300 }));
app.use(cors());
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });
io.engine.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  next();
});

const ensureRoomMode = async (roomId: string) => {
  const [memberCount, roomRaw] = await Promise.all([
    redis.scard(membersKey(roomId)),
    redis.get(roomKey(roomId)),
  ]);

  if (!roomRaw) return;

  const room = JSON.parse(roomRaw) as Room;
  if (memberCount >= 5 && room.mode !== "sfu") {
    const updatedRoom: Room = { ...room, mode: "sfu" };
    await redis.set(roomKey(roomId), JSON.stringify(updatedRoom));
    io.to(roomId).emit("roomMode", { mode: "sfu" });
  }
};

app.get("/health", (_req, res) => res.status(StatusCodes.OK).json({ ok: true }));
app.get("/metrics", async (_req, res) => {
  const rooms = await redis.keys("room:*");
  const sockets = io.of("/").sockets.size;
  res.json({ rooms: rooms.length, sockets });
});
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

  const perms = ROLE_PERMS.host;
  const access = signToken({ sub: hostId, roomId: id, role: "host", perms }, "1h");
  const refresh = crypto.randomBytes(24).toString("base64url");
  await setRefreshToken(hostId, refresh);

  res.json({ room, token: access, refresh });
});

// Join room (returns JWT)
app.post("/v1/rooms/:id/join", async (req, res) => {
  const roomId = req.params.id;
  const { userId } = req.body ?? {};
  if (!userId) return res.status(StatusCodes.BAD_REQUEST).json({ error: "userId required" });

  const raw = await redis.get(roomKey(roomId));
  if (!raw) return res.status(StatusCodes.NOT_FOUND).json({ error: "room not found" });

  const perms = ROLE_PERMS.participant;
  const access = signToken({ sub: userId, roomId, role: "participant", perms }, "1h");
  const refresh = crypto.randomBytes(24).toString("base64url");
  await setRefreshToken(userId, refresh);

  res.json({ token: access, refresh });
});

app.post("/auth/refresh", async (req, res) => {
  const { userId, refresh } = req.body ?? {};
  if (!userId || !refresh) return res.status(StatusCodes.BAD_REQUEST).json({ error: "missing fields" });

  const ok = await checkRefreshToken(userId, refresh);
  if (!ok) return res.status(StatusCodes.UNAUTHORIZED).json({ error: "invalid refresh" });

  // Require client to send last access token (optional, for rotation)
  // Recreate token with same role/perms by reading room membership
  // Here, client must also send roomId.
  const { roomId, role } = req.body ?? {};
  if (!roomId || !role) return res.status(StatusCodes.BAD_REQUEST).json({ error: "missing room context" });

  const perms = ROLE_PERMS[role as "host" | "participant"];
  if (!perms) return res.status(StatusCodes.BAD_REQUEST).json({ error: "unknown role" });
  const newAccess = signToken({ sub: userId, roomId, role, perms }, "1h");
  res.json({ token: newAccess });
});

// Protected: room details (debug)
app.get("/v1/rooms/:id", requireBearer, requirePerm("room:read"), async (req, res) => {
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
    const payload = verifyToken<{
      roomId: string;
      role: "host" | "participant";
      sub: string;
      perms?: string[];
    }>(token);
    (socket as any).auth = payload; // { roomId, role, sub }
    return next();
  } catch {
    return next(new Error("invalid token"));
  }
});

io.on("connection", async (socket) => {
  const { roomId, sub: userId } = (socket as any).auth || {};
  if (!roomId || !userId) {
    socket.disconnect(true);
    return;
  }

  // Join the room
  socket.join(roomId);

  // Track presence
  await redis.sadd(membersKey(roomId), userId);
  await redis.hset(socketsKey(roomId), socket.id, userId);

  // Notify others
  socket.to(roomId).emit("participantJoined", { userId, socketId: socket.id });

  await ensureRoomMode(roomId);

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
      await ensureRoomMode(roomId);
    }
  });

  socket.on("disconnect", async () => {
    await redis.hdel(socketsKey(roomId), socket.id);
    socket.to(roomId).emit("participantLeft", { userId, socketId: socket.id });
    const userStillPresent = (await redis.hvals(socketsKey(roomId))).includes(userId);
    if (!userStillPresent) {
      await redis.srem(membersKey(roomId), userId);
      await ensureRoomMode(roomId);
    }
  });
});

const port = Number(process.env.PORT) || 8080;
server.listen(port, () => console.log(`signaling listening on :${port}`));
