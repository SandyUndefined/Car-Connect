export type Role = "host" | "participant";

type RolePerms = Record<Role, string[]>;

export const ROLE_PERMS: RolePerms = {
  host: ["room:read", "room:write", "member:manage"],
  participant: ["room:read"],
};
