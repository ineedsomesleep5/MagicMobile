import { describe, expect, it } from "vitest";
import { POST as createCommanderGame } from "../commander/route";
import { GET as getGame } from "./[gameId]/route";
import { GET as getLegalActions } from "./[gameId]/legal-actions/route";
import { POST as postCommand } from "./[gameId]/commands/route";
import { createArenaDemoConfig } from "@/app/play/demo-game";

async function json<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

describe("engine game API routes", () => {
  it("creates a simulator Commander game, reads legal actions, and submits an engine command", async () => {
    const config = createArenaDemoConfig();
    const createResponse = await createCommanderGame(
      new Request("http://magicmobile.test/api/engine/commander", {
        method: "POST",
        body: JSON.stringify(config)
      })
    );
    const created = await json<{ id: string; legalActions: Array<{ type: string; cardInstanceId?: string }> }>(createResponse);

    const context = { params: Promise.resolve({ gameId: created.id }) };
    const gameResponse = await getGame(new Request(`http://magicmobile.test/api/engine/games/${created.id}`), context);
    await expect(json<{ id: string }>(gameResponse)).resolves.toMatchObject({ id: created.id });

    const legalResponse = await getLegalActions(
      new Request(`http://magicmobile.test/api/engine/games/${created.id}/legal-actions?playerId=human`),
      context
    );
    const legalActions = await json<Array<{ type: string; cardInstanceId?: string }>>(legalResponse);
    const tapAction = legalActions.find((action) => action.type === "tap_permanent");
    expect(tapAction?.cardInstanceId).toBeTruthy();

    const commandResponse = await postCommand(
      new Request(`http://magicmobile.test/api/engine/games/${created.id}/commands`, {
        method: "POST",
        body: JSON.stringify({
          type: "tap_permanent",
          gameId: created.id,
          playerId: "human",
          cardInstanceId: tapAction?.cardInstanceId
        })
      }),
      context
    );
    const afterCommand = await json<{ players: Array<{ playerId: string; zones: { battlefield: Array<{ instanceId: string; tapped?: boolean }> } }> }>(
      commandResponse
    );
    const human = afterCommand.players.find((player) => player.playerId === "human");
    expect(human?.zones.battlefield.find((card) => card.instanceId === tapAction?.cardInstanceId)).toMatchObject({ tapped: true });
  });
});
