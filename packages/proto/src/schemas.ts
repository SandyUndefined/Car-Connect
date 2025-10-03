export interface User {
  id: string;
  displayName: string;
  avatarUrl?: string;
}

export interface Room {
  id: string;
  hostId: string;
  mode: "mesh" | "sfu";
  createdAt: string; // ISO
  locked?: boolean;
}

export interface TurnCredential {
  username: string;
  credential: string;
  expiresAt: number;
}

export interface JoinRoomResponse {
  roomToken: string;
  iceServers: Array<{ urls: string | string[]; username?: string; credential?: string }>;
}
