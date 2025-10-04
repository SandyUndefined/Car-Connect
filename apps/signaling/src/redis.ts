import Redis from "ioredis";
export const redis = new Redis(process.env.REDIS_URL);

export const roomKey = (id: string) => `room:${id}`;
export const membersKey = (id: string) => `room:${id}:members`;
export const socketsKey = (id: string) => `room:${id}:sockets`;
