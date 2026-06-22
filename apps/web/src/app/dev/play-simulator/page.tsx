import { notFound } from "next/navigation";
import { fetchCardVisuals } from "@/lib/scryfall-cards";
import { createRuntimeEngineAdapter } from "@/lib/engine";
import { GameController } from "../../play/GameController";
import { arenaDemoCardNames, createArenaDemoConfig } from "../../play/demo-game";

export const dynamic = "force-dynamic";

export default async function PlaySimulatorPage() {
  if (process.env.NODE_ENV !== "development") {
    return notFound();
  }

  const config = createArenaDemoConfig();
  const [visuals, engineHealth] = await Promise.all([
    fetchCardVisuals(arenaDemoCardNames),
    createRuntimeEngineAdapter({ mode: "mock" }).getHealth()
  ]);

  return (
    <GameController
      config={config}
      initialHealth={engineHealth}
      simulatorMode
      visuals={Object.fromEntries(visuals)}
    />
  );
}
