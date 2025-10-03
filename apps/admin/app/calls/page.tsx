const activeRooms: Array<{ id: string; title: string }> = [
  { id: "room-1", title: "Demo Room 1" },
  { id: "room-2", title: "Demo Room 2" },
];

export default function CallsPage() {
  return (
    <main>
      <h1>Active Calls</h1>
      <p>Rooms fetched from the signaling service will appear here.</p>
      <ul>
        {activeRooms.map((room) => (
          <li key={room.id}>
            <strong>{room.title}</strong>
            <div>ID: {room.id}</div>
          </li>
        ))}
      </ul>
    </main>
  );
}
