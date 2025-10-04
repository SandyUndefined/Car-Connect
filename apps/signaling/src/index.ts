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
io.on("connection", (socket) => {
  socket.on("joinRoom", async ({ roomId, userId }) => {
    socket.join(roomId);
    io.to(roomId).emit("participantJoined", { userId, socketId: socket.id });
  });

  socket.on("signal", ({ roomId, from, to, data }) => {
    if (to) {
      io.to(to).emit("signal", { from, data }); // direct
    } else {
      socket.to(roomId).emit("signal", { from, data }); // broadcast
    }
  });

  socket.on("mute", ({ roomId, userId, muted }) => {
    socket.to(roomId).emit("mute", { userId, muted });
  });

  socket.on("videoToggle", ({ roomId, userId, enabled }) => {
    socket.to(roomId).emit("videoToggle", { userId, enabled });
  });

  socket.on("leaveRoom", ({ roomId, userId }) => {
    socket.leave(roomId);
    socket.to(roomId).emit("participantLeft", { userId, socketId: socket.id });
  });
});

const port = Number(process.env.PORT) || 8080;
server.listen(port, () => console.log(`signaling listening on :${port}`));
