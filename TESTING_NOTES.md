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
