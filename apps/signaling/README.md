# Car-Connect Signaling Service

Node.js/Express signaling API using Socket.IO for WebRTC coordination.

## Local Development

```bash
pnpm dev
docker compose up redis coturn
```

## Phase 2 Sanity Checklist

1. `docker compose -f infra/docker-compose.yml up redis coturn`
2. `cp apps/signaling/.env.example apps/signaling/.env`
3. `pnpm dev:signaling`
4. `curl http://localhost:8080/health -> { ok: true }`
5. `curl -X POST http://localhost:8080/v1/rooms -H "Content-Type: application/json" -d '{"hostId":"host_1","mode":"mesh"}'`
6. `curl -X POST http://localhost:8080/v1/rooms/<ROOM_ID>/join -H "Content-Type: application/json" -d '{"userId":"user_2"}'`
7. `curl -X POST http://localhost:8080/turn-cred -H "Content-Type: application/json" -d '{"userId":"user_2"}'`
8. `pnpm --filter @apps/signaling run test:socket -> see join + signal logs`

**Notes**

- TURN shared-secret must match coturn’s static secret.
- For public cloud deployments add `--external-ip` to coturn.
- Tokens expire in 6h; refresh strategy coming in Phase 5.

## HTTP Endpoints

- `GET /health`
- `POST /v1/rooms`
- `POST /v1/rooms/:id/join`
- `GET /turn-cred`

## Socket.IO Events

- `joinRoom`
- `signal`
- `mute`
- `videoToggle`
- `leaveRoom`
