import { DigitalSeat, HybridSeat, WebcamSeat } from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";
import { roomSeats } from "@/lib/mock-data";

export default async function RoomPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  return (
    <>
      <PageHeader title="Room" kicker={id} />
      <section className="room-grid">
        <div className="battlefield-preview">
          <div className="seat-grid">
            {roomSeats.map((seat) => {
              if (seat.type === "digital") return <DigitalSeat key={seat.name} name={seat.name} status={seat.status} />;
              if (seat.type === "webcam") return <WebcamSeat key={seat.name} name={seat.name} status={seat.status} />;
              return <HybridSeat key={seat.name} name={seat.name} status={seat.status} />;
            })}
          </div>
        </div>
        <aside className="panel">
          <h2>Room setup</h2>
          <p className="muted">Mock room state. Realtime room APIs are owned by the multiplayer workstream.</p>
          <table className="dev-table">
            <tbody>
              <tr>
                <th>Status</th>
                <td>Lobby</td>
              </tr>
              <tr>
                <th>Seats</th>
                <td>Digital, webcam, hybrid</td>
              </tr>
            </tbody>
          </table>
        </aside>
      </section>
    </>
  );
}
