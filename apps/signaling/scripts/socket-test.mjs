import { io } from "socket.io-client";
import fetch from "node-fetch";

const base = "http://localhost:8080";

async function main() {
  // create room
  const r = await fetch(`${base}/v1/rooms`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ hostId: "host_1", mode: "mesh" })
  }).then(r => r.json());

  const roomId = r.room.id;
  const hostToken = r.token;

  // join as guest
  const j = await fetch(`${base}/v1/rooms/${roomId}/join`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ userId: "user_2" })
  }).then(r => r.json());

  const guestToken = j.token;

  const host = io(base, { auth: { token: hostToken } });
  const guest = io(base, { auth: { token: guestToken } });

  host.on("connect", () => console.log("host connected", host.id));
  guest.on("connect", () => console.log("guest connected", guest.id));

  host.on("participantJoined", (p) => console.log("host sees joined:", p));
  guest.on("participantJoined", (p) => console.log("guest sees joined:", p));

  guest.on("signal", (m) => console.log("guest got signal:", m));
  host.on("signal", (m) => console.log("host got signal:", m));

  // after both connected, send a sample signal
  setTimeout(() => {
    host.emit("signal", { data: { sdp: "OFFER" } });
  }, 1000);

  // exit after a bit
  setTimeout(() => { host.close(); guest.close(); process.exit(0); }, 4000);
}

main().catch(e => { console.error(e); process.exit(1); });
