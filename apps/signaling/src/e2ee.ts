import { redis } from "./redis.js";

const RK = (roomId: string) => `room:${roomId}:e2eeKey`;

export async function setRoomKey(roomId: string, keyB64: string) {
  await redis.set(RK(roomId), keyB64);
}

export async function getRoomKey(roomId: string) {
  return (await redis.get(RK(roomId))) || null;
}
