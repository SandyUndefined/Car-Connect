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

## Troubleshooting

- Seeing a black video feed? Double-check that the browser or device has granted camera and microphone permissions and that the WebRTC tracks are enabled in your code.
- Peers cannot connect across different networks? Verify that TURN is operating correctly: hit `/turn-cred` and ensure it returns a username/credential, inspect the coturn container logs for active allocations, and if you are deploying in the cloud make sure coturn runs with `--external-ip` and that UDP/TCP port `3478` is open in your firewall/security group.
- WebRTC Offer/Answer not taking effect? Confirm that the signaling payload uses the same `signal` keys on both the sender and receiver so the SDP is properly applied.
- Running on an Android emulator? Use `10.0.2.2` instead of `localhost` when you need to hit services running on the host machine.
- Testing on a physical iOS device connected to your LAN? Point `SIGNALING_BASE` to your Mac's LAN IP address so the phone can reach the signaling server.
