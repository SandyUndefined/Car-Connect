# Car-Connect Applications

This directory contains the runnable apps that make up the Car-Connect experience.
Follow the sections below to install dependencies and run each service locally.

## Prerequisites

- **Node.js 20+** and **pnpm 9+** (the root `package.json` pins the workspace to `pnpm@9.0.0`).
- **Docker** for Redis + coturn (TURN) via `infra/docker-compose.yml`.
- **Flutter 3.x** SDK and a configured iOS/Android simulator or device for the mobile app.
- Optional: a TURN- or SFU-friendly network setup if you want to test peer-to-peer media across networks.

> If you are new to the repo, run `pnpm install` from the repository root before starting any app.

## Shared Setup

1. Start the shared infrastructure stack (Redis + coturn):
   ```bash
   pnpm dev:stack
   ```
   The command is equivalent to `docker compose -f infra/docker-compose.yml up` and should be left running in its own terminal.
2. Copy environment templates to real files for services that need them:
   ```bash
   cp apps/signaling/.env.example apps/signaling/.env
   cp apps/sfu/.env.example apps/sfu/.env
   ```
   Adjust hostnames or credentials if you are not running everything on `localhost`.

With the infrastructure online you can start any of the applications below in separate terminals.

## Signaling API (`apps/signaling`)

The Node.js/Express + Socket.IO service that coordinates WebRTC rooms.

```bash
pnpm dev:signaling
```

- The server listens on `http://localhost:8080` by default.
- Verify the service by hitting the health endpoint:
  ```bash
  curl http://localhost:8080/health
  ```
- Additional smoke tests:
  ```bash
  curl -X POST http://localhost:8080/v1/rooms \
       -H "Content-Type: application/json" \
       -d '{"hostId":"host_1","mode":"mesh"}'
  curl -X POST http://localhost:8080/v1/rooms/<ROOM_ID>/join \
       -H "Content-Type: application/json" \
       -d '{"userId":"user_2"}'
  curl -X POST http://localhost:8080/turn-cred \
       -H "Content-Type: application/json" \
       -d '{"userId":"user_2"}'
  ```

## SFU Service (`apps/sfu`)

Mediasoup-powered Selective Forwarding Unit that offloads media routing.

```bash
pnpm dev:sfu
```

- Exposes its HTTP control surface on `http://localhost:9090` by default (configurable via `.env`).
- Make sure Redis and the signaling API are running so the SFU can coordinate room state.

## Admin Dashboard (`apps/admin`)

Next.js dashboard for operational tooling.

```bash
pnpm dev:admin
```

- Opens on [http://localhost:3000](http://localhost:3000).
- Uses the same `.env.local` conventions as any Next.js project if you need to point it at non-default APIs.

## Mobile App (`apps/mobile`)

Flutter client that connects to the signaling API and optional SFU.

```bash
cd apps/mobile
flutter pub get
flutter run -d <device_id> \
  --dart-define=SIGNALING_BASE="http://<your_host_ip>:8080"
```

- Replace `<your_host_ip>` with your machine's LAN IP when running on a physical device or emulator that cannot hit `localhost` directly (e.g., `10.0.2.2` for the Android emulator).
- Use additional `--dart-define` values if you expose SFU endpoints or TURN credentials.

## Stopping Services

When you are done, stop each foreground process with `Ctrl+C` and bring down the Docker stack:

```bash
docker compose -f infra/docker-compose.yml down
```

This ensures Redis and coturn containers shut down cleanly.
