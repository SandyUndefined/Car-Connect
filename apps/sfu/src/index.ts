import "dotenv/config";
import express from "express";
import http from "http";
import cors from "cors";
import { StatusCodes } from "http-status-codes";
import { Server } from "socket.io";
import Redis from "ioredis";
import jwt from "jsonwebtoken";
import * as mediasoup from "mediasoup";

// ---- Env
const PORT = Number(process.env.PORT || 9090);
type Jwk = { kid: string; secret: string };
const KEYSET: Jwk[] = JSON.parse(
  process.env.JWT_KEYS || '[{"kid":"dev","secret":"dev-secret"}]',
);
const ACTIVE = KEYSET[0];

function verifyToken(token: string) {
  const decoded = jwt.decode(token, { complete: true }) as any;
  const kid = decoded?.header?.kid;
  const key = KEYSET.find((k) => k.kid === kid) || ACTIVE;
  return jwt.verify(token, key.secret) as any;
}
const redis = new Redis(process.env.REDIS_URL);

// ---- App
const app = express();
app.use(cors());
app.use(express.json());
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

// ---- Mediasoup worker & router
let worker: mediasoup.types.Worker;
let router: mediasoup.types.Router;
let audioLevelObserver: mediasoup.types.AudioLevelObserver;

// TODO: spawn one worker per CPU core and shard rooms across workers when scaling.
async function createWorker() {
  worker = await mediasoup.createWorker({
    rtcMinPort: 40000,
    rtcMaxPort: 49999,
    logLevel: "warn",
  });
  worker.on("died", () => {
    console.error("Mediasoup worker died. Exiting.");
    process.exit(1);
  });
  router = await worker.createRouter({
    mediaCodecs: [
      { kind: "audio", mimeType: "audio/opus", clockRate: 48000, channels: 2 },
      { kind: "video", mimeType: "video/VP8", clockRate: 90000, parameters: {} },
      // You can add H264/VP9/AV1 later
    ],
  });

  audioLevelObserver = await router.createAudioLevelObserver({
    interval: 800,
    threshold: -70,
    maxEntries: 1,
  });
}
await createWorker();

type RoomId = string;
type UserId = string;

type TransportSet = {
  send?: mediasoup.types.WebRtcTransport;
  recv?: mediasoup.types.WebRtcTransport;
};
type PerUser = {
  transports: TransportSet;
  producers: { audio?: mediasoup.types.Producer; video?: mediasoup.types.Producer };
  consumers: Map<string, mediasoup.types.Consumer>; // key by producerId
};

const rooms = new Map<RoomId, Map<UserId, PerUser>>();
const audioProducerRooms = new Map<string, { roomId: RoomId; userId: UserId }>();
const roomActiveSpeaker = new Map<RoomId, { userId?: UserId }>();

audioLevelObserver.on("volumes", (volumes) => {
  if (!volumes.length) return;
  const sorted = [...volumes].sort((a, b) => b.volume - a.volume);
  const { producer } = sorted[0];
  const info = audioProducerRooms.get(producer.id);
  if (!info) return;
  roomActiveSpeaker.set(info.roomId, { userId: info.userId });
});

audioLevelObserver.on("silence", () => {
  for (const roomId of roomActiveSpeaker.keys()) {
    roomActiveSpeaker.set(roomId, { userId: undefined });
  }
});

setInterval(() => {
  for (const [roomId] of rooms) {
    const active = roomActiveSpeaker.get(roomId)?.userId ?? null;
    io.to(roomId).emit("sfu.activeSpeaker", { userId: active });
  }
}, 1000);

function ensureRoom(roomId: RoomId) {
  if (!rooms.has(roomId)) rooms.set(roomId, new Map());
  if (!roomActiveSpeaker.has(roomId)) roomActiveSpeaker.set(roomId, { userId: undefined });
  return rooms.get(roomId)!;
}

function ensureUser(roomId: RoomId, userId: UserId) {
  const room = ensureRoom(roomId);
  if (!room.has(userId)) room.set(userId, { transports: {}, producers: {}, consumers: new Map() });
  return room.get(userId)!;
}

// ---- JWT gate for socket
io.use((socket, next) => {
  try {
    const token = socket.handshake.auth?.token as string;
    const payload = verifyToken(token); // { sub, roomId, role, perms }
    (socket as any).auth = payload;
    next();
  } catch (e) {
    next(new Error("invalid token"));
  }
});

