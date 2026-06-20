import { fetchCardVisuals } from "@/lib/scryfall-cards";
import { createRuntimeEngineAdapter } from "@/lib/engine";
import { createArenaDemoConfig, arenaDemoCardNames } from "./demo-game";
import { GameController } from "./GameController";

export const dynamic = "force-dynamic";

export default async function PlayPage() {
  const config = createArenaDemoConfig();
  const [visuals, engineHealth] = await Promise.all([
    fetchCardVisuals(arenaDemoCardNames),
    createRuntimeEngineAdapter().getHealth()
  ]);

  return (
    <GameController
      config={config}
      initialHealth={engineHealth}
      simulatorMode={process.env.ENGINE_MODE !== "xmage"}
      visuals={Object.fromEntries(visuals)}
    />
  );
}
