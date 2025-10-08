import "dotenv/config";
import crypto from "crypto";
import express from "express";
import fs from "fs";
import http from "http";
import https from "https";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import slowDown from "express-slow-down";
import { Server } from "socket.io";
import { StatusCodes } from "http-status-codes";
import { requireBearer, requirePerm, signToken, verifyToken } from "./auth.js";
import type { AuthPayload } from "./auth.js";
import { ROLE_PERMS } from "./roles.js";
import { redis, roomKey, membersKey, socketsKey } from "./redis.js";
import { setRoomKey, getRoomKey } from "./e2ee.js";
import type { Room } from "./models.js";
import { getTurnCredentials } from "./turn.js";
import { audit } from "./audit.js";

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
app.use(slowDown({ windowMs: 60_000, delayAfter: 200, delayMs: 10 }));
app.use(cors());
app.use(express.json());

const enableTls = (process.env.ENABLE_TLS || "false") === "true";
let server: http.Server | https.Server;
if (enableTls) {
  const key = fs.readFileSync(process.env.TLS_KEY_PATH!);
  const cert = fs.readFileSync(process.env.TLS_CERT_PATH!);
  server = https.createServer({ key, cert }, app);
} else {
  server = http.createServer(app);
}

// TIP: In production prefer terminating TLS at an edge proxy and only allow WSS traffic upstream.
const io = new Server(server, { cors: { origin: "*" } });
io.engine.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  next();
});

// Socket connection limit per IP (very simple)
const ipConn: Record<string, number> = {};
io.engine.on("connection", (raw) => {
  const ip = ((raw as any).request.socket.remoteAddress as string | undefined) || "unknown";
  ipConn[ip] = (ipConn[ip] || 0) + 1;
  raw.on("close", () => {
    ipConn[ip] = Math.max(0, (ipConn[ip] || 1) - 1);
  });
});
io.use((socket, next) => {
  const ip = ((socket.request.socket as any).remoteAddress as string | undefined) || "unknown";
  if ((ipConn[ip] || 0) > 20) return next(new Error("too many connections from IP"));
  next();
});

const HOST_PERMS = [
  "room:read",
  "room:lock",
  "room:muteAll",
  "room:remove",
  "signal:send",
];

const PARTICIPANT_PERMS = ["signal:send"];

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

  audit({ t: "join", roomId, userId });

  res.json({ token: access, refresh });
});

app.post("/v1/rooms/:id/e2ee/set", requireBearer, requirePerm("room:lock"), async (req, res) => {
  const { keyB64 } = req.body ?? {};
  if (!keyB64) return res.status(StatusCodes.BAD_REQUEST).json({ error: "keyB64 required" });
  await setRoomKey(req.params.id, keyB64);
  io.to(req.params.id).emit("e2eeEnabled", {});
  res.json({ ok: true });
});

app.get("/v1/rooms/:id/e2ee/key", requireBearer, requirePerm("room:read"), async (req, res) => {
  const key = await getRoomKey(req.params.id);
  if (!key) return res.status(StatusCodes.NOT_FOUND).json({ error: "no key" });
  res.json({ keyB64: key });
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

app.post("/v1/rooms/:id/lock", requireBearer, requirePerm("room:lock"), async (req, res) => {
  const roomId = req.params.id;
  const raw = await redis.get(roomKey(roomId));
  if (!raw) return res.status(StatusCodes.NOT_FOUND).json({ error: "room not found" });
  const room = JSON.parse(raw) as Room;
  room.locked = true;
  await redis.set(roomKey(roomId), JSON.stringify(room));
  io.to(roomId).emit("roomLocked", { locked: true });
  const auth = (req as any).auth as AuthPayload | undefined;
  if (auth?.sub) {
    audit({ t: "lock", roomId, userId: auth.sub, locked: true });
  }
  res.json({ ok: true });
});

app.post("/v1/rooms/:id/unlock", requireBearer, requirePerm("room:lock"), async (req, res) => {
  const roomId = req.params.id;
  const raw = await redis.get(roomKey(roomId));
  if (!raw) return res.status(StatusCodes.NOT_FOUND).json({ error: "room not found" });
  const room = JSON.parse(raw) as Room;
  room.locked = false;
  await redis.set(roomKey(roomId), JSON.stringify(room));
  io.to(roomId).emit("roomLocked", { locked: false });
  const auth = (req as any).auth as AuthPayload | undefined;
  if (auth?.sub) {
    audit({ t: "lock", roomId, userId: auth.sub, locked: false });
  }
  res.json({ ok: true });
});

app.post("/v1/rooms/:id/muteAll", requireBearer, requirePerm("room:muteAll"), async (req, res) => {
  const roomId = req.params.id;
  io.to(roomId).emit("muteAll", {});
  const auth = (req as any).auth as AuthPayload | undefined;
  if (auth?.sub) {
    audit({ t: "muteAll", roomId, userId: auth.sub });
  }
  res.json({ ok: true });
});

app.post("/v1/rooms/:id/remove", requireBearer, requirePerm("room:remove"), async (req, res) => {
  const roomId = req.params.id;
  const { targetUserId } = req.body ?? {};
  if (!targetUserId)
    return res.status(StatusCodes.BAD_REQUEST).json({ error: "targetUserId required" });

  const map = await redis.hgetall(socketsKey(roomId));
  const entries = Object.entries(map ?? {});
  const targets = entries
    .filter(([, uid]) => uid === targetUserId)
    .map(([sid]) => sid);
  targets.forEach((sid) => io.sockets.sockets.get(sid)?.emit("removedByHost", { reason: "removed" }));
  const auth = (req as any).auth as AuthPayload | undefined;
  if (auth?.sub) {
    audit({ t: "remove", roomId, userId: auth.sub, target: targetUserId });
  }

  res.json({ ok: true, count: targets.length });
});

// Socket.IO signaling events
io.use((socket, next) => {
  try {
    const token =
      (socket.handshake.auth && (socket.handshake.auth as any).token) ||
      (socket.handshake.query && (socket.handshake.query as any).token);
    if (!token) return next(new Error("missing token"));
    const payload = verifyToken<{
      roomId: string;
      role: "host" | "participant";
      sub: string;
      perms?: string[];
    }>(token);
    (socket as any).auth = payload; // { roomId, role, sub }
    return next();
  } catch {
    next(new Error("invalid token"));
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

  audit({ t: "join", roomId, userId });

  await ensureRoomMode(roomId);

  // Heartbeat (optional)
  socket.on("ping", () => socket.emit("pong", { t: Date.now() }));

  // WebRTC signaling pass-through
  // payload: { toSocketId?: string, data: any }
  socket.on("signal", ({ toSocketId, data }) => {
    const a = (socket as any).auth;
    if (!a?.perms?.includes("signal:send")) return;
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
    audit({ t: "leave", roomId, userId });

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
