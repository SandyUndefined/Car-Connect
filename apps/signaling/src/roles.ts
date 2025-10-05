export type Role = "host" | "participant";
export type Perm =
  | "room:read"
  | "room:write"
  | "room:lock"
  | "room:remove"
  | "room:muteAll"
  | "signal:send";

export const ROLE_PERMS: Record<Role, Perm[]> = {
  host: [
    "room:read",
    "room:write",
    "room:lock",
    "room:remove",
    "room:muteAll",
    "signal:send",
  ],
  participant: ["room:read", "signal:send"],
};

export function hasPerm(perms: Perm[], p: Perm) {
  return perms.includes(p);
}
