export type AuditEvent =
  | { t: "join"; roomId: string; userId: string }
  | { t: "leave"; roomId: string; userId: string }
  | { t: "muteAll"; roomId: string; userId: string }
  | { t: "remove"; roomId: string; userId: string; target: string }
  | { t: "lock"; roomId: string; userId: string; locked: boolean };

export function audit(ev: AuditEvent) {
  // For now, just console.log; later ship to a log collector
  console.log("[AUDIT]", new Date().toISOString(), JSON.stringify(ev));
}
