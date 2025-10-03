# Car-Connect Monorepo

This repository is organized as a pnpm-based monorepo that groups the mobile client, signaling server, and supporting infrastructure under a single workspace.

## Structure

```
.
├─ apps/
│  ├─ mobile/                # Flutter app
│  ├─ signaling/             # Node/Express + Socket.IO signaling API
│  └─ admin/                 # (Optional) Next.js admin dashboard
├─ packages/
│  └─ proto/                 # Shared TypeScript interfaces/schemas
├─ infra/                    # Docker, IaC, local dev services
├─ .editorconfig
├─ .gitignore
├─ .nvmrc
├─ README.md
├─ package.json
├─ pnpm-workspace.yaml
└─ tsconfig.base.json
```

Each directory currently contains placeholder files and can be expanded with application-specific code as the project evolves.