io.on("connection", (socket) => {
  const { roomId, userId } = (socket as any).auth;
  const room = ensureRoom(roomId);
  ensureUser(roomId, userId);

  socket.join(roomId);

  socket.on("sfu.getRouterRtpCapabilities", (cb) => {
    cb(router.rtpCapabilities);
  });

  socket.on("sfu.createWebRtcTransport", async ({ direction }, cb) => {
    try {
      const transport = await router.createWebRtcTransport({
        listenIps: [{ ip: "0.0.0.0", announcedIp: process.env.ANNOUNCED_IP || undefined }],
        enableUdp: true,
        enableTcp: true,
        preferUdp: true,
        initialAvailableOutgoingBitrate: 1_500_000,
      });
      const user = ensureUser(roomId, userId);
      if (direction === "send") user.transports.send = transport;
      else user.transports.recv = transport;

      transport.on("dtlsstatechange", (state) => {
        if (state === "closed") transport.close();
      });
      transport.on("close", () => {});

      cb({
        id: transport.id,
        iceParameters: transport.iceParameters,
        iceCandidates: transport.iceCandidates,
        dtlsParameters: transport.dtlsParameters,
      });
    } catch (e) {
      cb({ error: String(e) });
    }
  });

  socket.on("sfu.connectTransport", async ({ transportId, dtlsParameters }, cb) => {
    const user = ensureUser(roomId, userId);
    const transport =
      user.transports.send?.id === transportId ? user.transports.send :
      user.transports.recv?.id === transportId ? user.transports.recv : undefined;
    if (!transport) return cb({ error: "transport not found" });
    await transport.connect({ dtlsParameters });
    cb({ ok: true });
  });

  socket.on("sfu.produce", async ({ kind, rtpParameters }, cb) => {
    const user = ensureUser(roomId, userId);
    const transport = user.transports.send!;
    const producer = await transport.produce({ kind, rtpParameters, appData: { userId, roomId } });
    if (kind === "audio") user.producers.audio = producer;
    if (kind === "video") user.producers.video = producer;

    if (kind === "audio") {
      audioProducerRooms.set(producer.id, { roomId, userId });
      try {
        await audioLevelObserver.addProducer({ producerId: producer.id });
      } catch (err) {
        console.warn("failed to add producer to audio observer", err);
      }
    }

    // notify others to consume
    socket.to(roomId).emit("sfu.newProducer", { userId, producerId: producer.id, kind });

    producer.on("transportclose", () => producer.close());
    producer.on("close", () => {
      if (kind === "audio") {
        audioProducerRooms.delete(producer.id);
        audioLevelObserver.removeProducer({ producerId: producer.id }).catch(() => {});
      }
    });
    cb({ id: producer.id });
  });

  socket.on("sfu.consume", async ({ producerId, rtpCapabilities }, cb) => {
    try {
      if (!router.canConsume({ producerId, rtpCapabilities })) return cb({ error: "cant consume" });
      const user = ensureUser(roomId, userId);
      const transport = user.transports.recv!;
      const consumer = await transport.consume({ producerId, rtpCapabilities, paused: false });
      user.consumers.set(consumer.id, consumer);

      consumer.on("transportclose", () => consumer.close());
      cb({
        id: consumer.id,
        producerId,
        kind: consumer.kind,
        rtpParameters: consumer.rtpParameters,
      });
    } catch (e) {
      cb({ error: String(e) });
    }
  });

  socket.on("disconnect", () => {
    const roomMap = rooms.get(roomId);
    if (!roomMap) return;
    const user = roomMap.get(userId);
    if (!user) return;

    user.consumers.forEach((c) => c.close());
    user.producers.audio?.close();
    user.producers.video?.close();
    user.transports.send?.close();
    user.transports.recv?.close();
    roomMap.delete(userId);
    if (roomMap.size === 0) {
      rooms.delete(roomId);
      roomActiveSpeaker.set(roomId, { userId: undefined });
    } else {
      const anyAudio = Array.from(roomMap.values()).some((p) => p.producers.audio);
      if (!anyAudio) roomActiveSpeaker.set(roomId, { userId: undefined });
    }
  });
});

app.get("/health", (_req, res) => res.status(StatusCodes.OK).json({ ok: true }));

server.listen(PORT, () => console.log(`SFU listening on :${PORT}`));
