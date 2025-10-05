# SFU Mesh Auto-Switch Test Plan

This document captures the test scenario requested for verifying the mesh-to-SFU autoswitch behaviour.

## Environment Preparation
1. Start the infrastructure services:
   ```bash
   docker compose -f infra/docker-compose.yml up redis coturn
   ```
2. Launch the SFU app stack:
   ```bash
   pnpm --filter @apps/sfu dev
   pnpm --filter @apps/signaling dev
   ```

## Manual Verification Steps
1. Launch the Flutter client on four devices (or simulators) and join the same room. The room should remain in mesh mode.
2. Join the room with a fifth device.
   - The signaling service should emit `roomMode:{sfu}`.
   - Mobile clients should transition to the SFU screen automatically.
3. Confirm that every participant still sees and hears all others. Expect one uplink per participant and downlinks coming from the SFU.

## Expected Logs
- The SFU logs should show the creation of new transports, producers, and consumers.
- TURN logs may contain allocation entries (optional to check).
- Ensure there are no ICE or DTLS errors.

## Troubleshooting Notes
- If media is missing when in SFU mode, verify that `ANNOUNCED_IP` resolves to a reachable public IP.
- Confirm that UDP ports `40000-49999` are open in the firewall.
- If the autoswitch threshold is incorrect, adjust the configured limit accordingly.

> **Note:** The above steps were not executed in this environment because Docker and Flutter tooling are not available in the container. Follow the procedure on a local machine or CI environment where the required dependencies exist.

## 2025-02-18 Environment Check

- Attempting to start the stack with `docker compose -f infra/docker-compose.yml up redis coturn` fails because Docker is not installed in the execution environment.
- Running `pnpm --filter @apps/signaling dev` cannot complete because the container lacks outbound network access to download the pinned pnpm release via Corepack.
- Due to the missing services, subsequent API verification steps (room locking, mute-all, host removal, token refresh over HTTP/HTTPS) could not be exercised here.
- Re-run the scenario on a workstation or CI runner that has Docker available and unrestricted access to the npm registry.
