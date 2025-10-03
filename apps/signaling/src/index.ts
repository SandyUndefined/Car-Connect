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
