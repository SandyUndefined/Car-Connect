# Car-Connect Signaling Service

Node.js/Express signaling API using Socket.IO for WebRTC coordination.

## Local Development

```bash
pnpm dev
docker compose up redis coturn
```

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
