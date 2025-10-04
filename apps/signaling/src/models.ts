export type RoomMode = "mesh" | "sfu";
export interface Room {
  id: string;
  hostId: string;
  mode: RoomMode;
  createdAt: string;
  locked?: boolean;
}
