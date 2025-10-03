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

## Local Dev

### Terminal A: Infra

```bash
pnpm dev:stack    # starts redis + coturn
```

### Terminal B: Signaling API

```bash
cp apps/signaling/.env.example apps/signaling/.env
pnpm dev:signaling
```

### Terminal C: Flutter Mobile (run emulator or real device)

```bash
cd apps/mobile
flutter pub get
flutter run -d <your_device>  # ensure signalingBase points to your machine IP
```

> **Note:** On-device testing requires replacing `http://localhost:8080` with your host LAN IP in `Env.signalingBase`, or passing `--dart-define=SIGNALING_BASE="http://<LAN_IP>:8080"` when launching the Flutter app.
