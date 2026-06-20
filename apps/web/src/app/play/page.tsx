import { createEngineWorkerAdapter } from "@magicmobile/engine-worker";
import { Button, CommanderDamageGrid, GameLog, LifeTotalPanel, PhaseTracker, StackPanel } from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";

const playerIds = ["Ari", "Bo", "Cam"];

export default async function PlayPage() {
  const engine = createEngineWorkerAdapter();
  const snapshot = await engine.createGame({ playerIds, roomId: "mock-room" });
  const players = snapshot.players.map((player) => player.playerId);
  const commanderDamage = Object.fromEntries(
    snapshot.players.map((player) => [player.playerId, player.commanderDamage])
  );

  return (
    <>
      <PageHeader
        title="Play"
        kicker="Live table controls"
        actions={
          <>
            <Button tone="primary" size="lg">Pass Priority</Button>
            <Button size="lg">Draw Card</Button>
          </>
        }
      />
      <PhaseTracker activePhase={formatPhase(snapshot.phase)} />
      <section className="play-grid">
        <div className="battlefield-preview">
          <article className="feature">
            <h2>Mock engine game</h2>
            <p className="muted">Room {snapshot.roomId} is rendering through the shared EngineAdapter contract.</p>
          </article>
          <div className="three-column">
            {snapshot.players.map((player) => (
              <LifeTotalPanel
                key={player.playerId}
                playerName={player.playerId}
                life={player.life}
                poison={player.poison}
              />
            ))}
          </div>
          <div className="actions">
            <Button tone="danger" size="lg">Take Damage</Button>
            <Button size="lg">Cast Spell</Button>
            <Button size="lg">Move Card</Button>
          </div>
        </div>
        <aside className="list">
          <StackPanel spells={snapshot.players.flatMap((player) =>
            player.zones.stack.map((card) => ({ controller: player.playerId, id: card.instanceId, name: card.card.name }))
          )} />
          <CommanderDamageGrid players={players} damage={commanderDamage} />
          <GameLog entries={snapshot.log} />
        </aside>
      </section>
    </>
  );
}

function formatPhase(phase: string): string {
  if (phase === "precombat-main") return "Main";
  if (phase === "postcombat-main") return "Second Main";
  return phase.charAt(0).toUpperCase() + phase.slice(1);
}
