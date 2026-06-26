import { generateBracketThreeCommanderDeck } from "../../../packages/deck/src";
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const endpoint = (process.env.XMAGE_GATEWAY_URL ?? "http://localhost:17171").replace(/\/$/, "");
const workspaceRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const reportDirectory = path.join(workspaceRoot, "build_output", "smoke");
const latestReportPath = path.join(reportDirectory, "smoke-report.json");
const seed = process.env.XMAGE_SMOKE_SEED ?? "bridge-smoke";
const humanPlayerId = process.env.XMAGE_SMOKE_HUMAN_ID ?? "human";
const aiPlayerId = process.env.XMAGE_SMOKE_AI_ID ?? "ai-1";
const requestedScenario = process.env.XMAGE_SMOKE_SCENARIO ?? "core-flow";
if (requestedScenario === "commander-full-ai") {
  const report = await runCommanderFullAiGate();
  writeSmokeReportForScenario(report, "commander-full-ai");
  console.log(JSON.stringify(report, null, 2));
  if (!report.allRequiredScenariosPassed) {
    throw new Error(
      `[Smoke] commander-full-ai is not ready: ${report.stepsBlocked.join(", ") || "unknown blocker"}`
    );
  }
  process.exit(0);
}
if (requestedScenario === "prompt-variety") {
  const report = await runPromptVarietyGate();
  writeSmokeReportForScenario(report, "prompt-variety");
  console.log(JSON.stringify(report, null, 2));
  if (!report.allRequiredScenariosPassed) {
    throw new Error(
      `[Smoke] prompt-variety is not ready: ${report.stepsBlocked.join(", ") || "unknown blocker"}`
    );
  }
  process.exit(0);
}
const scenarioModule = scenarioModuleFor(requestedScenario);
const scenario = scenarioModule.id;
const manaRockScenario = scenario === "mana-rock";
const dragCastRegressionScenario = scenario === "drag-cast-regression";
const dragCastPhoneRegressionScenario = scenario === "drag-cast-phone-regression";
const manaRockLikeScenario = manaRockScenario || dragCastRegressionScenario || dragCastPhoneRegressionScenario;
const manaRockCardName = process.env.XMAGE_SMOKE_MANA_ROCK_CARD ?? (dragCastPhoneRegressionScenario ? "Circle of Flame" : "Sol Ring");
const alphaGameScenario = scenario === "core-flow";
const commanderGauntletScenario = scenario === "commander-gauntlet";
const blockerFlowScenario = scenario === "blocker-flow";
const damageAssignmentScenario = scenario === "damage-assignment";
const promptModeScenario = scenario === "prompt-mode";
const promptOrderScenario = scenario === "prompt-order";
const promptAmountScenario = scenario === "prompt-amount";
const promptMultiAmountScenario = scenario === "prompt-multi-amount" || scenario === "prompt-variety-multi-amount";
const promptPileScenario = scenario === "prompt-pile" || scenario === "prompt-variety-pile";
const activatedAbilityScenario = scenario === "activated-ability-stack";
const triggeredAbilityScenario = scenario === "triggered-ability-stack";
const fixtureScenario = scenarioModule.usesFixture;
const useFixtureHarness = process.env.XMAGE_USE_FIXTURE === "true";
const fixtureCallRequired = commanderGauntletScenario
  || activatedAbilityScenario
  || triggeredAbilityScenario
  || scenario === "prompt-variety"
  || scenario === "damage-assignment"
  || promptModeScenario
  || promptOrderScenario
  || promptAmountScenario
  || promptMultiAmountScenario
  || promptPileScenario;
const fixtureGateRequired = useFixtureHarness || fixtureCallRequired;
const aiDifficulty = process.env.XMAGE_SMOKE_AI_DIFFICULTY ?? "normal";
const routeFamiliesRequired = routeFamiliesRequiredForScenario(scenario);
const routeFamiliesSeen = new Set<string>();
let directStateSeeded = false;
let seededStateVerified = false;
let lastBridgeRevision: number | undefined;
let lastXmageCycle: number | undefined;
let health: any = null;
let promptModeChoiceSubmitted = false;
let promptModeChoiceResolved = false;
let promptOrderChoiceSubmitted = false;
let promptAmountChoiceSubmitted = false;
let promptMultiAmountChoiceSubmitted = false;
let promptMultiAmountChoiceResolved = false;
let promptPileChoiceSubmitted = false;
let promptPileChoiceResolved = false;
let damageAssignmentPromptSeen = false;
let damageAssignmentChoiceSubmitted = false;
let aiProgressObserved = false;
const promptSamples: any[] = [];

if (process.env.XMAGE_SMOKE_SELFTEST === "fixture-unavailable") {
  const selfTestReport = fixtureUnavailableReport({
    enabled: true,
    fixtureName: "commander-gauntlet",
    schemaVersion: 1,
    directStateSeeded: false,
    reason: "self-test deterministic fixture unavailable",
    productionDisabled: true,
    expectedRouteCoverage: commanderGauntletRouteFamiliesRequired()
  });
  writeSmokeReport(selfTestReport);
  console.log(JSON.stringify(selfTestReport, null, 2));
  console.error("[Smoke] deterministic fixture unavailable self-test");
  process.exit(1);
}

if (fixtureCallRequired && !useFixtureHarness) {
  const report = fixtureUnavailableReport({
    enabled: false,
    fixtureName: scenario,
    schemaVersion: 1,
    directStateSeeded: false,
    reason: `${scenario} requires the deterministic /dev/xmage-fixtures/commander setup route; run with XMAGE_USE_FIXTURE=true.`,
    productionDisabled: true,
    expectedRouteCoverage: routeFamiliesRequired
  });
  const blockedReport = {
    ...report,
    failedStep: "fixture-call-required",
    failureReason: `${scenario} must call the deterministic fixture route before submitting bridge commands.`
  };
  writeSmokeReport(blockedReport);
  console.log(JSON.stringify(blockedReport, null, 2));
  throw new Error(`[Smoke] ${scenario} requires XMAGE_USE_FIXTURE=true so setup uses the deterministic fixture route.`);
}

const fixtureEnvFailure = fixtureGateRequired ? fixtureEnvCheck() : null;
if (fixtureEnvFailure) {
  const report = fixtureUnavailableReport({
    enabled: true,
    fixtureName: scenario,
    schemaVersion: 1,
    directStateSeeded: false,
    reason: fixtureEnvFailure,
    productionDisabled: true,
    setupMethod: "fixture_env_check_failed",
    expectedRoutes: routeFamiliesRequired,
    expectedRouteCoverage: routeFamiliesRequired
  });
  writeSmokeReport(report);
  console.log(JSON.stringify(report, null, 2));
  throw new Error(`[Smoke] deterministic fixture unavailable: ${fixtureEnvFailure}`);
}

const human = fixtureScenario
  ? commanderGauntletScenario
    ? commanderGauntletHumanDeck()
    : activatedAbilityScenario
    ? activatedAbilityFixtureDeck()
    : triggeredAbilityScenario
    ? triggeredAbilityFixtureDeck()
    : dragCastPhoneRegressionScenario
    ? phoneDragCastFixtureDeck()
    : manaRockLikeScenario
    ? manaRockFixtureDeck()
    : promptModeScenario
    ? promptModeFixtureDeck()
    : promptOrderScenario
    ? promptOrderFixtureDeck()
    : promptAmountScenario
    ? promptAmountFixtureDeck()
    : promptMultiAmountScenario
    ? promptMultiAmountFixtureDeck()
    : promptPileScenario
    ? promptPileFixtureDeck()
    : scenario === "repeated-mulligan"
    ? repeatedMulliganFixtureDeck()
    : scenario === "choose-card"
    ? chooseCardFixtureDeck()
    : scenario === "choose-player"
    ? choosePlayerFixtureDeck()
    : scenario === "play-x-mana"
    ? playXManaFixtureDeck()
    : scenario === "choose-mana"
    ? chooseManaFixtureDeck()
    : scenario === "generic-replacement"
    ? genericReplacementFixtureDeck()
    : scenario === "zone-movement"
    ? zoneMovementFixtureDeck()
    : commanderFixtureDeck("Isamaru, Hound of Konda", "Plains")
  : generateBracketThreeCommanderDeck({ seed: `${seed}:human`, playerId: humanPlayerId }).deck;
const ai = fixtureScenario
  ? commanderGauntletScenario
    ? commanderGauntletAiDeck()
    : commanderFixtureDeck("Kozilek, Butcher of Truth", "Wastes")
  : generateBracketThreeCommanderDeck({ seed: `${seed}:ai`, playerId: aiPlayerId }).deck;
const fixtureSeed = fixtureGateRequired ? fixtureSeedSchema() : null;

health = await request("/health");
if (health.status !== "ready") {
  throw new Error(`XMage smoke requires ready health, received: ${JSON.stringify(health)}`);
}
const createPath = fixtureGateRequired ? "/dev/xmage-fixtures/commander" : "/games/commander";
const created = await request(createPath, {
  method: "POST",
  body: {
    scenario,
    scenarioName: scenario,
    seed,
    roomId: `smoke-${seed}`,
    humanPlayerId,
    humanDeck: human,
    aiPlayers: [{ playerId: aiPlayerId, displayName: "Noaddrag", difficulty: aiDifficulty, deck: ai }],
    startingLife: 40,
    commanderDamageEnabled: true,
    ...(fixtureSeed ?? {})
  }
});

let snapshot = created;
assertBridgeSnapshot(snapshot, "created game");
const activeFixtureHarness = snapshot.fixtureHarness ?? null;
directStateSeeded = activeFixtureHarness?.directStateSeeded === true;
seededStateVerified = verifySeededStateFromSnapshot(snapshot);
if (fixtureGateRequired && !activeFixtureHarness?.enabled) {
  throw new Error(
    "[Smoke] XMAGE_USE_FIXTURE=true but gateway did not return fixtureHarness metadata.\n"
      + smokeDebug("fixture harness startup snapshot", snapshot)
  );
}
if (fixtureGateRequired && (!directStateSeeded || !seededStateVerified)) {
  const report = fixtureUnavailableReport(activeFixtureHarness, snapshot);
  writeSmokeReport(report);
  console.log(JSON.stringify(report, null, 2));
  throw new Error(
    "[Smoke] fixture smoke requires deterministic real-XMage fixture seeding, "
      + `but fixtureHarness.directStateSeeded=${String(activeFixtureHarness?.directStateSeeded)} `
      + `and seededStateVerified=${String(seededStateVerified)}.\n`
      + smokeDebug("deterministic fixture unavailable", snapshot)
  );
}

const completed: string[] = [];
const promptChecks: string[] = [];
let combatExercised = false;
let blockerAssignmentExercised = false;
let combatStepSeen = false;
let aiWaits = 0;
let staleActionRecoveries = 0;
let stackSeen = false;
let manaRockCastSeen = false;
let manaRockResolvedSeen = false;
let manaRockPaymentSourceSeen = false;
let dragCastLandSeen = false;
const turnsObserved = new Set<number>();
const actionsByType: Record<string, number> = {};
const commanderTaxChanges: Array<{ playerId: string; tax: number; turn: number }> = [];
const commanderDamageChanges: Array<{ recipient: string; attacker: string; damage: number; turn: number }> = [];
let commanderBattlefieldSeen = false;
const gauntlet = {
  playedLand: false,
  castManaRock: false,
  tappedManaSource: false,
  fetchActivated: false,
  searchResolved: false,
  commanderCast: false,
  etbOrTriggerSeen: false,
  activatedAbilityUsed: false,
  stackObjectSeen: false,
  commanderRemoved: false,
  commanderReplacementAnswered: false,
  commanderRecastWithTax: false,
  aiTurnContinued: false
};
const gauntletPromptFamilies = new Set<string>();

recordCommanderState(snapshot);
recordCoverage(snapshot);
recordFixtureOpeningPromptCoverage(activeFixtureHarness);
console.error(`[Smoke] Started ${scenario} game ${snapshot.id}. Turn: ${snapshot.turn}, Phase: ${snapshot.phase}, Step: ${snapshot.step}`);
if (activeFixtureHarness) {
  console.error(
    `[Smoke] Fixture harness: directStateSeeded=${activeFixtureHarness.directStateSeeded}, fallback=${activeFixtureHarness.fallback ?? "none"}`
  );
}

const maxTurns = commanderGauntletScenario ? 16 : alphaGameScenario ? 13 : fixtureScenario ? 12 : 9; // Core flow observes 12 full turns.
const maxStepsCount = commanderGauntletScenario ? 900 : alphaGameScenario ? 900 : fixtureScenario ? 420 : 300; // Safeguard against infinite loops.
let stepCount = 0;

while (snapshot.turn < maxTurns && stepCount < maxStepsCount) {
  stepCount++;

  // 1. Check if game has ended
  const humanPlayer = snapshot.players?.find(p => p.playerId === humanPlayerId);
  const aiPlayer = snapshot.players?.find(p => p.playerId === aiPlayerId);
  if (humanPlayer && typeof humanPlayer.life === "number" && humanPlayer.life <= 0) {
    console.error(`[Smoke] Game ended: Human life is ${humanPlayer.life}`);
    break;
  }
  if (aiPlayer && typeof aiPlayer.life === "number" && aiPlayer.life <= 0) {
    console.error(`[Smoke] Game ended: AI life is ${aiPlayer.life}`);
    break;
  }

  // 2. Track commander tax and damage from authoritative XMage snapshots.
  recordCommanderState(snapshot);
  recordCoverage(snapshot);

  if (scenarioSatisfied()) {
    console.error(`[Smoke] ${scenario} scenario satisfied at turn ${snapshot.turn}, step ${snapshot.step}`);
    break;
  }
  if (isGameOverSnapshot(snapshot)) {
    console.error(`[Smoke] Game ended: XMage reported GAME_OVER`);
    break;
  }

  // 3. Check if human has legal actions
  const actionable = snapshot.legalActions?.some(a => a.type !== "concede") ?? false;
  const isHumanActive = snapshot.priorityPlayerId === humanPlayerId || snapshot.waitingOnPlayerId === humanPlayerId || actionable;

  if (isHumanActive) {
    const action = chooseBestAction(snapshot);
    if (!action) {
      console.error(`[Smoke] Human has priority/actions but no best action was chosen. Legal: ${formatActions(snapshot)}`);
      // Fallback: wait a bit and refresh
      await new Promise(resolve => setTimeout(resolve, 1000));
      snapshot = await request(`/games/${encodeURIComponent(snapshot.id)}`);
      assertBridgeSnapshot(snapshot, "refresh after no best action");
      continue;
    }

    const manaRockSourceManaAvailable = snapshot.legalActions?.some((candidate) => candidate.type === "make_mana") ?? false;
    if (manaRockLikeScenario && action.type === "cast_spell" && isManaRockAction(action) && manaRockCastSeen && !manaRockSourceManaAvailable) {
      const report = {
        ...baseSummaryReport(snapshot),
        failedStep: "mana-rock-cast-no-progress",
        failureReason: `${manaRockCardName} remained in hand and castable after a prior real XMage cast attempt; payment/resolution did not progress.`
      };
      writeSmokeReport(report);
      throw new Error(
        `[Smoke] refusing repeated ${manaRockCardName} cast with no payment or zone progress.\n`
          + smokeDebug(`repeated ${manaRockCardName} cast snapshot`, snapshot)
      );
    }

    console.error(`[Smoke] Turn ${snapshot.turn} (${snapshot.phase} - ${snapshot.step}): Executing human action: ${action.type} (label: ${action.label ?? "none"})`);
    actionsByType[action.type] = (actionsByType[action.type] ?? 0) + 1;
    markRouteFamily(action.type);
    recordRouteFamilyForAction(action);
    
    // Check if combat is exercised
    if (action.type === "declare_attackers" || action.type === "declare_blockers") {
      combatExercised = true;
    }
    if (action.type === "declare_blockers") {
      blockerAssignmentExercised = true;
    }
    if (dragCastRegressionScenario && action.type === "play_land") {
      dragCastLandSeen = true;
    }
    if (manaRockLikeScenario && action.type === "cast_spell" && isManaRockAction(action)) {
      manaRockCastSeen = true;
    }
    if (manaRockLikeScenario && action.type === "make_mana" && manaRockCastSeen) {
      manaRockPaymentSourceSeen = true;
    }
    recordGauntletAction(snapshot, action);

    if (snapshot.promptEnvelopeV2) {
      const pKey = `${snapshot.promptEnvelopeV2.method ?? "unknown"}:${snapshot.promptEnvelopeV2.responseKind ?? "unknown"}`;
      if (!promptChecks.includes(pKey)) {
        promptChecks.push(pKey);
      }
      recordRouteFamilyForPrompt(snapshot);
      if (commanderGauntletScenario) {
        gauntletPromptFamilies.add(pKey);
      }
    }

    const previous = snapshot;
    assertLegalActionBeforeSubmit(snapshot, action);
    const command = commandFromAction(snapshot.id, action, snapshot);
    assertCommandUsesLegalAction(action, command);
    if (dragCastRegressionScenario && (action.type === "play_land" || action.type === "cast_spell")) {
      assertIosDragCommandUsesCurrentHandLegalAction(snapshot, action, command);
    }
    snapshot = await request(`/games/${encodeURIComponent(snapshot.id)}/commands`, {
      method: "POST",
      body: command
    });
    if (snapshot.staleActionRecovered) {
      assertBridgeSnapshot(snapshot, `stale action recovery: ${action.type}`);
      delete snapshot.staleActionRecovered;
      staleActionRecoveries++;
      console.error(`[Smoke] Refreshed after stale ${action.type}; choosing next live action.`);
      continue;
    }

    const semanticLabel = action.type === "play_land"
      ? "play land"
      : action.type === "make_mana"
        ? "make mana"
        : action.type === "activate_ability"
          ? "activate ability"
          : action.type === "cast_spell"
            ? "cast simple spell"
            : action.type === "declare_attackers" || action.type === "declare_blockers"
              ? "combat"
              : action.type === "pass_priority" || action.type === "pass_until_response" || action.type === "pass_until_next_turn"
                ? "pass priority"
                : "resolve prompt";
            
    snapshot = await waitForSemanticProgress(previous, snapshot, semanticLabel);
    if (manaRockLikeScenario && action.type === "cast_spell" && isManaRockAction(action)) {
      assertManaRockCastProgress(previous, snapshot);
    }
    assertBridgeSnapshot(snapshot, `action: ${action.type}`);
    assertBridgeProgress(previous, snapshot, `action: ${action.type}`, {
      allowEqual: snapshot.pendingStatus === "waiting_for_xmage"
    });
    assertSemanticProgress(previous, snapshot, semanticLabel);
    if (promptModeScenario && action.type === "choose_mode") {
      promptModeChoiceSubmitted = true;
    }
    if (promptOrderScenario && (action.type === "order_triggers" || action.type === "order_items")) {
      promptOrderChoiceSubmitted = true;
    }
    if (promptAmountScenario && action.type === "choose_amount") {
      promptAmountChoiceSubmitted = true;
    }
    if (promptMultiAmountScenario && action.type === "choose_multi_amount") {
      promptMultiAmountChoiceSubmitted = true;
    }
    if (promptPileScenario && action.type === "choose_pile") {
      promptPileChoiceSubmitted = true;
    }
    if (damageAssignmentScenario && isDamageAssignmentPromptSnapshot(previous) && isDamageAssignmentPromptAction(action)) {
      damageAssignmentPromptSeen = true;
      damageAssignmentChoiceSubmitted = true;
      markRouteFamily("damage_assignment");
    }
    recordRouteFamilyForTransition(previous, snapshot);
    recordCommanderState(snapshot);
    recordCoverage(snapshot);
    recordGauntletSnapshot(snapshot);
    completed.push(`[Turn ${previous.turn} ${previous.phase}] ${action.type}: ${action.label ?? "none"}`);
  } else {
    // 4. Waiting for AI priority
    if (snapshot.waitingOnPlayerId === aiPlayerId || snapshot.priorityPlayerId === aiPlayerId) {
      aiWaits++;
      console.error(`[Smoke] Waiting for AI priority... turn ${snapshot.turn}, phase ${snapshot.phase}, step ${snapshot.step}`);
      snapshot = await waitForAiIfNeeded(snapshot, "wait for AI priority");
      recordCoverage(snapshot);
      recordGauntletSnapshot(snapshot);
    } else {
      // General wait and refresh
      await new Promise(resolve => setTimeout(resolve, 1000));
      snapshot = await request(`/games/${encodeURIComponent(snapshot.id)}`);
      assertBridgeSnapshot(snapshot, "general refresh");
      recordCoverage(snapshot);
      recordGauntletSnapshot(snapshot);
    }
  }
}

recordCommanderState(snapshot);
recordCoverage(snapshot);

if (scenario === "blocker-flow" && !blockerAssignmentExercised) {
  throw new Error(
    "[Smoke] blocker-flow scenario did not exercise a real declare_blockers action.\n"
      + smokeDebug("combat scenario final snapshot", snapshot)
  );
}

if (scenario === "commander-replacement-tax" || scenario === "commander-damage") {
  if (commanderTaxChanges.length === 0) {
    throw new Error(
      "[Smoke] commander-state scenario did not observe commander tax from XMage rules text.\n"
        + smokeDebug("commander tax final snapshot", snapshot)
    );
  }
  if (commanderDamageChanges.length === 0) {
    throw new Error(
      "[Smoke] commander-state scenario did not observe commander damage from XMage rules text.\n"
        + smokeDebug("commander damage final snapshot", snapshot)
    );
  }
}

if (scenario === "mana-rock" || scenario === "drag-cast-regression" || scenario === "drag-cast-phone-regression") {
  if (dragCastRegressionScenario && !dragCastLandSeen) {
    throw new Error(
      "[Smoke] drag-cast-regression did not submit a play_land action through the drag-equivalent legal action path.\n"
        + smokeDebug("drag land final snapshot", snapshot)
    );
  }
  if (!manaRockCastSeen) {
    throw new Error(
      `[Smoke] ${scenario} scenario did not cast ${manaRockCardName} from an XMage legal action.\n`
        + smokeDebug("mana-rock cast final snapshot", snapshot)
    );
  }
  if (!manaRockPaymentSourceSeen) {
    throw new Error(
      `[Smoke] ${scenario} scenario did not expose source make_mana actions during payment.\n`
        + smokeDebug("mana-rock payment final snapshot", snapshot)
    );
  }
  if (dragCastPhoneRegressionScenario && !stackSeen) {
    throw new Error(
      "[Smoke] drag-cast-phone-regression did not observe a real stack object after the drag-equivalent cast.\n"
        + smokeDebug("drag-cast-phone stack final snapshot", snapshot)
    );
  }
  if (dragCastPhoneRegressionScenario) {
    const phoneSteps = completedScenarioSteps();
    if (!phoneSteps.includes("drag-cast-phone-regression")) {
      throw new Error(
        "[Smoke] drag-cast-phone-regression did not complete cast + stack + source mana proof.\n"
          + smokeDebug("drag-cast-phone final snapshot", snapshot)
      );
    }
  }
  if (!manaRockResolvedSeen && !dragCastPhoneRegressionScenario) {
    throw new Error(
      `[Smoke] mana-rock scenario did not observe ${manaRockCardName} leaving hand and resolving to the battlefield.\n`
        + smokeDebug("mana-rock resolution final snapshot", snapshot)
    );
  }
}

if (scenario === "core-flow") {
  const alphaFailures = [
    turnsObserved.size >= 12 ? "" : `observed ${turnsObserved.size}/12 turns`,
    actionsByType.keep_hand || actionsByType.mulligan ? "" : "opening-hand decision missing",
    actionsByType.play_land ? "" : "play_land missing",
    actionsByType.make_mana ? "" : "make_mana missing",
    actionsByType.cast_spell ? "" : "cast_spell missing",
    actionsByType.pass_priority || actionsByType.pass_until_response || actionsByType.pass_until_next_turn || actionsByType.advance_phase ? "" : "pass/advance action missing",
    aiWaits > 0 ? "" : "AI wait/progress missing",
    combatStepSeen ? "" : "combat step not observed"
  ].filter(Boolean);
  if (alphaFailures.length > 0) {
    writeSmokeReport({
      ...baseSummaryReport(snapshot),
      failedStep: "core-flow",
      failureReason: alphaFailures.join(", ")
    });
    throw new Error(
      `[Smoke] alpha-game scenario did not satisfy real-game coverage: ${alphaFailures.join(", ")}.\n`
        + smokeDebug("alpha-game final snapshot", snapshot)
    );
  }
}

if (scenario === "commander-gauntlet") {
  const missing = commanderGauntletMissingSteps();
  if (missing.length > 0) {
    writeSmokeReport({
      ...baseSummaryReport(snapshot),
      failedStep: "commander-gauntlet",
      failureReason: `Missing required gauntlet steps: ${missing.join(", ")}`
    });
    throw new Error(
      `[Smoke] commander-gauntlet did not complete required real-XMage steps: ${missing.join(", ")}.\n`
        + smokeDebug("commander-gauntlet final snapshot", snapshot)
    );
  }
}

if (activatedAbilityScenario || triggeredAbilityScenario || promptModeScenario || promptOrderScenario || promptAmountScenario || promptMultiAmountScenario || promptPileScenario || scenario === "prompt-variety" || scenario === "damage-assignment" || scenario === "choose-mana" || scenario === "mana-color-choice") {
  const missing = missingRouteFamilies();
  if (missing.length > 0) {
    writeSmokeReport({
      ...baseSummaryReport(snapshot),
      failedStep: scenario,
      failureReason: `Missing required route families: ${missing.join(", ")}`
    });
    throw new Error(
      `[Smoke] ${scenario} did not complete required real-XMage route families: ${missing.join(", ")}.\n`
      + smokeDebug(`${scenario} final snapshot`, snapshot)
    );
  }
}

if (promptModeScenario && (!promptModeChoiceSubmitted || !promptModeChoiceResolved)) {
  writeSmokeReport({
    ...baseSummaryReport(snapshot),
    failedStep: "prompt-mode",
    failureReason: `choose_mode ${promptModeChoiceSubmitted ? "was submitted" : "was not submitted"}; resolved proof ${promptModeChoiceResolved ? "was observed" : "was not observed"}.`
  });
  throw new Error(
    "[Smoke] prompt-mode did not submit and resolve a real XMage choose_mode response.\n"
      + smokeDebug("prompt-mode final snapshot", snapshot)
  );
}

if (promptOrderScenario && !promptOrderChoiceSubmitted) {
  writeSmokeReport({
    ...baseSummaryReport(snapshot),
    failedStep: "prompt-order",
    failureReason: "order_triggers/order_items was observed only as a prompt family or not observed; no real order response was submitted."
  });
  throw new Error(
    "[Smoke] prompt-order did not submit a real XMage order_triggers/order_items response.\n"
      + smokeDebug("prompt-order final snapshot", snapshot)
  );
}

if (promptAmountScenario && !promptAmountChoiceSubmitted) {
  writeSmokeReport({
    ...baseSummaryReport(snapshot),
    failedStep: "prompt-amount",
    failureReason: "choose_amount was observed only as a prompt family or not observed; no real amount response was submitted."
  });
  throw new Error(
    "[Smoke] prompt-amount did not submit a real XMage choose_amount response.\n"
      + smokeDebug("prompt-amount final snapshot", snapshot)
  );
}

if (promptMultiAmountScenario && !promptMultiAmountChoiceSubmitted) {
  writeSmokeReport({
    ...baseSummaryReport(snapshot),
    failedStep: "prompt-multi-amount",
    failureReason: "choose_multi_amount was observed only as a prompt family or not observed; no real multi-amount response was submitted."
  });
  throw new Error(
    "[Smoke] prompt-multi-amount did not submit a real XMage choose_multi_amount response.\n"
      + smokeDebug("prompt-multi-amount final snapshot", snapshot)
  );
}

if (promptMultiAmountScenario && !promptMultiAmountChoiceResolved) {
  writeSmokeReport({
    ...baseSummaryReport(snapshot),
    failedStep: "prompt-multi-amount",
    failureReason: "choose_multi_amount was submitted but XMage kept or reissued the multi-amount prompt; no authoritative resolved snapshot was observed."
  });
  throw new Error(
    "[Smoke] prompt-multi-amount submitted but did not resolve through real XMage.\n"
      + smokeDebug("prompt-multi-amount final snapshot", snapshot)
  );
}

if (promptPileScenario && !promptPileChoiceSubmitted) {
  writeSmokeReport({
    ...baseSummaryReport(snapshot),
    failedStep: "prompt-pile",
    failureReason: "choose_pile was observed only as a prompt family or not observed; no real pile response was submitted."
  });
  throw new Error(
    "[Smoke] prompt-pile did not submit a real XMage choose_pile response.\n"
      + smokeDebug("prompt-pile final snapshot", snapshot)
  );
}

if (promptPileScenario && !promptPileChoiceResolved) {
  writeSmokeReport({
    ...baseSummaryReport(snapshot),
    failedStep: "prompt-pile",
    failureReason: "choose_pile was submitted but XMage kept or reissued the pile prompt; no authoritative resolved snapshot was observed."
  });
  throw new Error(
    "[Smoke] prompt-pile submitted but did not resolve through real XMage.\n"
      + smokeDebug("prompt-pile final snapshot", snapshot)
  );
}

if (stepCount >= maxStepsCount) {
  throw new Error(
    `[Smoke] hit maximum loop safeguards (${maxStepsCount} steps).\n`
      + smokeDebug("max step snapshot", snapshot)
  );
}

console.error(`[Smoke] Play loop finished at turn ${snapshot.turn}. Saving report...`);

// Produce final JSON summary report
const summaryReport = baseSummaryReport(snapshot);

writeSmokeReport(summaryReport);

// Output summary JSON report to stdout
console.log(JSON.stringify(summaryReport, null, 2));
await cleanupSmokeGame(snapshot);

function writeSmokeReport(report: unknown) {
  const reportScenario = typeof report === "object" && report !== null && "scenario" in report
    ? String((report as { scenario?: unknown }).scenario ?? scenario)
    : scenario;
  writeSmokeReportForScenario(report, reportScenario);
}

function writeSmokeReportForScenario(report: unknown, reportScenario: string) {
  const scenarioReportPath = path.join(reportDirectory, `smoke-report-${reportScenario}.json`);
  fs.mkdirSync(reportDirectory, { recursive: true });
  fs.writeFileSync(latestReportPath, JSON.stringify(report, null, 2), "utf8");
  fs.writeFileSync(scenarioReportPath, JSON.stringify(report, null, 2), "utf8");
  console.error(`[Smoke] Report saved to ${latestReportPath}`);
  console.error(`[Smoke] Scenario report saved to ${scenarioReportPath}`);
}

async function cleanupSmokeGame(snapshot: SmokeSnapshot) {
  const concede = snapshot.legalActions?.find((action) => action.type === "concede");
  if (!snapshot.id || !concede || isGameOverSnapshot(snapshot)) {
    return;
  }
  try {
    await request(`/games/${encodeURIComponent(snapshot.id)}/commands`, {
      method: "POST",
      body: commandFromAction(snapshot.id, concede, snapshot)
    });
    console.error(`[Smoke] Cleanup conceded game ${snapshot.id}`);
  } catch (error) {
    console.error(`[Smoke] Cleanup concede skipped for ${snapshot.id}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

async function runCommanderFullAiGate() {
  const requiredScenarios = [
    "commander-gauntlet",
    "mana-rock",
    "commander-damage",
    "blocker-flow",
    "activated-ability-stack",
    "triggered-ability-stack",
    "prompt-mode",
    "prompt-order",
    "prompt-amount",
    "prompt-multi-amount",
    "prompt-pile",
    "damage-assignment"
  ];
  const scenarioResults: Array<Record<string, unknown>> = [];

  for (const childScenario of requiredScenarios) {
    console.error(`[Smoke] commander-full-ai running ${childScenario}`);
    const reportPath = path.join(reportDirectory, `smoke-report-${childScenario}.json`);
    const startedAtMs = Date.now();
    fs.rmSync(reportPath, { force: true });
    const result = spawnSync("pnpm", ["smoke:xmage"], {
      cwd: workspaceRoot,
      env: {
        ...process.env,
        ENABLE_XMAGE_FIXTURES: "true",
        NODE_ENV: "test",
        XMAGE_SMOKE_SCENARIO: childScenario,
        XMAGE_USE_FIXTURE: "true"
      },
      encoding: "utf8"
    });
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);

    const childReport = readReportIfPresent(reportPath, startedAtMs);
    scenarioResults.push({
      scenario: childScenario,
      passed: result.status === 0,
      exitCode: result.status,
      reportPath,
      ...(childReport ?? {
        failedStep: "report-missing",
        failureReason: `No scenario report was written for ${childScenario}.`
      })
    });
  }

  const routeFamiliesCovered = unionReportStrings(scenarioResults, "routeFamiliesSeen").sort();
  const routeFamiliesRequired = unionReportStrings(scenarioResults, "routeFamiliesRequired").sort();
  const routeFamiliesMissing = routeFamiliesRequired
    .filter((family) => !routeFamilyCoveredByReports(family, routeFamiliesCovered))
    .sort();
  const iOSRequiredRoutesMissing = routeFamiliesMissing.filter((family) => ![
    "fixture_call",
    "direct_state_seeded",
    "seeded_state_verified"
  ].includes(family));
  const failedScenarios = scenarioResults
    .filter((result) => result.passed !== true)
    .map((result) => String(result.scenario));
  const sourceFailures = scenarioResults
    .filter((result) => result.source !== "xmage-java-bridge")
    .map((result) => String(result.scenario));
  const directSeedFailures = scenarioResults
    .filter((result) => result.directStateSeeded !== true)
    .map((result) => String(result.scenario));
  const seededVerificationFailures = scenarioResults
    .filter((result) => result.seededStateVerified !== true)
    .map((result) => String(result.scenario));
  const productionGateFailures = scenarioResults
    .filter((result) => !resultProductionDisabled(result))
    .map((result) => String(result.scenario));
  const scenarioStepsBlocked = scenarioResults.flatMap((result) => {
    const blocks = Array.isArray(result.stepsBlocked) ? result.stepsBlocked.map(String) : [];
    return blocks.map((block) => `${String(result.scenario)}:${block}`);
  });
  const stepsBlocked = Array.from(new Set([
    ...failedScenarios.map((name) => `scenario:${name}`),
    ...sourceFailures.map((name) => `source:${name}`),
    ...directSeedFailures.map((name) => `direct_state_seeded:${name}`),
    ...seededVerificationFailures.map((name) => `seeded_state_verified:${name}`),
    ...productionGateFailures.map((name) => `production_disabled:${name}`),
    ...scenarioStepsBlocked,
    ...routeFamiliesMissing.map((family) => `route_family:${family}`)
  ])).sort();
  const allRequiredScenariosPassed = stepsBlocked.length === 0
    && iOSRequiredRoutesMissing.length === 0;

  return {
    endpoint,
    scenario: "commander-full-ai",
    fixtureRequested: true,
    fixtureCallRequired: true,
    requiredScenarios,
    allRequiredScenariosPassed,
    source: scenarioResults.every((result) => result.source === "xmage-java-bridge") ? "xmage-java-bridge" : "mixed-or-missing",
    directStateSeeded: scenarioResults.every((result) => result.directStateSeeded === true),
    seededStateVerified: scenarioResults.every((result) => result.seededStateVerified === true),
    productionDisabled: scenarioResults.every(resultProductionDisabled),
    routeFamiliesRequired,
    routeFamiliesCovered,
    routeFamiliesMissing,
    stepsBlocked,
    iOSRequiredRoutesMissing,
    scenarioResults: scenarioResults.map((result) => ({
      scenario: result.scenario,
      passed: result.passed,
      source: result.source,
      directStateSeeded: result.directStateSeeded,
      seededStateVerified: result.seededStateVerified,
      bridgeRevision: result.bridgeRevision,
      xmageCycle: result.xmageCycle,
      routeFamiliesRequired: result.routeFamiliesRequired,
      routeFamiliesMissing: result.routeFamiliesMissing,
      stepsBlocked: result.stepsBlocked,
      failedStep: result.failedStep,
      failureReason: result.failureReason,
      reportPath: result.reportPath
    })),
    readinessVerdict: allRequiredScenariosPassed
      ? "full-commander-vs-ai-ready"
      : "not-ready-full-commander-vs-ai",
    failureReason: allRequiredScenariosPassed
      ? null
      : "Full Commander vs AI requires every listed deterministic scenario to pass and every required route family to be covered by real XMage."
  };
}

async function runPromptVarietyGate() {
  const requiredScenarios = [
    "activated-ability-stack",
    "triggered-ability-stack",
    "prompt-mode",
    "prompt-order",
    "prompt-amount",
    "prompt-multi-amount",
    "prompt-pile"
  ];
  const scenarioResults = runChildSmokeScenarios("prompt-variety", requiredScenarios);
  const routeFamiliesRequired = promptVarietyRouteFamiliesRequired();
  const routeFamiliesCovered = unionReportStrings(scenarioResults, "routeFamiliesSeen").sort();
  const routeFamiliesMissing = routeFamiliesRequired
    .filter((family) => !routeFamilyCoveredByReports(family, routeFamiliesCovered))
    .sort();
  const failedScenarios = scenarioResults
    .filter((result) => result.passed !== true)
    .map((result) => String(result.scenario));
  const sourceFailures = scenarioResults
    .filter((result) => result.source !== "xmage-java-bridge")
    .map((result) => String(result.scenario));
  const directSeedFailures = scenarioResults
    .filter((result) => result.directStateSeeded !== true)
    .map((result) => String(result.scenario));
  const seededVerificationFailures = scenarioResults
    .filter((result) => result.seededStateVerified !== true)
    .map((result) => String(result.scenario));
  const productionGateFailures = scenarioResults
    .filter((result) => {
      const harness = result.fixtureHarness as { productionDisabled?: unknown } | undefined;
      return harness?.productionDisabled !== true;
    })
    .map((result) => String(result.scenario));
  const scenarioStepsBlocked = scenarioResults.flatMap((result) => {
    const blocks = Array.isArray(result.stepsBlocked) ? result.stepsBlocked.map(String) : [];
    return blocks.map((block) => `${String(result.scenario)}:${block}`);
  });
  const stepsBlocked = Array.from(new Set([
    ...failedScenarios.map((name) => `scenario:${name}`),
    ...sourceFailures.map((name) => `source:${name}`),
    ...directSeedFailures.map((name) => `direct_state_seeded:${name}`),
    ...seededVerificationFailures.map((name) => `seeded_state_verified:${name}`),
    ...productionGateFailures.map((name) => `production_disabled:${name}`),
    ...scenarioStepsBlocked,
    ...routeFamiliesMissing.map((family) => `route_family:${family}`)
  ])).sort();
  const allRequiredScenariosPassed = stepsBlocked.length === 0;

  return {
    endpoint,
    scenario: "prompt-variety",
    fixtureRequested: true,
    fixtureCallRequired: true,
    requiredScenarios,
    allRequiredScenariosPassed,
    source: scenarioResults.every((result) => result.source === "xmage-java-bridge") ? "xmage-java-bridge" : "mixed-or-missing",
    directStateSeeded: scenarioResults.every((result) => result.directStateSeeded === true),
    seededStateVerified: scenarioResults.every((result) => result.seededStateVerified === true),
    productionDisabled: scenarioResults.every((result) => {
      const harness = result.fixtureHarness as { productionDisabled?: unknown } | undefined;
      return harness?.productionDisabled === true;
    }),
    routeFamiliesRequired,
    routeFamiliesSeen: routeFamiliesCovered,
    routeFamiliesCovered,
    routeFamiliesMissing,
    stepsCompleted: allRequiredScenariosPassed ? ["prompt-variety"] : [],
    stepsBlocked,
    scenarioResults: scenarioResults.map((result) => ({
      scenario: result.scenario,
      passed: result.passed,
      source: result.source,
      directStateSeeded: result.directStateSeeded,
      seededStateVerified: result.seededStateVerified,
      bridgeRevision: result.bridgeRevision,
      xmageCycle: result.xmageCycle,
      routeFamiliesSeen: result.routeFamiliesSeen,
      routeFamiliesRequired: result.routeFamiliesRequired,
      routeFamiliesMissing: result.routeFamiliesMissing,
      stepsBlocked: result.stepsBlocked,
      failedStep: result.failedStep,
      failureReason: result.failureReason,
      reportPath: result.reportPath
    })),
    failureReason: allRequiredScenariosPassed
      ? null
      : "Prompt variety requires every targeted real-XMage prompt scenario to pass and cover every required prompt route family."
  };
}

function runChildSmokeScenarios(parentScenario: string, requiredScenarios: string[]) {
  const scenarioResults: Array<Record<string, unknown>> = [];

  for (const childScenario of requiredScenarios) {
    console.error(`[Smoke] ${parentScenario} running ${childScenario}`);
    const reportPath = path.join(reportDirectory, `smoke-report-${childScenario}.json`);
    const startedAtMs = Date.now();
    fs.rmSync(reportPath, { force: true });
    const result = spawnSync("pnpm", ["smoke:xmage"], {
      cwd: workspaceRoot,
      env: {
        ...process.env,
        ENABLE_XMAGE_FIXTURES: "true",
        NODE_ENV: "test",
        XMAGE_SMOKE_SCENARIO: childScenario,
        XMAGE_USE_FIXTURE: "true"
      },
      encoding: "utf8"
    });
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);

    const childReport = readReportIfPresent(reportPath, startedAtMs);
    scenarioResults.push({
      scenario: childScenario,
      passed: result.status === 0,
      exitCode: result.status,
      reportPath,
      ...(childReport ?? {
        failedStep: "report-missing",
        failureReason: `No scenario report was written for ${childScenario}.`
      })
    });
  }

  return scenarioResults;
}

function readReportIfPresent(reportPath: string, minMtimeMs = 0) {
  try {
    if (minMtimeMs > 0 && fs.statSync(reportPath).mtimeMs + 1000 < minMtimeMs) {
      return null;
    }
    return JSON.parse(fs.readFileSync(reportPath, "utf8")) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function routeFamilyCoveredByReports(family: string, coveredFamilies: string[]) {
  const covered = new Set(coveredFamilies);
  if (family === "search_select/choose_card") {
    return covered.has("search_select") || covered.has("choose_card") || covered.has(family);
  }
  if (family === "order_triggers/order_items") {
    return covered.has("order_triggers") || covered.has("order_items") || covered.has(family);
  }
  return covered.has(family);
}

function resultProductionDisabled(result: Record<string, unknown>) {
  if (result.productionDisabled === true) return true;
  const harness = result.fixtureHarness as { productionDisabled?: unknown } | undefined;
  return harness?.productionDisabled === true;
}

function unionReportStrings(reports: Array<Record<string, unknown>>, key: string) {
  return Array.from(new Set(reports.flatMap((report) => {
    const value = report[key];
    return Array.isArray(value) ? value.map(String) : [];
  })));
}

function baseSummaryReport(snapshot: SmokeSnapshot) {
  const stepsCompleted = completedScenarioSteps();
  const stepsBlocked = blockedScenarioSteps(stepsCompleted);
  const promptFamiliesSeen = Array.from(new Set([...promptChecks, ...gauntletPromptFamilies])).sort();
  return {
    endpoint,
    scenario,
    scenarioSet: scenarioModule.scenarioSet,
    objective: commanderGauntletScenario
      ? {
          fixtureCallRequired,
          directStateSeededRequired: true,
          seededStateVerifiedRequired: true,
          realCommanderGameRequired: true,
          postSetupCommandPath: "bridge-command-endpoints-only"
        }
      : undefined,
    fixtureRequested: useFixtureHarness,
    fixtureCallRequired,
    fixtureCallUsed: createPath === "/dev/xmage-fixtures/commander",
    realCommanderGame: isRealCommanderSnapshot(snapshot),
    directStateSeeded,
    seededStateVerified,
    fixtureHarness: activeFixtureHarness,
    health,
    gameId: snapshot.id,
    source: snapshot.source ?? "gateway",
    bridgeRevision: snapshot.bridgeRevision ?? null,
    xmageCycle: snapshot.xmageCycle ?? null,
    phase: snapshot.phase,
    step: snapshot.step,
    turn: snapshot.turn,
    promptText: snapshot.promptText,
    promptChecks,
    promptSamples,
    promptFamiliesSeen,
    routeFamiliesRequired,
    routeFamiliesSeen: sortedRouteFamiliesSeen(),
    routeFamiliesMissing: missingRouteFamilies(),
    completed,
    stepsCompleted,
    stepsBlocked,
    laterScope: laterScopeSteps(stepsCompleted),
    turnsObserved: Array.from(turnsObserved).sort((a, b) => a - b),
    actionsByType,
    staleActionRecoveries,
    aiWaits,
    stackSeen,
    combatStepSeen,
    combatExercised,
    blockerAssignmentExercised,
    manaRock: {
      cardName: manaRockCardName,
      castSeen: manaRockCastSeen,
      paymentSourceSeen: manaRockPaymentSourceSeen,
      resolvedSeen: manaRockResolvedSeen
    },
    arcaneSignet: manaRockCardName === "Arcane Signet" ? {
      castSeen: manaRockCastSeen,
      paymentSourceSeen: manaRockPaymentSourceSeen,
      resolvedSeen: manaRockResolvedSeen
    } : undefined,
    promptMode: promptModeScenario ? {
      choiceSubmitted: promptModeChoiceSubmitted,
      choiceResolved: promptModeChoiceResolved
    } : undefined,
    promptOrder: promptOrderScenario ? {
      choiceSubmitted: promptOrderChoiceSubmitted
    } : undefined,
    promptAmount: promptAmountScenario ? {
      choiceSubmitted: promptAmountChoiceSubmitted
    } : undefined,
    promptMultiAmount: promptMultiAmountScenario ? {
      choiceSubmitted: promptMultiAmountChoiceSubmitted,
      choiceResolved: promptMultiAmountChoiceResolved
    } : undefined,
    promptPile: promptPileScenario ? {
      choiceSubmitted: promptPileChoiceSubmitted,
      choiceResolved: promptPileChoiceResolved
    } : undefined,
    damageAssignment: damageAssignmentScenario ? {
      promptSeen: damageAssignmentPromptSeen,
      choiceSubmitted: damageAssignmentChoiceSubmitted
    } : undefined,
    commanderTaxChanges,
    commanderDamageChanges,
    players: snapshot.players?.map((player: SmokePlayer) => ({
      playerId: player.playerId,
      life: player.life,
      commanderTax: player.commanderTax ?? 0,
      commanderDamage: player.commanderDamage ?? {},
      library: player.zones?.library?.length ?? 0,
      hand: player.zones?.hand?.length ?? 0,
      battlefield: player.zones?.battlefield?.length ?? 0,
      command: player.zones?.command?.map((card) => card.card?.name) ?? []
    })),
    legalActions: snapshot.legalActions?.map((action: SmokeAction) => action.type).slice(0, 12) ?? []
  };
}

function fixtureUnavailableReport(fixtureHarness: SmokeSnapshot["fixtureHarness"], snapshot?: SmokeSnapshot) {
  const promptFamiliesSeen = safeReportValue(() => Array.from(new Set([...promptChecks, ...gauntletPromptFamilies])).sort(), []);
  const stepsCompleted = safeReportValue(() => completedScenarioSteps(), []);
  const reportScenario = fixtureHarness?.fixtureName ?? scenario;
  const reportModule = scenarioModuleFor(reportScenario);
  const requiredRouteFamilies = routeFamiliesRequiredForScenario(reportScenario);
  const routeFamilies = safeReportValue(() => sortedRouteFamiliesSeen(), []);
  const routeMissing = safeReportValue(
    () => requiredRouteFamilies.filter((family) => !routeFamilySeen(family)),
    requiredRouteFamilies
  );
  return {
    endpoint,
    scenario: reportScenario,
    scenarioSet: reportModule.scenarioSet,
    objective: {
      fixtureCallRequired: true,
      directStateSeededRequired: true,
      seededStateVerifiedRequired: true,
      realCommanderGameRequired: true,
      postSetupCommandPath: "bridge-command-endpoints-only"
    },
    fixtureRequested: true,
    fixtureCallRequired: true,
    fixtureCallUsed: useFixtureHarness,
    realCommanderGame: snapshot ? isRealCommanderSnapshot(snapshot) : false,
    directStateSeeded: safeReportValue(() => directStateSeeded, false),
    seededStateVerified: safeReportValue(() => seededStateVerified, false),
    fixtureHarness,
    health,
    gameId: snapshot?.id ?? null,
    source: snapshot?.source ?? "xmage-java-bridge",
    bridgeRevision: snapshot?.bridgeRevision ?? null,
    xmageCycle: snapshot?.xmageCycle ?? null,
    phase: snapshot?.phase ?? null,
    step: snapshot?.step ?? null,
    turn: snapshot?.turn ?? null,
    promptFamiliesSeen,
    routeFamiliesRequired: requiredRouteFamilies,
    routeFamiliesSeen: routeFamilies,
    routeFamiliesMissing: routeMissing,
    actionsByType: safeReportValue(() => actionsByType, {}),
    commanderTaxChanges: safeReportValue(() => commanderTaxChanges, []),
    commanderDamageChanges: safeReportValue(() => commanderDamageChanges, []),
    stackSeen: safeReportValue(() => stackSeen, false),
    combatStepSeen: safeReportValue(() => combatStepSeen, false),
    combatExercised: safeReportValue(() => combatExercised, false),
    blockerAssignmentExercised: safeReportValue(() => blockerAssignmentExercised, false),
    stepsCompleted,
    stepsBlocked: [
      ...(safeReportValue(() => useFixtureHarness, false) ? [] : ["fixture_call"]),
      ...(safeReportValue(() => directStateSeeded, false) ? [] : ["direct_state_seeded"]),
      ...(safeReportValue(() => seededStateVerified, false) ? [] : ["seeded_state_verified"]),
      ...routeMissing.map((family) => `route_family:${family}`)
    ],
    laterScope: reportModule.scenarioSet
      .filter((step) => step !== "core-flow" && step !== "commander-gauntlet")
      .filter((step) => !reportModule.requiredSteps.includes(step))
      .filter((step) => !stepsCompleted.includes(step)),
    staleActionRecoveries: safeReportValue(() => staleActionRecoveries, 0),
    failedStep: "deterministic-fixture-unavailable",
    failureReason: fixtureHarness?.reason
      ?? `XMage fixture harness did not seed deterministic state; release gate cannot prove ${reportScenario} routes.`
  };
}

function safeReportValue<T>(factory: () => T, fallback: T) {
  try {
    return factory();
  } catch {
    return fallback;
  }
}

function fixtureEnvCheck() {
  if (process.env.ENABLE_XMAGE_FIXTURES !== "true") {
    return "Fixture smoke requires ENABLE_XMAGE_FIXTURES=true so /dev/xmage-fixtures/commander is explicitly enabled.";
  }
  if (!process.env.NODE_ENV) {
    return "Fixture smoke requires NODE_ENV to be set to a non-production value.";
  }
  if (process.env.NODE_ENV === "production") {
    return "Fixture smoke is disabled when NODE_ENV=production.";
  }
  return null;
}

function fixtureSeedSchema() {
  const commander = commanderGauntletScenario ? "Isamaru, Hound of Konda" : human.commander.cardName;
  const basic = commanderGauntletScenario ? "Plains" : "Plains";
  const expectedRoutes = routeFamiliesRequired.length > 0 ? routeFamiliesRequired : scenarioModule.requiredSteps;
  const hand = damageAssignmentScenario
    ? ["Plains"]
    : blockerFlowScenario
    ? [basic]
    : dragCastRegressionScenario
    ? ["Plains", manaRockCardName]
    : dragCastPhoneRegressionScenario
    ? [manaRockCardName]
    : manaRockScenario
    ? [manaRockCardName]
    : commanderGauntletScenario
    ? ["Sol Ring", "Arcane Signet", "Terramorphic Expanse", "Swords to Plowshares", "Spirited Companion", "Plains", "Plains"]
    : activatedAbilityScenario
    ? ["Plains"]
    : promptModeScenario
    ? ["Lavabrink Venturer"]
    : promptOrderScenario
    ? ["Spirited Companion", "Plains"]
    : promptAmountScenario
    ? ["Wheel of Misfortune"]
    : promptMultiAmountScenario
    ? ["Manamorphose"]
    : promptPileScenario
    ? ["Fact or Fiction"]
    : triggeredAbilityScenario
    ? ["Spirited Companion", "Plains"]
    : [basic];
  const libraryTop = damageAssignmentScenario
    ? ["Plains"]
    : promptMultiAmountScenario
    ? ["Mountain"]
    : promptPileScenario
    ? ["Island", "Island", "Island", "Island", "Island"]
    : promptAmountScenario
    ? Array.from({ length: 7 }, () => "Mountain")
    : commanderGauntletScenario
    ? Array.from({ length: 24 }, () => "Plains")
    : [basic];
  const battlefield = damageAssignmentScenario
    ? ["Defensive Formation", "Silvercoat Lion", "Savannah Lions", "Plains"]
    : blockerFlowScenario
    ? ["Silvercoat Lion", basic]
    : dragCastPhoneRegressionScenario
    ? ["Mountain", "Mountain"]
    : manaRockLikeScenario
    ? [basic, basic]
    : activatedAbilityScenario
    ? ["Seal of Cleansing", basic]
    : promptModeScenario
    ? [basic, basic, basic]
    : promptOrderScenario
    ? ["Soul Warden", basic, basic]
    : promptAmountScenario
    ? ["Mountain", "Mountain", "Mountain"]
    : promptMultiAmountScenario
    ? ["Mountain", "Mountain"]
    : promptPileScenario
    ? ["Island", "Island", "Island", "Island"]
    : triggeredAbilityScenario
    ? [basic, basic]
    : [basic];
  const requiresCommandZoneProof = commanderGauntletScenario
    || scenario === "commander-damage"
    || scenario === "commander-replacement-tax";
  const commandZone = requiresCommandZoneProof ? [commander] : [];
  return {
    gameId: `fixture-${scenario}-${seed}`,
    commander,
    hand,
    battlefield,
    commandZone,
    libraryTop,
    graveyard: [],
    exile: [],
    aiBattlefield: damageAssignmentScenario ? ["Metalwork Colossus"] : [blockerFlowScenario ? "Memnite" : activatedAbilityScenario ? "Sol Ring" : commanderGauntletScenario ? "Plains" : "Wastes"],
    phase: blockerFlowScenario || damageAssignmentScenario ? "combat" : "precombat-main",
    step: blockerFlowScenario ? "declare-blockers" : damageAssignmentScenario ? "combat-damage" : "precombat-main",
    activePlayerId: blockerFlowScenario || damageAssignmentScenario ? aiPlayerId : humanPlayerId,
    priorityPlayerId: humanPlayerId,
    expectedRoutes,
    expectedRouteCoverage: expectedRoutes
  };
}

function verifySeededStateFromSnapshot(snapshot: SmokeSnapshot) {
  if (!fixtureSeed || !isRealCommanderSnapshot(snapshot)) return false;
  if (snapshot.phase !== fixtureSeed.phase || snapshot.step !== fixtureSeed.step) return false;
  if (snapshot.activePlayerId !== fixtureSeed.activePlayerId || snapshot.priorityPlayerId !== fixtureSeed.priorityPlayerId) return false;

  const human = humanPlayer(snapshot);
  const ai = snapshot.players?.find((player) => player.playerId === aiPlayerId);
  if (!human || !ai) return false;

  const libraryNames = zoneNames(human, "library");
  const libraryTopVisible = fixtureSeed.libraryTop.every((cardName, index) => libraryNames[index] === cardName);
  const libraryTopHidden = libraryNames.length >= fixtureSeed.libraryTop.length
    && libraryNames.slice(0, fixtureSeed.libraryTop.length).every((cardName) => /hidden/i.test(cardName));

  return containsAll(zoneNames(human, "hand"), fixtureSeed.hand)
    && containsAll(zoneNames(human, "battlefield"), fixtureSeed.battlefield)
    && containsAll(zoneNames(human, "command"), fixtureSeed.commandZone)
    && containsAll(zoneNames(human, "graveyard"), fixtureSeed.graveyard)
    && containsAll(zoneNames(human, "exile"), fixtureSeed.exile)
    && (libraryTopVisible || libraryTopHidden)
    && containsAll(zoneNames(ai, "battlefield"), fixtureSeed.aiBattlefield);
}

function isRealCommanderSnapshot(snapshot: SmokeSnapshot) {
  return snapshot.source === "xmage-java-bridge"
    && typeof snapshot.bridgeRevision === "number"
    && !/simulator/i.test(snapshot.source ?? "")
    && Boolean(snapshot.players?.some((player) => player.playerId === humanPlayerId))
    && Boolean(snapshot.players?.some((player) => player.playerId === aiPlayerId));
}

function zoneNames(player: SmokePlayer, zone: string) {
  return (player.zones?.[zone] ?? []).map((entry) => entry.card?.name).filter((name): name is string => Boolean(name));
}

function containsAll(actual: string[], expected: string[]) {
  return expected.every((cardName) => actual.includes(cardName));
}

function completedScenarioSteps() {
  const steps = new Set<string>();
  if (useFixtureHarness) steps.add("fixture_call");
  if (directStateSeeded) steps.add("direct_state_seeded");
  if (seededStateVerified) steps.add("seeded_state_verified");
  if (actionsByType.keep_hand || actionsByType.mulligan) steps.add("opening-hand-decision");
  if (actionsByType.play_land) steps.add("play-land");
  if (actionsByType.make_mana) steps.add("make-mana");
  if (actionsByType.cast_spell) steps.add("cast-spell");
  if (actionsByType.pass_priority || actionsByType.pass_until_response || actionsByType.pass_until_next_turn || actionsByType.advance_phase) {
    steps.add("pass-priority");
  }
  if (actionsByType.choose_player) steps.add("starting-player-choice");
  if (aiProgressObserved) steps.add("ai-progress");
  if (combatStepSeen) steps.add("combat-step-seen");
  if (stackSeen) steps.add("stack-seen");
  if (combatExercised) steps.add("combat-exercised");
  if (manaRockCastSeen && manaRockPaymentSourceSeen && manaRockResolvedSeen) steps.add("mana-rock");
  if (dragCastPhoneRegressionScenario && manaRockCastSeen && manaRockPaymentSourceSeen && stackSeen) steps.add("drag-cast-phone-regression");
  if (dragCastLandSeen && manaRockCastSeen && manaRockPaymentSourceSeen && manaRockResolvedSeen) steps.add("drag-cast-regression");
  if (gauntlet.searchResolved || actionsByType.search_select) steps.add("search-select");
  if (gauntlet.commanderReplacementAnswered || commanderTaxChanges.length > 0) steps.add("commander-replacement-tax");
  if (commanderDamageChanges.length > 0) steps.add("commander-damage");
  if (actionsByType.declare_blockers) steps.add("blocker-flow");
  if (promptVarietyRouteFamiliesSatisfied()) steps.add("prompt-variety");
  for (const family of sortedRouteFamiliesSeen()) {
    steps.add(`route-family:${family}`);
  }
  for (const [step, done] of Object.entries(gauntlet)) {
    if (done) steps.add(`commander-gauntlet:${step}`);
  }
  return Array.from(steps).sort();
}

function blockedScenarioSteps(stepsCompleted: string[]) {
  if (commanderGauntletScenario) {
    return commanderGauntletMissingSteps();
  }
  const completedSet = new Set(stepsCompleted);
  return scenarioModule.requiredSteps.filter((step) => !completedSet.has(step));
}

function laterScopeSteps(stepsCompleted: string[]) {
  if (!commanderGauntletScenario) return [];
  const completedSet = new Set(stepsCompleted);
  return scenarioModule.scenarioSet
    .filter((step) => step !== "core-flow" && step !== "commander-gauntlet")
    .filter((step) => !scenarioModule.requiredSteps.includes(step))
    .filter((step) => !completedSet.has(step));
}

function routeFamiliesRequiredForScenario(input: string) {
  if (input === "commander-gauntlet") return commanderGauntletRouteFamiliesRequired();
  if (input === "prompt-variety") return promptVarietyRouteFamiliesRequired();
  if (input === "prompt-mode") return ["cast_spell", "choose_mode"];
  if (input === "prompt-order") return ["order_triggers/order_items"];
  if (input === "prompt-amount") return ["cast_spell", "choose_amount"];
  if (input === "prompt-multi-amount" || input === "prompt-variety-multi-amount") return ["cast_spell", "choose_multi_amount"];
  if (input === "prompt-pile" || input === "prompt-variety-pile") return ["cast_spell", "choose_pile"];
  if (input === "damage-assignment") return ["choose_multi_amount", "damage_assignment"];
  if (input === "activated-ability-stack") return ["activate_ability", "stack_object_seen", "pass_priority"];
  if (input === "triggered-ability-stack") return ["trigger_seen", "stack_object_seen", "pass_priority"];
  if (input === "opening-start-player" || input === "starting-player-choice") return ["choose_player"];
  if (input === "choose-mana" || input === "mana-color-choice") return ["choose_mana"];
  if (input === "ai-turn-progress") return ["pass_priority"];
  if (input === "drag-cast-regression") return ["play_land", "cast_spell", "make_mana"];
  if (input === "drag-cast-phone-regression") return ["cast_spell", "make_mana", "stack_object_seen"];
  return [];
}

function promptVarietyRouteFamiliesRequired() {
  return [
    "stack_object_seen",
    "activate_ability",
    "choose_ability",
    "choose_mode",
    "order_triggers/order_items",
    "choose_amount",
    "choose_multi_amount",
    "choose_pile"
  ];
}

function commanderGauntletRouteFamiliesRequired() {
  return Array.from(new Set([
    "play_land",
    "cast_spell",
    "make_mana",
    "activate_ability",
    "search_select/choose_card",
    "choose_target",
    "answer_yes_no",
    "pay_cost",
    "commander_replacement",
    "pass_priority",
    "stack_object_seen",
    "trigger_seen",
    "zone_update_seen",
    "commander_tax_seen"
  ]));
}

function sortedRouteFamiliesSeen() {
  return Array.from(routeFamiliesSeen).sort();
}

function missingRouteFamilies() {
  return routeFamiliesRequired.filter((family) => !routeFamilySeen(family));
}

function routeFamilySeen(family: string) {
  if (family === "search_select/choose_card") {
    return routeFamiliesSeen.has("search_select") || routeFamiliesSeen.has("choose_card") || routeFamiliesSeen.has(family);
  }
  if (family === "order_triggers/order_items") {
    return routeFamiliesSeen.has("order_triggers") || routeFamiliesSeen.has("order_items") || routeFamiliesSeen.has(family);
  }
  return routeFamiliesSeen.has(family);
}

function markRouteFamily(family: string) {
  if (routeFamiliesRequired.length > 0) {
    routeFamiliesSeen.add(family);
  }
}

function promptVarietyRouteFamiliesSatisfied() {
  return promptVarietyRouteFamiliesRequired().every(routeFamilySeen);
}

function scenarioModuleFor(input: string): ScenarioModule {
  switch (input) {
    case "general":
    case "alpha-game":
    case "core-flow":
      return {
        id: "core-flow",
        usesFixture: false,
        scenarioSet: ["core-flow"],
        requiredSteps: [
          "opening-hand-decision",
          "play-land",
          "make-mana",
          "cast-spell",
          "pass-priority",
          "ai-progress",
          "combat-step-seen"
        ]
      };
    case "opening-start-player":
    case "starting-player-choice":
      return {
        id: input,
        usesFixture: false,
        scenarioSet: ["opening-start-player"],
        requiredSteps: ["starting-player-choice", "route-family:choose_player"]
      };
    case "repeated-mulligan":
      return {
        id: "repeated-mulligan",
        usesFixture: true,
        scenarioSet: ["repeated-mulligan"],
        requiredSteps: ["route-family:mulligan"]
      };
    case "ai-turn-progress":
      return {
        id: "ai-turn-progress",
        usesFixture: false,
        scenarioSet: ["ai-turn-progress"],
        requiredSteps: ["opening-hand-decision", "pass-priority", "ai-progress"]
      };
    case "arcane-signet":
    case "mana-rock":
      return {
        id: "mana-rock",
        usesFixture: true,
        scenarioSet: ["mana-rock"],
        requiredSteps: ["mana-rock"]
      };
    case "drag-cast-regression":
      return {
        id: "drag-cast-regression",
        usesFixture: true,
        scenarioSet: ["drag-cast-regression"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          "route-family:play_land",
          "route-family:cast_spell",
          "route-family:make_mana",
          "drag-cast-regression"
        ]
      };
    case "drag-cast-phone-regression":
      return {
        id: "drag-cast-phone-regression",
        usesFixture: true,
        scenarioSet: ["drag-cast-phone-regression"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          "route-family:cast_spell",
          "route-family:make_mana",
          "route-family:stack_object_seen",
          "drag-cast-phone-regression"
        ]
      };
    case "search-select":
      return {
        id: "search-select",
        usesFixture: true,
        scenarioSet: ["search-select"],
        requiredSteps: ["search-select"]
      };
    case "choose-card":
      return {
        id: "choose-card",
        usesFixture: true,
        scenarioSet: ["choose-card"],
        requiredSteps: ["route-family:choose_card"]
      };
    case "choose-player":
      return {
        id: "choose-player",
        usesFixture: true,
        scenarioSet: ["choose-player"],
        requiredSteps: ["route-family:choose_player"]
      };
    case "play-x-mana":
      return {
        id: "play-x-mana",
        usesFixture: true,
        scenarioSet: ["play-x-mana"],
        requiredSteps: ["route-family:play_x_mana"]
      };
    case "choose-mana":
    case "mana-color-choice":
      return {
        id: input,
        usesFixture: true,
        scenarioSet: ["choose-mana"],
        requiredSteps: ["route-family:choose_mana"]
      };
    case "generic-replacement":
      return {
        id: "generic-replacement",
        usesFixture: true,
        scenarioSet: ["generic-replacement"],
        requiredSteps: ["route-family:generic_replacement"]
      };
    case "zone-movement":
      return {
        id: "zone-movement",
        usesFixture: true,
        scenarioSet: ["zone-movement"],
        requiredSteps: ["zone_update_seen"]
      };
    case "commander-state":
    case "commander-replacement-tax":
      return {
        id: "commander-replacement-tax",
        usesFixture: true,
        scenarioSet: ["commander-replacement-tax"],
        requiredSteps: ["commander-replacement-tax"]
      };
    case "commander-damage":
      return {
        id: "commander-damage",
        usesFixture: true,
        scenarioSet: ["commander-damage"],
        requiredSteps: ["commander-damage"]
      };
    case "combat":
    case "blocker-flow":
      return {
        id: "blocker-flow",
        usesFixture: true,
        scenarioSet: ["blocker-flow"],
        requiredSteps: ["combat-exercised"]
      };
    case "prompt-variety":
      return {
        id: "prompt-variety",
        usesFixture: true,
        scenarioSet: ["prompt-variety"],
        requiredSteps: ["prompt-variety"]
      };
    case "prompt-mode":
      return {
        id: "prompt-mode",
        usesFixture: true,
        scenarioSet: ["prompt-mode"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          "route-family:cast_spell",
          "route-family:choose_mode"
        ]
      };
    case "prompt-order":
    case "prompt-variety-order":
      return {
        id: "prompt-order",
        usesFixture: true,
        scenarioSet: ["prompt-order"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          "route-family:order_triggers/order_items"
        ]
      };
    case "prompt-amount":
    case "prompt-variety-amount":
      return {
        id: "prompt-amount",
        usesFixture: true,
        scenarioSet: ["prompt-amount"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          "route-family:cast_spell",
          "route-family:choose_amount"
        ]
      };
    case "prompt-multi-amount":
    case "prompt-variety-multi-amount":
      return {
        id: "prompt-multi-amount",
        usesFixture: true,
        scenarioSet: ["prompt-multi-amount"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          "route-family:cast_spell",
          "route-family:choose_multi_amount"
        ]
      };
    case "prompt-pile":
    case "prompt-variety-pile":
      return {
        id: "prompt-pile",
        usesFixture: true,
        scenarioSet: ["prompt-pile"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          "route-family:cast_spell",
          "route-family:choose_pile"
        ]
      };
    case "damage-assignment":
      return {
        id: "damage-assignment",
        usesFixture: true,
        scenarioSet: ["damage-assignment"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          "route-family:choose_multi_amount",
          "route-family:damage_assignment"
        ]
      };
    case "activated-ability":
    case "activated-ability-stack":
      return {
        id: "activated-ability-stack",
        usesFixture: true,
        scenarioSet: ["activated-ability-stack"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          ...routeFamiliesRequiredForScenario("activated-ability-stack").map((family) => `route-family:${family}`)
        ]
      };
    case "triggered-ability":
    case "triggered-ability-stack":
      return {
        id: "triggered-ability-stack",
        usesFixture: true,
        scenarioSet: ["triggered-ability-stack"],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          ...routeFamiliesRequiredForScenario("triggered-ability-stack").map((family) => `route-family:${family}`)
        ]
      };
    case "fixture-smoke":
    case "commander-gauntlet":
      return {
        id: "commander-gauntlet",
        usesFixture: true,
        scenarioSet: [
          "core-flow",
          "mana-rock",
          "search-select",
          "commander-replacement-tax",
          "commander-damage",
          "blocker-flow",
          "prompt-variety",
          "commander-gauntlet"
        ],
        requiredSteps: [
          "fixture_call",
          "direct_state_seeded",
          "seeded_state_verified",
          ...commanderGauntletRouteFamiliesRequired().map((family) => `route-family:${family}`)
        ]
      };
    default:
      throw new Error(
        `Unknown XMAGE_SMOKE_SCENARIO "${input}". Expected core-flow, mana-rock, search-select, `
          + "opening-start-player, starting-player-choice, ai-turn-progress, commander-replacement-tax, commander-damage, blocker-flow, prompt-variety, "
          + "prompt-mode, prompt-order, prompt-amount, prompt-multi-amount, prompt-pile, choose-mana, mana-color-choice, activated-ability-stack, triggered-ability-stack, damage-assignment, drag-cast-regression, fixture-smoke, "
          + "commander-gauntlet, or commander-full-ai."
      );
  }
}

async function request(path: string, options: { method?: string; body?: unknown } = {}) {
  const response = await fetch(`${endpoint}${path}`, {
    method: options.method ?? "GET",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: options.body === undefined ? undefined : JSON.stringify(options.body)
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) {
    if (response.status === 409 && body?.error === "action_no_longer_legal" && body.snapshot) {
      console.error(`[Smoke] Recovered from stale action on ${path}: ${body.message ?? body.error}`);
      body.snapshot.staleActionRecovered = true;
      return body.snapshot;
    }
    const fixtureHarnessBody = body?.fixtureHarness ?? body;
    if (path.startsWith("/dev/xmage-fixtures/") && fixtureHarnessBody?.directStateSeeded === false) {
      const fixtureHarness = {
        ...fixtureHarnessBody,
        reason: fixtureHarnessBody.blockedReason
          ?? body.blockedReason
          ?? body.message
          ?? body.error
          ?? "deterministic fixture unavailable"
      };
      const report = fixtureUnavailableReport(fixtureHarness);
      writeSmokeReport(report);
      console.log(JSON.stringify(report, null, 2));
      throw new Error(
        `[Smoke] deterministic fixture unavailable: ${fixtureHarness.reason}`
      );
    }
    throw new Error(`XMage smoke request failed (${response.status}) ${path}: ${text}`);
  }
  return body;
}

function commanderFixtureDeck(commander: string, basic: string) {
  return {
    name: `${commander} Fixture`,
    commander: { cardName: commander, quantity: 1, section: "commander" },
    entries: [{ cardName: basic, quantity: 99, section: "deck" }]
  };
}

function manaRockFixtureDeck() {
  return {
    name: `${manaRockCardName} Payment Fixture`,
    commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
    entries: [
      { cardName: manaRockCardName, quantity: 1, section: "deck" },
      { cardName: "Plains", quantity: 98, section: "deck" }
    ]
  };
}

function phoneDragCastFixtureDeck() {
  return {
    name: "Phone Drag Cast Payment Fixture",
    commander: { cardName: "Krenko, Mob Boss", quantity: 1, section: "commander" },
    entries: [
      { cardName: manaRockCardName, quantity: 1, section: "deck" },
      { cardName: "Mountain", quantity: 98, section: "deck" }
    ]
  };
}

function activatedAbilityFixtureDeck() {
  return {
    name: "Activated Ability Stack Fixture",
    commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
    entries: [
      { cardName: "Seal of Cleansing", quantity: 1, section: "deck" },
      { cardName: "Sol Ring", quantity: 1, section: "deck" },
      { cardName: "Plains", quantity: 97, section: "deck" }
    ]
  };
}

function promptModeFixtureDeck() {
  return {
    name: "Prompt Mode Fixture",
    commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
    entries: [
      { cardName: "Lavabrink Venturer", quantity: 1, section: "deck" },
      { cardName: "Plains", quantity: 98, section: "deck" }
    ]
  };
}

function promptOrderFixtureDeck() {
  return {
    name: "Prompt Order Fixture",
    commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
    entries: [
      { cardName: "Soul Warden", quantity: 1, section: "deck" },
      { cardName: "Spirited Companion", quantity: 1, section: "deck" },
      { cardName: "Plains", quantity: 97, section: "deck" }
    ]
  };
}

function promptAmountFixtureDeck() {
  return {
    name: "Prompt Amount Fixture",
    commander: { cardName: "Kenrith, the Returned King", quantity: 1, section: "commander" },
    entries: [
      { cardName: "Wheel of Misfortune", quantity: 1, section: "deck" },
      { cardName: "Mountain", quantity: 98, section: "deck" }
    ]
  };
}

function promptMultiAmountFixtureDeck() {
  return {
    name: "Prompt Multi Amount Fixture",
    commander: { cardName: "Kenrith, the Returned King", quantity: 1, section: "commander" },
    entries: [
      { cardName: "Manamorphose", quantity: 1, section: "deck" },
      { cardName: "Mountain", quantity: 98, section: "deck" }
    ]
  };
}

function promptPileFixtureDeck() {
  return {
    name: "Prompt Pile Fixture",
    commander: { cardName: "Kenrith, the Returned King", quantity: 1, section: "commander" },
    entries: [
      { cardName: "Fact or Fiction", quantity: 1, section: "deck" },
      { cardName: "Island", quantity: 98, section: "deck" }
    ]
  };
}

function triggeredAbilityFixtureDeck() {
  return {
    name: "MagicMobile Triggered Ability Fixture",
    commander: { cardName: "Isamaru, Hound of Konda" },
    entries: [
      { cardName: "Spirited Companion", quantity: 1, section: "deck" },
      { cardName: "Plains", quantity: 98, section: "deck" }
    ]
  };
}

function repeatedMulliganFixtureDeck() {
  return commanderFixtureDeck("Isamaru, Hound of Konda", "Plains");
}

function chooseCardFixtureDeck() {
  return {
    name: "MagicMobile Choose Card Fixture",
    commander: { cardName: "Isamaru, Hound of Konda" },
    entries: [
      { cardName: "Faithless Looting", quantity: 1, section: "deck" },
      { cardName: "Mountain", quantity: 98, section: "deck" }
    ]
  };
}

function choosePlayerFixtureDeck() {
  return {
    name: "MagicMobile Choose Player Fixture",
    commander: { cardName: "Isamaru, Hound of Konda" },
    entries: [
      { cardName: "Sign in Blood", quantity: 1, section: "deck" },
      { cardName: "Swamp", quantity: 98, section: "deck" }
    ]
  };
}

function playXManaFixtureDeck() {
  return {
    name: "MagicMobile Play X Mana Fixture",
    commander: { cardName: "Isamaru, Hound of Konda" },
    entries: [
      { cardName: "Blaze", quantity: 1, section: "deck" },
      { cardName: "Mountain", quantity: 98, section: "deck" }
    ]
  };
}

function chooseManaFixtureDeck() {
  return {
    name: "MagicMobile Choose Mana Fixture",
    commander: { cardName: "Isamaru, Hound of Konda" },
    entries: [
      { cardName: "Lotus Petal", quantity: 1, section: "deck" },
      { cardName: "Plains", quantity: 98, section: "deck" }
    ]
  };
}

function genericReplacementFixtureDeck() {
  return {
    name: "MagicMobile Generic Replacement Fixture",
    commander: { cardName: "Isamaru, Hound of Konda" },
    entries: [
      { cardName: "Doom Blade", quantity: 1, section: "deck" },
      { cardName: "Leyline of the Void", quantity: 1, section: "deck" },
      { cardName: "Rest in Peace", quantity: 1, section: "deck" },
      { cardName: "Swamp", quantity: 96, section: "deck" }
    ]
  };
}

function zoneMovementFixtureDeck() {
  return {
    name: "MagicMobile Zone Movement Fixture",
    commander: { cardName: "Isamaru, Hound of Konda" },
    entries: [
      { cardName: "Doom Blade", quantity: 1, section: "deck" },
      { cardName: "Swords to Plowshares", quantity: 1, section: "deck" },
      { cardName: "Swamp", quantity: 97, section: "deck" }
    ]
  };
}

function commanderGauntletHumanDeck() {
  return {
    name: "Commander Gauntlet Fixture",
    commander: { cardName: "Isamaru, Hound of Konda", quantity: 1, section: "commander" },
    entries: [
      { cardName: "Sol Ring", quantity: 1, section: "deck" },
      { cardName: "Arcane Signet", quantity: 1, section: "deck" },
      { cardName: "Terramorphic Expanse", quantity: 1, section: "deck" },
      { cardName: "Swords to Plowshares", quantity: 1, section: "deck" },
      { cardName: "Spirited Companion", quantity: 1, section: "deck" },
      { cardName: "Plains", quantity: 94, section: "deck" }
    ]
  };
}

function commanderGauntletAiDeck() {
  return commanderFixtureDeck("Isamaru, Hound of Konda", "Plains");
}

function findAction(snapshot: SmokeSnapshot, type: string | string[], label = "") {
  const types = Array.isArray(type) ? type : [type];
  const matches = snapshot.legalActions?.filter((action) => types.includes(action.type)) ?? [];
  if (label === "choose starting player") {
    return matches.find((action) => /you start/i.test(action.label ?? "")) ?? matches[0];
  }
  if (types.includes("play_mana")) {
    return matches.find((action) => action.manaType === "G" || /\{G\}| G$|Choose G/i.test(action.label ?? "")) ?? matches[0];
  }
  return matches[0];
}

function chooseBestAction(snapshot: SmokeSnapshot): SmokeAction | undefined {
  if (!snapshot.legalActions || snapshot.legalActions.length === 0) {
    return undefined;
  }

  // 1. Active prompt responses from promptEnvelopeV2
  if (snapshot.promptEnvelopeV2) {
    const expected = snapshot.promptEnvelopeV2.responseCommand?.type ?? snapshot.promptEnvelopeV2.responseKind;
    console.error(`[Smoke] Prompt envelope active: ${snapshot.promptEnvelopeV2.method} expecting ${expected}`);

    if (scenario === "repeated-mulligan") {
      const mulligan = snapshot.legalActions.find(a => a.type === "mulligan");
      if (mulligan) return mulligan;
    } else {
      const keepHand = snapshot.legalActions.find(a => a.type === "keep_hand");
      if (keepHand) return keepHand;
    }

    // Order items/triggers
    const orderAction = snapshot.legalActions.find(a => a.type === "order_triggers" || a.type === "order_items");
    if (orderAction) return orderAction;

    // Search select / choose card/pile/player
    const selectAction = snapshot.legalActions.find(a => 
      a.type === "search_select" || 
      a.type === "choose_card" || 
      a.type === "choose_pile" || 
      a.type === "choose_player"
    );
    if (selectAction) return selectAction;

    // Play/choose/make mana prompts
    if (expected === "play_mana" || expected === "mana" || expected === "choose_mana") {
      const sourceManaAction = snapshot.legalActions.find(a => a.type === "make_mana");
      if (sourceManaAction) return sourceManaAction;
      const playManaActions = snapshot.legalActions.filter(a => a.type === "play_mana" || a.type === "choose_mana");
      if (playManaActions.length > 0) {
        const green = playManaActions.find(a => a.manaType === "G" || /\{G\}| G$|Choose G/i.test(a.label ?? ""));
        return green ?? playManaActions[0];
      }
    }

    // Yes/No / Pay Cost / Confirmation / Commander replacement
    if (expected === "answer_yes_no" || expected === "pay_cost" || expected === "confirmation" || expected === "commander_replacement") {
      const yesNo = snapshot.legalActions.find(a => 
        a.type === "answer_yes_no" || 
        a.type === "commander_replacement" || 
        a.type === "pay_cost"
      );
      if (yesNo) return yesNo;
    }

    // Targets picker
    if (expected === "choose_target" || expected === "resolve_choice") {
      const promptTarget = choosePromptTarget(snapshot);
      if (promptTarget) return promptTarget;
      const target = snapshot.legalActions.find(a => 
        a.type === "choose_target" || 
        a.type === "resolve_choice" || 
        a.type === "choose_card" || 
        a.type === "choose_player"
      );
      if (target) {
        if (/you start/i.test(target.label ?? "")) return target;
        return target;
      }
    }

    // Choose amount / multi amount
    const amountActions = snapshot.legalActions.filter(a =>
      a.type === "choose_amount" || 
      a.type === "choose_multi_amount" || 
      a.type === "play_x_mana"
    );
    const amountAction = promptAmountScenario
      ? amountActions.find((a) => String(a.amount ?? a.commandTemplate?.amount ?? a.choiceIds?.[0] ?? "") === "1")
        ?? amountActions.find((a) => String(a.amount ?? a.commandTemplate?.amount ?? a.choiceIds?.[0] ?? "") !== "0")
        ?? amountActions[0]
      : amountActions[0];
    if (amountAction) {
      if ((promptMultiAmountScenario || damageAssignmentScenario) && amountAction.type === "choose_multi_amount") {
        return withExplicitSmokeMultiAmounts(amountAction, snapshot);
      }
      return amountAction;
    }

    // Choose mode/ability
    const modeAction = snapshot.legalActions.find(a => a.type === "choose_mode" || a.type === "choose_ability");
    if (modeAction) return modeAction;

    // If there is any legal action that matches type or responseKind directly
    const directMatch = snapshot.legalActions.find(a => a.type === expected || a.responseKind === expected);
    if (directMatch) return directMatch;

    return undefined;
  }

  // 2. Keep opening hand or mulligan
  if (scenario === "repeated-mulligan") {
    const mulligan = snapshot.legalActions.find(a => a.type === "mulligan");
    if (mulligan) return mulligan;
  } else {
    const keepHand = snapshot.legalActions.find(a => a.type === "keep_hand");
    if (keepHand) return keepHand;
  }

  if (fixtureScenario) {
    const fixtureAction = chooseFixtureAction(snapshot);
    if (fixtureAction) return fixtureAction;
  }

  // 3. Play land
  const playLand = snapshot.legalActions.find(a => a.type === "play_land");
  if (playLand) return playLand;

  // 4. Make mana (tap untapped land/creature for mana)
  const makeMana = snapshot.legalActions.find(a => a.type === "make_mana");
  if (makeMana) return makeMana;

  // 5. Cast spells (prefer non-commander spells from hand first, then commander if we have mana)
  const castSpell = snapshot.legalActions.find(a => a.type === "cast_spell");
  if (castSpell) return castSpell;

  // 6. Pass priority / next phase. Prefer this before optional activated abilities
  // so the smoke runner does not loop on equipment or utility permanents.
  const pass = snapshot.legalActions.find(a => a.type === "pass_priority" || a.type === "pass_until_response" || a.type === "advance_phase");
  if (pass) return pass;

  // 7. Combat is intentionally exercised by fixture scenarios. The broad
  // smoke loop should prove the 1v1 Commander turn/mana path without being
  // blocked by currently targeted combat/AI coverage gaps.
  if (fixtureScenario) {
    const attackers = snapshot.legalActions.find(a => a.type === "declare_attackers");
    if (attackers) return attackers;

    const blockers = snapshot.legalActions.find(a => a.type === "declare_blockers");
    if (blockers) return blockers;
  }

  // 8. Activate abilities on battlefield permanents only when no pass action exists.
  const activateAbility = snapshot.legalActions.find(a => a.type === "activate_ability");
  if (activateAbility) return activateAbility;

  // 10. Fallback
  const fallback = snapshot.legalActions.find(a => a.type !== "concede");
  if (fallback) return fallback;

  return undefined;
}

function chooseFixtureAction(snapshot: SmokeSnapshot): SmokeAction | undefined {
  if (damageAssignmentScenario) {
    const damageAction = chooseDamageAssignmentAction(snapshot);
    if (damageAction) return damageAction;
  }

  if (blockerFlowScenario) {
    const blocker = snapshot.legalActions?.find((action) => action.type === "declare_blockers");
    if (blocker) return blocker;
  }

  if (commanderGauntletScenario) {
    const gauntletAction = chooseCommanderGauntletAction(snapshot);
    if (gauntletAction) return gauntletAction;
  }

  if (dragCastRegressionScenario || dragCastPhoneRegressionScenario) {
    const dragAction = chooseDragCastRegressionAction(snapshot);
    if (dragAction) return dragAction;
  }

  if (manaRockScenario) {
    const manaRockAction = chooseManaRockAction(snapshot);
    if (manaRockAction) return manaRockAction;
  }

  const actions = snapshot.legalActions ?? [];
  if (activatedAbilityScenario) {
    const sealActivation = actions.find((action) =>
      action.type === "activate_ability"
        && /seal of cleansing/i.test(action.cardName ?? action.label ?? "")
    );
    if (sealActivation) return sealActivation;

    const nonManaAbility = actions.find((action) =>
      action.type === "activate_ability" && !looksLikeManaAction(action)
    );
    if (nonManaAbility) return nonManaAbility;
  }

  if (triggeredAbilityScenario) {
    const castCompanion = actions.find((action) =>
      action.type === "cast_spell" && /spirited companion/i.test(action.cardName ?? action.label ?? "")
    );
    if (castCompanion) return castCompanion;

    const makeWhite = actions.find((action) =>
      action.type === "make_mana"
      && ((action.producedMana ?? action.commandTemplate?.producedMana ?? []).includes("W")
        || /plains|white|\{w\}/i.test(action.cardName ?? action.label ?? ""))
    );
    if (makeWhite) return makeWhite;
  }

  if (promptAmountScenario) {
    const castWheel = actions.find((action) =>
      action.type === "cast_spell" && /wheel of misfortune/i.test(action.cardName ?? action.label ?? "")
    );
    if (castWheel) return castWheel;

    const makeRed = actions.find((action) =>
      action.type === "make_mana"
      && ((action.producedMana ?? action.commandTemplate?.producedMana ?? []).includes("R")
        || /mountain|red|\{r\}/i.test(action.cardName ?? action.label ?? ""))
    );
    if (makeRed) return makeRed;
  }

  if (promptMultiAmountScenario) {
    const chooseMultiAmount = actions.find((action) => action.type === "choose_multi_amount");
    if (chooseMultiAmount) return withExplicitSmokeMultiAmounts(chooseMultiAmount, snapshot);

    const castManamorphose = actions.find((action) =>
      action.type === "cast_spell" && /manamorphose/i.test(action.cardName ?? action.label ?? "")
    );
    if (castManamorphose) return castManamorphose;

    const makeRed = actions.find((action) =>
      action.type === "make_mana"
      && ((action.producedMana ?? action.commandTemplate?.producedMana ?? []).includes("R")
        || /mountain|red|\{r\}/i.test(action.cardName ?? action.label ?? ""))
    );
    if (makeRed) return makeRed;
  }

  if (promptPileScenario) {
    const choosePile = actions.find((action) => action.type === "choose_pile");
    if (choosePile) return choosePile;

    const castFact = actions.find((action) =>
      action.type === "cast_spell" && /fact or fiction/i.test(action.cardName ?? action.label ?? "")
    );
    if (castFact) return castFact;

    const makeBlue = actions.find((action) =>
      action.type === "make_mana"
      && ((action.producedMana ?? action.commandTemplate?.producedMana ?? []).includes("U")
        || /island|blue|\{u\}/i.test(action.cardName ?? action.label ?? ""))
    );
    if (makeBlue) return makeBlue;
  }

  const battlefieldNames = humanZone(snapshot, "battlefield").map((entry) => entry.card?.name ?? "");
  const hasIsamaru = battlefieldNames.includes("Isamaru, Hound of Konda");
  const hasLand = humanZone(snapshot, "battlefield").some((entry) => /plains/i.test(entry.card?.name ?? ""));

  if (!hasLand) {
    const land = actions.find((action) => action.type === "play_land" && /plains/i.test(action.cardName ?? action.label ?? ""));
    if (land) return land;
  }

  if (!hasIsamaru) {
    const castCommander = actions.find((action) =>
      action.type === "cast_spell"
      && ((action.sourceZone ?? action.commandTemplate?.sourceZone) === "command" || /isamaru/i.test(action.cardName ?? action.label ?? ""))
    );
    if (castCommander) return castCommander;

    const makeWhite = actions.find((action) =>
      action.type === "make_mana"
      && ((action.producedMana ?? action.commandTemplate?.producedMana ?? []).includes("W")
        || /plains|white|\{w\}/i.test(action.cardName ?? action.label ?? ""))
    );
    if (makeWhite) return makeWhite;

    const makeMana = actions.find((action) => action.type === "make_mana");
    if (makeMana) return makeMana;
  }

  const attacker = actions.find((action) => action.type === "declare_attackers" && /isamaru/i.test(action.label ?? action.cardName ?? ""))
    ?? actions.find((action) => action.type === "declare_attackers");
  if (attacker) return attacker;

  const blocker = actions.find((action) => action.type === "declare_blockers");
  if (blocker) return blocker;

  return undefined;
}

function withExplicitSmokeMultiAmounts(action: SmokeAction, snapshot: SmokeSnapshot): SmokeAction {
  return {
    ...action,
    amounts: explicitSmokeMultiAmounts(snapshot)
  };
}

function chooseDamageAssignmentAction(snapshot: SmokeSnapshot): SmokeAction | undefined {
  const actions = snapshot.legalActions ?? [];
  if (isDamageAssignmentPromptSnapshot(snapshot)) {
    damageAssignmentPromptSeen = true;
    const multiAmount = actions.find((action) => action.type === "choose_multi_amount");
    if (multiAmount) return withExplicitSmokeMultiAmounts(multiAmount, snapshot);

    const yes = actions.find((action) =>
      action.type === "answer_yes_no"
        && (action.confirmed === true || action.commandTemplate?.confirmed === true || /yes/i.test(action.label ?? ""))
    );
    if (yes) return yes;

    const amount = actions.find((action) => action.type === "choose_amount" && damageAssignmentAmount(action) > 0)
      ?? actions.find((action) => action.type === "choose_amount");
    if (amount) {
      const chosen = damageAssignmentAmount(amount);
      return {
        ...amount,
        amount: chosen,
        commandTemplate: {
          ...(amount.commandTemplate ?? {}),
          amount: chosen
        }
      };
    }
  }

  const blocker = actions.find((action) =>
    action.type === "declare_blockers"
      && /metalwork colossus/i.test(action.label ?? action.cardName ?? "")
      && ((action.blockers?.length ?? action.commandTemplate?.blockers?.length ?? 0) > 1 || /with \d+ creatures/i.test(action.label ?? ""))
  ) ?? actions.find((action) =>
    action.type === "declare_blockers" && /metalwork colossus/i.test(action.label ?? action.cardName ?? "")
  ) ?? actions.find((action) => action.type === "declare_blockers");
  if (blocker) return blocker;

  return actions.find((action) =>
    action.type === "pass_priority"
      || action.type === "pass_until_response"
      || action.type === "advance_phase"
      || action.type === "pass_until_next_turn"
  ) ?? actions.find((action) => action.type === "declare_blockers");
}

function damageAssignmentAmount(action: SmokeAction) {
  const raw = action.amount ?? action.commandTemplate?.amount ?? Number(action.choiceIds?.[0]);
  if (Number.isFinite(raw) && raw > 0) {
    return Number(raw);
  }
  return 1;
}

function explicitSmokeMultiAmounts(snapshot: SmokeSnapshot) {
  const prompt = snapshot.promptEnvelopeV2;
  const slots = prompt?.multiAmounts ?? [];
  if (slots.length === 0) {
    throw new Error("[Smoke] choose_multi_amount prompt did not include multiAmounts metadata.");
  }
  const totalMin = prompt?.totalMin ?? prompt?.minChoices ?? 0;
  const totalMax = prompt?.totalMax ?? prompt?.maxChoices ?? totalMin;
  const amounts = slots.map((slot) => Math.max(slot.min, Math.min(slot.max, slot.defaultValue ?? slot.min)));
  let total = amounts.reduce((sum, amount) => sum + amount, 0);

  for (let i = 0; i < slots.length && total < totalMin; i += 1) {
    const add = Math.min(slots[i].max - amounts[i], totalMin - total);
    if (add > 0) {
      amounts[i] += add;
      total += add;
    }
  }

  if (totalMax >= totalMin) {
    for (let i = slots.length - 1; i >= 0 && total > totalMax; i -= 1) {
      const remove = Math.min(amounts[i] - slots[i].min, total - totalMax);
      if (remove > 0) {
        amounts[i] -= remove;
        total -= remove;
      }
    }
  }

  if (total < totalMin || total > totalMax) {
    throw new Error(`[Smoke] could not build legal multi-amount allocation for total range ${totalMin}-${totalMax}.`);
  }
  return amounts;
}

function chooseCommanderGauntletAction(snapshot: SmokeSnapshot): SmokeAction | undefined {
  const actions = snapshot.legalActions ?? [];

  if (snapshot.promptEnvelopeV2) {
    return undefined;
  }

  const playPlains = actions.find((action) =>
    action.type === "play_land" && /plains/i.test(action.cardName ?? action.label ?? "")
  );
  if (!gauntlet.playedLand && playPlains) return playPlains;

  const castManaRock = actions.find((action) =>
    action.type === "cast_spell" && /\b(sol ring|arcane signet)\b/i.test(action.cardName ?? action.label ?? "")
  );
  if (!gauntlet.castManaRock && castManaRock) return castManaRock;

  const playFetch = actions.find((action) =>
    action.type === "play_land" && /\b(evolving wilds|terramorphic expanse|fabled passage)\b/i.test(action.cardName ?? action.label ?? "")
  );
  if (!gauntlet.fetchActivated && playFetch) return playFetch;

  const activateFetch = actions.find((action) =>
    action.type === "activate_ability" && /\b(evolving wilds|terramorphic expanse|fabled passage)\b/i.test(action.cardName ?? action.label ?? "")
  );
  if (!gauntlet.searchResolved && activateFetch) return activateFetch;

  const castCommander = actions.find((action) =>
    action.type === "cast_spell"
      && ((action.sourceZone ?? action.commandTemplate?.sourceZone) === "command"
        || isKnownCommanderText(action.cardName ?? action.label ?? ""))
  );
  if ((!gauntlet.commanderCast || commanderTaxChanges.length > 0) && castCommander) return castCommander;

  const castCompanion = actions.find((action) =>
    action.type === "cast_spell" && /spirited companion/i.test(action.cardName ?? action.label ?? "")
  );
  if (!gauntlet.etbOrTriggerSeen && castCompanion) return castCompanion;

  const removeCommander = actions.find((action) =>
    action.type === "cast_spell" && /swords to plowshares/i.test(action.cardName ?? action.label ?? "")
  );
  if (gauntlet.commanderCast && !gauntlet.commanderRemoved && removeCommander) return removeCommander;

  const nonManaAbility = actions.find((action) =>
    action.type === "activate_ability"
      && !/\b(evolving wilds|terramorphic expanse)\b/i.test(action.cardName ?? action.label ?? "")
      && !looksLikeManaAction(action)
  );
  if (!gauntlet.activatedAbilityUsed && nonManaAbility) return nonManaAbility;

  const makeMana = actions.find((action) => action.type === "make_mana");
  if (makeMana && (gauntlet.castManaRock || !gauntlet.tappedManaSource)) return makeMana;

  const attacker = actions.find((action) => action.type === "declare_attackers");
  if (attacker) return attacker;

  return actions.find((action) =>
    action.type === "pass_priority" || action.type === "pass_until_response" || action.type === "pass_until_next_turn" || action.type === "advance_phase"
  );
}

function chooseManaRockAction(snapshot: SmokeSnapshot): SmokeAction | undefined {
  const actions = snapshot.legalActions ?? [];
  const battlefield = humanZone(snapshot, "battlefield");
  const landCount = battlefield.filter((entry) => /land/i.test(entry.card?.typeLine ?? "") || /plains/i.test(entry.card?.name ?? "")).length;
  const hasManaRockInHand = humanZone(snapshot, "hand").some((entry) => isManaRockName(entry.card?.name ?? ""));

  if (snapshot.promptEnvelopeV2 && isManaOrPaymentPrompt(snapshot)) {
    const sourceMana = actions.find((action) => action.type === "make_mana");
    if (sourceMana) return sourceMana;
    const pay = actions.find((action) => action.type === "pay_cost" && action.pay !== false);
    if (pay) return pay;
    const mana = actions.find((action) => action.type === "play_mana" || action.type === "choose_mana");
    if (mana) return mana;
  }

  if (landCount < 2) {
    const land = actions.find((action) => action.type === "play_land" && /plains/i.test(action.cardName ?? action.label ?? ""));
    if (land) return land;
  }

  if (manaRockCastSeen && !manaRockResolvedSeen) {
    const sourceMana = actions.find((action) => action.type === "make_mana");
    if (sourceMana) return sourceMana;
  }

  if (landCount >= 2 && hasManaRockInHand) {
    const castManaRock = actions.find((action) =>
      action.type === "cast_spell" && isManaRockAction(action)
    );
    if (castManaRock) return castManaRock;
  }

  return actions.find((action) =>
    action.type === "pass_priority" || action.type === "pass_until_response" || action.type === "pass_until_next_turn" || action.type === "advance_phase"
  );
}

function chooseDragCastRegressionAction(snapshot: SmokeSnapshot): SmokeAction | undefined {
  const actions = snapshot.legalActions ?? [];
  const battlefield = humanZone(snapshot, "battlefield");
  const hasManaRockInHand = humanZone(snapshot, "hand").some((entry) => isManaRockName(entry.card?.name ?? ""));

  if (snapshot.promptEnvelopeV2 && isManaOrPaymentPrompt(snapshot)) {
    const sourceMana = actions.find((action) => action.type === "make_mana");
    if (sourceMana) return sourceMana;
    const pay = actions.find((action) => action.type === "pay_cost" && action.pay !== false);
    if (pay) return pay;
    const mana = actions.find((action) => action.type === "play_mana" || action.type === "choose_mana");
    if (mana) return mana;
  }

  if (!dragCastLandSeen) {
    const dragLand = iosDragPlayableActions(snapshot, "play_land")
      .find((action) => /land|plains|forest|island|mountain|swamp/i.test(action.cardName ?? action.label ?? ""));
    if (dragLand) return dragLand;
  }

  if (manaRockCastSeen && !manaRockResolvedSeen) {
    const sourceMana = actions.find((action) => action.type === "make_mana");
    if (sourceMana) return sourceMana;
  }

  if (battlefield.length >= 2 && hasManaRockInHand) {
    const castManaRock = iosDragPlayableActions(snapshot, "cast_spell")
      .find((action) => isManaRockAction(action));
    if (castManaRock) return castManaRock;
  }

  return actions.find((action) =>
    action.type === "pass_priority" || action.type === "pass_until_response" || action.type === "pass_until_next_turn" || action.type === "advance_phase"
  );
}

function choosePromptTarget(snapshot: SmokeSnapshot): SmokeAction | undefined {
  const actions = snapshot.legalActions?.filter(a =>
    a.type === "choose_target"
      || a.type === "resolve_choice"
      || a.type === "choose_card"
      || a.type === "search_select"
  ) ?? [];
  if (actions.length === 0) return undefined;

  const message = `${snapshot.promptText ?? ""} ${snapshot.promptEnvelopeV2?.message ?? ""}`.toLowerCase();
  if (message.includes("starting player")) {
    return actions.find((action) => /you start/i.test(action.label ?? "")) ?? actions[0];
  }
  const requestedCardName = requestedCardNameFromPrompt(message);
  if (requestedCardName) {
    const requested = actions.find((action) => actionName(action).toLowerCase() === requestedCardName)
      ?? actions.find((action) => actionName(action).toLowerCase().includes(requestedCardName));
    if (requested) return requested;
  }
  if (message.includes("basic land")) {
    return multiChoiceAction(snapshot, actions, actions.filter(isBasicLandAction))
      ?? multiChoiceAction(snapshot, actions, actions.filter((action) => /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? "")))
      ?? actions.find(isBasicLandAction)
      ?? actions.find((action) => /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? ""))
      ?? actions[0];
  }
  if (message.includes("land card")) {
    return multiChoiceAction(snapshot, actions, actions.filter((action) => /land/i.test(action.typeLine ?? "")))
      ?? multiChoiceAction(snapshot, actions, actions.filter((action) => /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? "")))
      ?? actions.find((action) => /land/i.test(action.typeLine ?? ""))
      ?? actions.find((action) => /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? ""))
      ?? actions[0];
  }
  if (message.includes("artifact") || message.includes("enchantment")) {
    return actions.find((action) => /sol ring|arcane signet/i.test(action.label ?? action.cardName ?? ""))
      ?? actions.find((action) => /artifact|enchantment/i.test(action.typeLine ?? ""))
      ?? actions[0];
  }
  if (message.includes("creature")) {
    if (commanderGauntletScenario) {
      const commander = actions.find((action) => isKnownCommanderText(action.label ?? action.cardName ?? ""));
      if (commander) return commander;
    }
    return actions.find((action) => /creature/i.test(action.typeLine ?? "")) ?? actions[0];
  }
  return actions[0];
}

function multiChoiceAction(snapshot: SmokeSnapshot, actions: SmokeAction[], matches: SmokeAction[]) {
  const maxChoices = snapshot.promptEnvelopeV2?.maxChoices ?? 1;
  if (maxChoices <= 1 || matches.length < maxChoices) {
    return undefined;
  }
  const first = matches[0];
  const targetIds = matches
    .map((action) => action.cardInstanceId ?? action.targetIds?.[0] ?? action.validTargetIds?.[0] ?? action.id?.replace(/^xmage-choice-/, ""))
    .filter((id): id is string => Boolean(id))
    .slice(0, maxChoices);
  if (targetIds.length < maxChoices) {
    return undefined;
  }
  return {
    ...first,
    label: `Choose ${targetIds.length} ${actionName(first).replace(/^Choose /i, "")} cards`,
    targetIds,
    cardInstanceIds: first.type === "choose_card" || first.type === "search_select" ? targetIds : first.cardInstanceIds,
    commandTemplate: {
      ...(first.commandTemplate ?? {}),
      targetIds
    }
  };
}

function requestedCardNameFromPrompt(message: string) {
  const match = message.match(/\bselect(?: an?| one)? ([a-z0-9,' -]+?) card\b/i)
    ?? message.match(/\bchoose(?: an?| one)? ([a-z0-9,' -]+?) card\b/i);
  const requested = match?.[1]?.trim().toLowerCase();
  if (!requested || ["a", "an", "one", "target", "creature", "land", "basic land", "card"].includes(requested)) {
    return undefined;
  }
  return requested;
}

function actionName(action: SmokeAction) {
  return action.cardName ?? action.label ?? "";
}

function knownCommanderName() {
  return human.commander?.cardName ?? "";
}

function isKnownCommanderText(text: string) {
  const name = knownCommanderName();
  return Boolean(name) && text.toLowerCase().includes(name.toLowerCase());
}

function isKnownCommanderAction(action: SmokeAction) {
  return (action.sourceZone ?? action.commandTemplate?.sourceZone) === "command"
    || isKnownCommanderText(action.cardName ?? action.label ?? "");
}

function isKnownCommanderEntry(entry: { card?: { name?: string } }) {
  return isKnownCommanderText(entry.card?.name ?? "");
}

function isBasicLandAction(action: SmokeAction) {
  if (action.isBasicLand) return true;
  return /basic land/i.test(action.typeLine ?? "")
    || /\b(forest|island|mountain|plains|swamp|wastes)\b/i.test(action.label ?? action.cardName ?? "");
}

async function waitForAction(snapshot: SmokeSnapshot, type: string | string[], optional = false, label = "") {
  let current = snapshot;
  const deadline = Date.now() + (optional ? 10000 : 30000);
  while (true) {
    const action = findAction(current, type, label);
    if (action || Date.now() >= deadline) {
      return { snapshot: current, action };
    }
    await new Promise((resolve) => setTimeout(resolve, 750));
    current = await request(`/games/${encodeURIComponent(current.id)}`);
    assertBridgeSnapshot(current, `wait for action ${Array.isArray(type) ? type.join("/") : type}`);
  }
}

async function waitForAiIfNeeded(snapshot: SmokeSnapshot, label: string) {
  if (snapshot.waitingOnPlayerId !== aiPlayerId && snapshot.priorityPlayerId !== aiPlayerId) {
    return snapshot;
  }
  console.error(`[Smoke] Waiting for AI priority... active priority player: ${snapshot.priorityPlayerId}, waiting on: ${snapshot.waitingOnPlayerId}`);
  let current = snapshot;
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    current = await request(`/games/${encodeURIComponent(current.id)}`);
    assertBridgeSnapshot(current, label);
    if (current.engineHealth?.status && current.engineHealth.status !== "ready") {
      writeSmokeReport({
        ...baseSummaryReport(current),
        failedStep: "bridge-disconnected",
        failureReason: current.engineHealth.reason ?? `XMage bridge health is ${current.engineHealth.status}`
      });
      throw new Error(
        `XMage smoke ${label} stopped because the Java bridge disconnected.\n`
          + smokeDebug(`bridge disconnected during ${label}`, current)
      );
    }
    const actionable = current.legalActions?.some((action) => action.type !== "concede") ?? false;
    if (current.waitingOnPlayerId !== aiPlayerId || current.priorityPlayerId !== aiPlayerId || actionable) {
      console.error(`[Smoke] AI finished or action became available. New priority: ${current.priorityPlayerId}`);
      aiProgressObserved = true;
      return current;
    }
  }
  writeSmokeReport({
    ...baseSummaryReport(current),
    failedStep: "ai-priority-stall",
    failureReason: `Timed out waiting for AI progress during ${label}`,
    stallEvidence: {
      phase: current.phase,
      step: current.step,
      priorityPlayerId: current.priorityPlayerId,
      waitingOnPlayerId: current.waitingOnPlayerId,
      bridgeRevision: current.bridgeRevision ?? null,
      xmageCycle: current.xmageCycle ?? null,
      recentLog: (current.log ?? []).slice(-8)
    }
  });
  throw new Error(
    `XMage smoke ${label} timed out waiting for AI progress.\n`
      + smokeDebug(`AI stalled during ${label}`, current)
  );
}

async function waitForSemanticProgress(previous: SmokeSnapshot, next: SmokeSnapshot, label: string) {
  let current = next;
  const deadline = Date.now() + semanticProgressDeadlineMs(label);
  while (
    (!hasSemanticProgress(previous, current, label) || !bridgeProgressed(previous, current))
      && Date.now() < deadline
  ) {
    await new Promise((resolve) => setTimeout(resolve, 750));
    current = await request(`/games/${encodeURIComponent(current.id)}`);
    assertBridgeSnapshot(current, `semantic progress ${label}`);
  }
  return current;
}

function semanticProgressDeadlineMs(label: string) {
  if (manaRockScenario && label === "cast simple spell") return 5000;
  if (label === "cast simple spell") return 30000;
  if (label === "resolve prompt") return 20000;
  return 15000;
}

function commandFromAction(gameId: string, action: SmokeAction, snapshot: SmokeSnapshot) {
  const template = { ...(action.commandTemplate ?? {}) };
  delete template.multiAmounts;

  // Determine max choices allowed by prompt
  let maxChoices = 1;
  if (snapshot.promptEnvelopeV2) {
    maxChoices = snapshot.promptEnvelopeV2.maxChoices ?? 1;
  }

  // Helper to slice array to maxChoices if needed
  const sliceToMax = (arr: string[] | undefined) => {
    if (!arr) return undefined;
    if (maxChoices > 0 && arr.length > maxChoices) {
      return arr.slice(0, maxChoices);
    }
    return arr;
  };

  const rawTargetIds = action.targetIds ?? action.validTargetIds ?? template.targetIds ?? template.choiceIds;
  const targetIds = sliceToMax(rawTargetIds);

  const rawCardInstanceIds = action.cardInstanceIds ?? action.validCardInstanceIds ?? template.cardInstanceIds ?? rawTargetIds;
  const cardInstanceIds = sliceToMax(rawCardInstanceIds);

  const rawPlayerIds = action.playerIds ?? action.validPlayerIds ?? template.playerIds ?? rawTargetIds;
  const playerIds = sliceToMax(rawPlayerIds);

  const rawChoiceIds = action.choiceIds
    ?? template.choiceIds
    ?? (action.type === "resolve_choice" ? rawTargetIds : undefined);
  const choiceIds = sliceToMax(rawChoiceIds);

  const rawModeIds = action.modeIds ?? template.modeIds ?? rawTargetIds;
  const modeIds = sliceToMax(rawModeIds);

  const command: SmokeCommandTemplate & { gameId: string } = {
    ...template,
    type: action.type ?? template.type,
    gameId,
    playerId: action.playerId ?? template.playerId ?? humanPlayerId,
    promptId: action.promptId ?? template.promptId,
    messageId: action.messageId ?? template.messageId,
    cardInstanceId: action.cardInstanceId ?? template.cardInstanceId,
    sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId ?? template.sourceInstanceId ?? template.cardInstanceId,
    abilityId: action.abilityId ?? template.abilityId,
    choiceIds,
    targetIds,
    cardInstanceIds,
    modeIds,
    playerIds,
    manaType: action.manaType ?? template.manaType,
    manaTypes: action.manaTypes ?? template.manaTypes,
    orderedIds: action.orderedIds ?? template.orderedIds ?? targetIds,
    confirmed: action.confirmed ?? template.confirmed,
    pay: action.pay ?? template.pay,
    amount: action.amount ?? template.amount,
    amounts: action.amounts ?? template.amounts,
    pile: action.pile ?? template.pile,
    useCommandZone: action.useCommandZone ?? template.useCommandZone,
    attackers: action.attackers ?? template.attackers,
    blockers: action.blockers ?? template.blockers
  };
  return pruneUndefined(command);
}

function assertLegalActionBeforeSubmit(snapshot: SmokeSnapshot, action: SmokeAction) {
  const legalActions = snapshot.legalActions ?? [];
  const legal = legalActions.some((candidate) =>
    candidate === action
      || (action.id !== undefined && candidate.id === action.id)
      || (
        candidate.type === action.type
          && candidate.label === action.label
          && candidate.cardInstanceId === action.cardInstanceId
          && candidate.sourceInstanceId === action.sourceInstanceId
      )
  );
  if (!legal) {
    throw new Error(
      `[Smoke] refusing to submit ${action.type}; action is not present in current legalActions.\n`
        + smokeDebug("illegal submit snapshot", snapshot)
    );
  }
}

function assertCommandUsesLegalAction(action: SmokeAction, command: Record<string, unknown>) {
  const template = action.commandTemplate ?? {};
  const allowedSources = [action, template];
  const equivalentSelectionFields = [
    "choiceIds",
    "targetIds",
    "validTargetIds",
    "cardInstanceIds",
    "validCardInstanceIds",
    "playerIds",
    "validPlayerIds",
    "modeIds",
    "orderedIds"
  ];
  const exactFieldNames = [
    "type",
    "playerId",
    "promptId",
    "messageId",
    "cardInstanceId",
    "sourceInstanceId",
    "abilityId",
    "choiceIds",
    "targetIds",
    "cardInstanceIds",
    "modeIds",
    "playerIds",
    "manaType",
    "manaTypes",
    "orderedIds",
    "confirmed",
    "pay",
    "amount",
    "amounts",
    "pile",
    "useCommandZone",
    "attackers",
    "blockers"
  ];
  for (const field of exactFieldNames) {
    if (!(field in command)) continue;
    const value = command[field];
    if (field === "playerId" && value === humanPlayerId && action.playerId === undefined && template.playerId === undefined) continue;
    if (
      allowedSources.some((source) => field in source && JSON.stringify((source as Record<string, unknown>)[field]) === JSON.stringify(value))
        || (field === "sourceInstanceId" && value === action.cardInstanceId)
        || (field === "orderedIds" && JSON.stringify(value) === JSON.stringify(command.targetIds))
        || (equivalentSelectionFields.includes(field) && selectionValueDerived(value, allowedSources, equivalentSelectionFields))
    ) {
      continue;
    }
    throw new Error(`[Smoke] command field ${field} was not derived from the LegalAction or commandTemplate.`);
  }
}

function iosDragPlayableActions(snapshot: SmokeSnapshot, type: "play_land" | "cast_spell") {
  const handIds = new Set(humanZone(snapshot, "hand").map((entry) => entry.instanceId).filter(Boolean));
  return (snapshot.legalActions ?? []).filter((action) => {
    if (action.type !== type) return false;
    const sourceId = effectiveActionSourceInstanceId(action);
    const cardId = effectiveActionCardInstanceId(action);
    return Boolean((sourceId && handIds.has(sourceId)) || (cardId && handIds.has(cardId)));
  });
}

function assertIosDragCommandUsesCurrentHandLegalAction(
  snapshot: SmokeSnapshot,
  action: SmokeAction,
  command: Record<string, unknown>
) {
  const handIds = new Set(humanZone(snapshot, "hand").map((entry) => entry.instanceId).filter(Boolean));
  const actionSourceId = effectiveActionSourceInstanceId(action);
  const actionCardId = effectiveActionCardInstanceId(action);
  const commandSourceId = typeof command.sourceInstanceId === "string" ? command.sourceInstanceId : undefined;
  const commandCardId = typeof command.cardInstanceId === "string" ? command.cardInstanceId : undefined;

  if (!actionSourceId && !actionCardId) {
    throw new Error(`[Smoke] drag action ${action.type} did not include source/card ids or commandTemplate ids.`);
  }
  if (!((actionSourceId && handIds.has(actionSourceId)) || (actionCardId && handIds.has(actionCardId)))) {
    throw new Error(
      `[Smoke] drag action ${action.type} did not match a current hand card.\n`
        + smokeDebug("drag action mismatch snapshot", snapshot)
    );
  }
  if (commandSourceId !== actionSourceId && commandCardId !== actionCardId) {
    throw new Error(
      `[Smoke] drag command did not preserve the current LegalAction ids: `
        + `actionSource=${actionSourceId ?? "n/a"} actionCard=${actionCardId ?? "n/a"} `
        + `commandSource=${commandSourceId ?? "n/a"} commandCard=${commandCardId ?? "n/a"}`
    );
  }
}

function effectiveActionSourceInstanceId(action: SmokeAction) {
  return action.commandTemplate?.sourceInstanceId ?? action.sourceInstanceId ?? action.cardInstanceId;
}

function effectiveActionCardInstanceId(action: SmokeAction) {
  return action.commandTemplate?.cardInstanceId ?? action.cardInstanceId ?? effectiveActionSourceInstanceId(action);
}

function selectionValueDerived(
  value: unknown,
  sources: Record<string, unknown>[],
  fields: string[]
) {
  return sources.some((source) =>
    fields.some((field) =>
      field in source && JSON.stringify(source[field]) === JSON.stringify(value)
    )
  );
}

function pruneUndefined<T extends Record<string, unknown>>(value: T) {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== undefined)) as Partial<T>;
}

function assertBridgeProgress(
  previous: SmokeSnapshot,
  next: SmokeSnapshot,
  label: string,
  options: { allowEqual?: boolean } = {}
) {
  const revisionAdvanced = advanced(previous.bridgeRevision, next.bridgeRevision, options.allowEqual);
  const cycleAdvanced = advanced(previous.xmageCycle, next.xmageCycle, options.allowEqual);
  if (!revisionAdvanced && !cycleAdvanced) {
    throw new Error(
      `XMage smoke ${label} did not advance bridgeRevision or xmageCycle: `
        + `${previous.bridgeRevision ?? "n/a"} -> ${next.bridgeRevision ?? "n/a"}, `
        + `${previous.xmageCycle ?? "n/a"} -> ${next.xmageCycle ?? "n/a"}`
    );
  }
}

function assertBridgeSnapshot(snapshot: SmokeSnapshot, label: string) {
  if (snapshot.source !== "xmage-java-bridge") {
    throw new Error(`XMage smoke ${label} did not return a Java bridge snapshot. Source: ${snapshot.source ?? "missing"}`);
  }
  if (/simulator/i.test(snapshot.source ?? "")) {
    throw new Error(`XMage smoke ${label} returned simulator source, which cannot count as product success.`);
  }
  if (typeof snapshot.bridgeRevision !== "number") {
    throw new Error(`XMage smoke ${label} did not include numeric bridgeRevision.`);
  }
  if (snapshot.xmageCycle !== undefined && typeof snapshot.xmageCycle !== "number") {
    throw new Error(`XMage smoke ${label} returned non-numeric xmageCycle.`);
  }
  if (lastBridgeRevision !== undefined && snapshot.bridgeRevision < lastBridgeRevision) {
    throw new Error(`XMage smoke ${label} bridgeRevision went backward: ${lastBridgeRevision} -> ${snapshot.bridgeRevision}`);
  }
  if (lastXmageCycle !== undefined && snapshot.xmageCycle !== undefined && snapshot.xmageCycle < lastXmageCycle) {
    throw new Error(`XMage smoke ${label} xmageCycle went backward: ${lastXmageCycle} -> ${snapshot.xmageCycle}`);
  }
  lastBridgeRevision = snapshot.bridgeRevision;
  if (snapshot.xmageCycle !== undefined) {
    lastXmageCycle = snapshot.xmageCycle;
  }
}

function assertSemanticProgress(previous: SmokeSnapshot, next: SmokeSnapshot, label: string) {
  if (hasSemanticProgress(previous, next, label)) {
    return;
  }
  if (next.pendingStatus) {
    return;
  }
  if (label === "play land") {
    throw new Error(`XMage smoke play land did not increase human battlefield count: ${humanZone(previous, "battlefield").length} -> ${humanZone(next, "battlefield").length}`);
  }
  if (label === "make mana") {
    throw new Error(
      `XMage smoke make mana did not increase human mana pool: ${manaTotal(previous)} -> ${manaTotal(next)}\n`
        + smokeDebug("before make_mana", previous)
        + "\n"
        + smokeDebug("after make_mana", next)
    );
  }
  if (label === "cast simple spell") {
    throw new Error(
      "XMage smoke cast simple spell did not change hand, board, graveyard, stack, mana, or prompt state.\n"
        + smokeDebug("before cast_spell", previous)
        + "\n"
        + smokeDebug("after cast_spell", next)
    );
  }
  if (label === "activate ability") {
    throw new Error(
      "XMage smoke activate ability did not change prompt, stack, zones, action list, or tapped state.\n"
        + smokeDebug("before activate_ability", previous)
        + "\n"
        + smokeDebug("after activate_ability", next)
    );
  }
  if (label === "pass priority") {
    throw new Error(
      "XMage smoke pass priority did not change priority, phase/step, prompt state, or visible game zones.\n"
        + smokeDebug("before pass_priority", previous)
        + "\n"
        + smokeDebug("after pass_priority", next)
    );
  }
}

function assertManaRockCastProgress(previous: SmokeSnapshot, next: SmokeSnapshot) {
  if (manaRockCastMadeProgress(previous, next)) return;
  const report = {
    ...baseSummaryReport(next),
    failedStep: "mana-rock-cast-no-progress",
    failureReason: `${manaRockCardName} cast action returned a real XMage snapshot but did not open a payment prompt, expose source make_mana actions, move the card, use mana, or put an object on the stack.`
  };
  writeSmokeReport(report);
  throw new Error(
    "[Smoke] mana-rock cast did not make real XMage gameplay progress.\n"
      + smokeDebug(`before ${manaRockCardName} cast`, previous)
      + "\n"
      + smokeDebug(`after ${manaRockCardName} cast`, next)
  );
}

function manaRockCastMadeProgress(previous: SmokeSnapshot, next: SmokeSnapshot) {
  return humanZone(next, "hand").filter((entry) => isManaRockName(entry.card?.name ?? "")).length
      < humanZone(previous, "hand").filter((entry) => isManaRockName(entry.card?.name ?? "")).length
    || humanZone(next, "battlefield").some((entry) => isManaRockName(entry.card?.name ?? ""))
    || humanZone(next, "stack").length > humanZone(previous, "stack").length
    || snapshotHasStackObject(next)
    || next.promptEnvelopeV2 !== undefined
    || manaTotal(previous) !== manaTotal(next)
    || (next.legalActions ?? []).some((action) => action.type === "make_mana" && next.promptEnvelopeV2 && isManaOrPaymentPrompt(next));
}

function isManaRockAction(action: SmokeAction) {
  return isManaRockName(action.cardName ?? action.label ?? "");
}

function isManaRockName(name: string) {
  return name.toLowerCase().includes(manaRockCardName.toLowerCase());
}

function hasSemanticProgress(previous: SmokeSnapshot, next: SmokeSnapshot, label: string) {
  if (label === "play land") {
    return humanZone(next, "battlefield").length > humanZone(previous, "battlefield").length;
  }
  if (label === "make mana") {
    return manaTotal(next) > manaTotal(previous)
      || humanZone(previous, "battlefield").some((beforeCard) => {
        const afterCard = humanZone(next, "battlefield").find((card) => card.instanceId === beforeCard.instanceId);
        return beforeCard.tapped !== true && afterCard?.tapped === true;
      })
      || previous.promptEnvelopeV2?.id !== next.promptEnvelopeV2?.id
      || humanZone(previous, "stack").length !== humanZone(next, "stack").length;
  }
  if (label === "activate ability") {
    return previous.promptEnvelopeV2?.id !== next.promptEnvelopeV2?.id
      || next.promptEnvelopeV2 !== undefined
      || humanZone(previous, "stack").length !== humanZone(next, "stack").length
      || zonesChanged(previous, next)
      || formatActions(previous) !== formatActions(next)
      || humanZone(previous, "battlefield").some((beforeCard) => {
        const afterCard = humanZone(next, "battlefield").find((card) => card.instanceId === beforeCard.instanceId);
        return beforeCard.tapped !== afterCard?.tapped;
      });
  }
  if (label === "cast simple spell") {
    return humanZone(previous, "hand").length !== humanZone(next, "hand").length
      || humanZone(previous, "battlefield").length !== humanZone(next, "battlefield").length
      || humanZone(previous, "graveyard").length !== humanZone(next, "graveyard").length
      || humanZone(previous, "stack").length !== humanZone(next, "stack").length
      || manaTotal(previous) !== manaTotal(next)
      || next.promptEnvelopeV2 !== undefined
      || next.pendingStatus === "waiting_for_xmage";
  }
  if (label === "combat") {
    return previous.step !== next.step
      || previous.phase !== next.phase
      || previous.turn !== next.turn
      || previous.priorityPlayerId !== next.priorityPlayerId
      || previous.waitingOnPlayerId !== next.waitingOnPlayerId
      || JSON.stringify(previous.xmage?.combat ?? null) !== JSON.stringify(next.xmage?.combat ?? null)
      || JSON.stringify(humanZone(previous, "battlefield")) !== JSON.stringify(humanZone(next, "battlefield"))
      || JSON.stringify(next.players?.map((player) => player.life)) !== JSON.stringify(previous.players?.map((player) => player.life))
      || previous.bridgeRevision !== next.bridgeRevision
      || previous.xmageCycle !== next.xmageCycle;
  }
  if (label === "pass priority") {
    return previous.priorityPlayerId !== next.priorityPlayerId
      || previous.waitingOnPlayerId !== next.waitingOnPlayerId
      || previous.step !== next.step
      || previous.phase !== next.phase
      || previous.turn !== next.turn
      || previous.promptText !== next.promptText
      || humanZone(previous, "hand").length !== humanZone(next, "hand").length
      || humanZone(previous, "battlefield").length !== humanZone(next, "battlefield").length
      || humanZone(previous, "graveyard").length !== humanZone(next, "graveyard").length
      || humanZone(previous, "stack").length !== humanZone(next, "stack").length
      || manaTotal(previous) !== manaTotal(next)
      || formatActions(previous) !== formatActions(next)
      || next.promptEnvelopeV2 !== undefined
      || previous.bridgeRevision !== next.bridgeRevision
      || previous.xmageCycle !== next.xmageCycle;
  }
  if (label === "resolve prompt") {
    return previous.promptEnvelopeV2?.id !== next.promptEnvelopeV2?.id
      || previous.promptEnvelopeV2?.messageId !== next.promptEnvelopeV2?.messageId
      || previous.promptEnvelopeV2?.method !== next.promptEnvelopeV2?.method
      || previous.promptEnvelopeV2?.responseKind !== next.promptEnvelopeV2?.responseKind
      || previous.promptText !== next.promptText
      || formatActions(previous) !== formatActions(next)
      || zonesChanged(previous, next)
      || humanZone(previous, "stack").length !== humanZone(next, "stack").length
      || previous.step !== next.step
      || previous.phase !== next.phase
      || next.pendingStatus !== undefined;
  }
  return true;
}

function bridgeProgressed(previous: SmokeSnapshot, next: SmokeSnapshot) {
  return advanced(previous.bridgeRevision, next.bridgeRevision) || advanced(previous.xmageCycle, next.xmageCycle);
}

function advanced(before: unknown, after: unknown, allowEqual = false) {
  if (typeof before !== "number" || typeof after !== "number") return;
  return allowEqual ? after >= before : after > before;
}

function hasPromptResponseAction(snapshot: SmokeSnapshot) {
  const expected = snapshot.promptEnvelopeV2?.responseCommand?.type;
  if (!expected) return Boolean(snapshot.legalActions?.length);
  return snapshot.legalActions?.some((action) =>
    action.type === expected
    || action.responseKind === expected
    || (expected === "choose_card" && action.type === "search_select")
    || (expected === "answer_yes_no" && ["keep_hand", "mulligan", "commander_replacement"].includes(action.type))
    || (expected === "resolve_choice" && ["answer_yes_no", "choose_target", "choose_card", "choose_player"].includes(action.type))
  ) ?? false;
}

function humanZone(snapshot: SmokeSnapshot, zone: string) {
  return humanPlayer(snapshot)?.zones?.[zone] ?? [];
}

function humanPlayer(snapshot: SmokeSnapshot) {
  return snapshot.players?.find((player) => player.playerId === humanPlayerId);
}

function manaTotal(snapshot: SmokeSnapshot) {
  const pool = humanPlayer(snapshot)?.manaPool ?? {};
  return Object.values(pool).reduce((total, value) => total + (typeof value === "number" ? value : 0), 0);
}

function snapshotHasStackObject(snapshot: SmokeSnapshot) {
  return ((snapshot.xmage?.stack as unknown[] | undefined)?.length ?? 0) > 0
    || humanZone(snapshot, "stack").length > 0
    || (snapshot.players ?? []).some((player) => (player.zones?.stack?.length ?? 0) > 0);
}

function zonesChanged(previous: SmokeSnapshot, next: SmokeSnapshot) {
  return JSON.stringify(zoneCounts(previous)) !== JSON.stringify(zoneCounts(next));
}

function zoneCounts(snapshot: SmokeSnapshot) {
  return (snapshot.players ?? []).map((player) => ({
    playerId: player.playerId,
    hand: player.zones?.hand?.length ?? 0,
    library: player.zones?.library?.length ?? 0,
    battlefield: player.zones?.battlefield?.length ?? 0,
    graveyard: player.zones?.graveyard?.length ?? 0,
    exile: player.zones?.exile?.length ?? 0,
    command: player.zones?.command?.length ?? 0,
    stack: player.zones?.stack?.length ?? 0
  }));
}

function recordCommanderState(snapshot: SmokeSnapshot) {
  for (const player of snapshot.players ?? []) {
    if (player.commanderTax !== undefined && player.commanderTax > 0) {
      if (!commanderTaxChanges.some(t => t.playerId === player.playerId && t.tax === player.commanderTax)) {
        commanderTaxChanges.push({ playerId: player.playerId, tax: player.commanderTax, turn: snapshot.turn ?? 1 });
        markRouteFamily("commander_tax_seen");
        console.error(`[Smoke] Witnessed Commander Tax: ${player.playerId} tax is now ${player.commanderTax} on turn ${snapshot.turn}`);
      }
    }
    for (const [oppId, dmg] of Object.entries(player.commanderDamage ?? {})) {
      if (typeof dmg === "number" && dmg > 0) {
        if (!commanderDamageChanges.some(d => d.recipient === player.playerId && d.attacker === oppId && d.damage === dmg)) {
          commanderDamageChanges.push({ recipient: player.playerId, attacker: oppId, damage: dmg, turn: snapshot.turn ?? 1 });
          console.error(`[Smoke] Witnessed Commander Damage: ${oppId} dealt ${dmg} to ${player.playerId} on turn ${snapshot.turn}`);
        }
      }
    }
  }
}

function recordRouteFamilyForAction(action: SmokeAction) {
  if (routeFamiliesRequired.length === 0) return;
  if (action.type === "play_land") markRouteFamily("play_land");
  if (action.type === "cast_spell") markRouteFamily("cast_spell");
  if (action.type === "make_mana") markRouteFamily("make_mana");
  if (action.type === "activate_ability") markRouteFamily("activate_ability");
  if (action.type === "choose_ability") markRouteFamily("choose_ability");
  if (action.type === "choose_mode") markRouteFamily("choose_mode");
  if (action.type === "choose_amount") markRouteFamily("choose_amount");
  if (action.type === "choose_multi_amount") markRouteFamily("choose_multi_amount");
  if (action.type === "choose_pile") markRouteFamily("choose_pile");
  if (action.type === "search_select" || action.type === "choose_card") markRouteFamily(action.type);
  if (action.type === "choose_target") markRouteFamily("choose_target");
  if (action.type === "answer_yes_no") markRouteFamily("answer_yes_no");
  if (action.type === "pay_cost") markRouteFamily("pay_cost");
  if (action.type === "choose_player") markRouteFamily("choose_player");
  if (action.type === "play_x_mana") markRouteFamily("play_x_mana");
  if (action.type === "choose_mana") markRouteFamily("choose_mana");
  if (action.type === "generic_replacement") markRouteFamily("generic_replacement");
  if (action.type === "mulligan") markRouteFamily("mulligan");
  if (damageAssignmentScenario && isDamageAssignmentPromptAction(action)) {
    markRouteFamily("damage_assignment");
    damageAssignmentChoiceSubmitted = true;
  }
  if (action.type === "commander_replacement") markRouteFamily("commander_replacement");
  if (action.type === "play_mana" || action.type === "choose_mana") markRouteFamily("pay_cost");
  if (["pass_priority", "pass_until_response", "pass_until_next_turn", "advance_phase"].includes(action.type)) {
    markRouteFamily("pass_priority");
  }
  if (action.type === "order_triggers" || action.type === "order_items") {
    markRouteFamily("order_triggers/order_items");
    markRouteFamily("trigger_seen");
  }
}

function recordFixtureOpeningPromptCoverage(harness: any) {
  const operations = Array.isArray(harness?.operationsApplied) ? harness.operationsApplied : [];
  if (operations.includes("pre_seed_opening_prompt:choose_player")) {
    markRouteFamily("choose_player");
    actionsByType.choose_player = Math.max(actionsByType.choose_player ?? 0, 1);
    completed.push("[Fixture opening] choose_player: real XMage starting-player prompt answered before deterministic seed");
  }
}

function recordRouteFamilyForPrompt(snapshot: SmokeSnapshot) {
  if (routeFamiliesRequired.length === 0 || !snapshot.promptEnvelopeV2) return;
  const expected = `${snapshot.promptEnvelopeV2.responseCommand?.type ?? ""} ${snapshot.promptEnvelopeV2.responseKind ?? ""}`.toLowerCase();
  const promptText = `${snapshot.promptEnvelopeV2.method ?? ""} ${snapshot.promptEnvelopeV2.message ?? ""} ${snapshot.promptText ?? ""}`.toLowerCase();
  if (expected.includes("target")) markRouteFamily("choose_target");
  if (expected.includes("card")) markRouteFamily("choose_card");
  if (expected.includes("player")) markRouteFamily("choose_player");
  if (expected.includes("search")) markRouteFamily("search_select");
  if (expected.includes("ability")) markRouteFamily("choose_ability");
  if (expected.includes("mode")) markRouteFamily("choose_mode");
  if (expected.includes("generic_replacement")) markRouteFamily("generic_replacement");
  if (expected.includes("multi_amount")) {
    markRouteFamily("choose_multi_amount");
  } else if (expected.includes("amount")) {
    markRouteFamily("choose_amount");
  }
  if (expected.includes("play_x_mana") || expected.includes("x_mana")) markRouteFamily("play_x_mana");
  if (expected.includes("choose_mana")) markRouteFamily("choose_mana");
  if (expected.includes("pile")) markRouteFamily("choose_pile");
  if (expected.includes("order") || promptText.includes("order")) markRouteFamily("order_triggers/order_items");
  if (expected.includes("yes") || expected.includes("confirmation")) markRouteFamily("answer_yes_no");
  if (expected.includes("pay") || expected.includes("mana") || promptText.includes("pay")) markRouteFamily("pay_cost");
  if (damageAssignmentScenario && isDamageAssignmentPromptSnapshot(snapshot)) {
    damageAssignmentPromptSeen = true;
    markRouteFamily("damage_assignment");
  }
  if (
    expected.includes("commander")
      || promptText.includes("commander replacement")
      || promptText.includes("command zone")
      || (promptText.includes("commander") && promptText.includes("command"))
  ) {
    markRouteFamily("commander_replacement");
  }
  if (expected.includes("trigger")) markRouteFamily("order_triggers");
  if (expected.includes("order")) markRouteFamily("order_items");
  if (expected.includes("trigger") || expected.includes("order")) markRouteFamily("trigger_seen");
}

function recordRouteFamilyForTransition(previous: SmokeSnapshot, next: SmokeSnapshot) {
  if (routeFamiliesRequired.length === 0) return;
  if (snapshotHasStackObject(next)) {
    markRouteFamily("stack_object_seen");
  }
  if (zonesChanged(previous, next)) {
    markRouteFamily("zone_update_seen");
  }
  const promptText = `${next.promptText ?? ""} ${next.promptEnvelopeV2?.method ?? ""} ${next.promptEnvelopeV2?.responseKind ?? ""} ${next.promptEnvelopeV2?.message ?? ""}`.toLowerCase();
  if (promptText.includes("trigger") || promptText.includes("order")) {
    markRouteFamily("trigger_seen");
  }
  if (promptText.includes("command zone") || (promptText.includes("commander") && promptText.includes("command"))) {
    markRouteFamily("commander_replacement");
  }
  if (promptText.includes("pay") || promptText.includes("mana")) {
    markRouteFamily("pay_cost");
  }
  if (damageAssignmentScenario && (isDamageAssignmentPromptSnapshot(previous) || isDamageAssignmentPromptSnapshot(next))) {
    damageAssignmentPromptSeen = true;
    markRouteFamily("damage_assignment");
  }
}

function recordGauntletAction(snapshot: SmokeSnapshot, action: SmokeAction) {
  if (!commanderGauntletScenario) return;

  if (action.type === "play_land") {
    gauntlet.playedLand = true;
  }
  if (action.type === "cast_spell" && /\b(sol ring|arcane signet)\b/i.test(action.cardName ?? action.label ?? "")) {
    gauntlet.castManaRock = true;
  }
  if (action.type === "make_mana") {
    gauntlet.tappedManaSource = true;
  }
  if (action.type === "activate_ability" && /\b(evolving wilds|terramorphic expanse|fabled passage)\b/i.test(action.cardName ?? action.label ?? "")) {
    gauntlet.fetchActivated = true;
  }
  if (action.type === "cast_spell" && isKnownCommanderAction(action)) {
    gauntlet.commanderCast = true;
    if (commanderTaxChanges.some((entry) => entry.playerId === humanPlayerId && entry.tax >= 2)) {
      gauntlet.commanderRecastWithTax = true;
    }
  }
  if (action.type === "activate_ability" && !looksLikeManaAction(action)) {
    gauntlet.activatedAbilityUsed = true;
  }
  if (
    action.type === "commander_replacement"
      || (
        action.type === "answer_yes_no"
          && snapshot.promptEnvelopeV2
          && `${snapshot.promptEnvelopeV2.responseKind ?? ""} ${snapshot.promptEnvelopeV2.message ?? ""} ${snapshot.promptText ?? ""}`.toLowerCase().includes("command")
      )
  ) {
    gauntlet.commanderReplacementAnswered = true;
  }
  recordGauntletSnapshot(snapshot);
}

function recordGauntletSnapshot(snapshot: SmokeSnapshot) {
  if (!commanderGauntletScenario) return;

  const stack = (snapshot.xmage?.stack as unknown[] | undefined) ?? humanZone(snapshot, "stack");
  if (stack.length > 0) {
    gauntlet.stackObjectSeen = true;
  }

  const humanBattlefield = humanZone(snapshot, "battlefield");
  const humanGraveyard = humanZone(snapshot, "graveyard");
  const humanCommand = humanZone(snapshot, "command");
  if (humanBattlefield.some((entry) => /land/i.test(entry.card?.typeLine ?? "") || /\b(plains|island|swamp|mountain|forest|wastes)\b/i.test(entry.card?.name ?? ""))) {
    gauntlet.playedLand = true;
  }
  if (humanBattlefield.some((entry) => /\b(sol ring|arcane signet)\b/i.test(entry.card?.name ?? ""))) {
    gauntlet.castManaRock = true;
  }
  if (
    humanGraveyard.some((entry) => /\b(evolving wilds|terramorphic expanse|fabled passage)\b/i.test(entry.card?.name ?? ""))
      && humanBattlefield.some((entry) => /plains/i.test(entry.card?.name ?? ""))
  ) {
    gauntlet.searchResolved = true;
    markRouteFamily("search_select/choose_card");
  }
  const commanderOnBattlefield = humanBattlefield.some(isKnownCommanderEntry);
  if (commanderOnBattlefield) {
    gauntlet.commanderCast = true;
    commanderBattlefieldSeen = true;
  }
  if (
    commanderBattlefieldSeen
      && !commanderOnBattlefield
      && (
        humanGraveyard.some((entry) => /swords to plowshares/i.test(entry.card?.name ?? ""))
          || humanCommand.some(isKnownCommanderEntry)
      )
    ) {
    gauntlet.commanderRemoved = true;
  }
  if (
    humanBattlefield.some((entry) => /spirited companion/i.test(entry.card?.name ?? ""))
      || humanGraveyard.some((entry) => /spirited companion/i.test(entry.card?.name ?? ""))
  ) {
    gauntlet.etbOrTriggerSeen = true;
    markRouteFamily("trigger_seen");
  }
  if (aiWaits > 0 || turnsObserved.has(2)) {
    gauntlet.aiTurnContinued = true;
  }

  if (snapshot.promptEnvelopeV2) {
    const pKey = `${snapshot.promptEnvelopeV2.method ?? "unknown"}:${snapshot.promptEnvelopeV2.responseKind ?? "unknown"}`;
    gauntletPromptFamilies.add(pKey);
  }
}

function commanderGauntletMissingSteps() {
  const missing = Object.entries(gauntlet)
    .filter(([, done]) => !done)
    .map(([step]) => step);
  if (!useFixtureHarness) {
    missing.unshift("fixture_call");
  }
  if (!directStateSeeded) {
    missing.unshift("direct_state_seeded");
  }
  if (!seededStateVerified) {
    missing.unshift("seeded_state_verified");
  }
  for (const family of missingRouteFamilies()) {
    missing.push(`route_family:${family}`);
  }
  return Array.from(new Set(missing));
}

function recordCoverage(snapshot: SmokeSnapshot) {
  if (typeof snapshot.turn === "number") {
    turnsObserved.add(snapshot.turn);
  }
  recordPromptSample(snapshot);
  recordRouteFamilyForPrompt(snapshot);
  const phaseStep = `${snapshot.phase ?? ""} ${snapshot.step ?? ""}`.toLowerCase();
  if (phaseStep.includes("combat") || phaseStep.includes("attack") || phaseStep.includes("block")) {
    combatStepSeen = true;
  }
  if (snapshotHasStackObject(snapshot)) {
    stackSeen = true;
    markRouteFamily("stack_object_seen");
  }
  if (manaRockLikeScenario && humanZone(snapshot, "battlefield").some((entry) => isManaRockName(entry.card?.name ?? ""))) {
    manaRockResolvedSeen = true;
  }
  if (
    promptMultiAmountScenario
      && promptMultiAmountChoiceSubmitted
      && (snapshot.promptEnvelopeV2?.responseKind ?? "") !== "multi_amount"
  ) {
    promptMultiAmountChoiceResolved = true;
  }
  if (
    promptPileScenario
      && promptPileChoiceSubmitted
      && (snapshot.promptEnvelopeV2?.responseKind ?? "") !== "pile"
  ) {
    promptPileChoiceResolved = true;
  }
  if (
    triggeredAbilityScenario
      && (
        humanZone(snapshot, "battlefield").some((entry) => /spirited companion/i.test(entry.card?.name ?? ""))
          || humanZone(snapshot, "graveyard").some((entry) => /spirited companion/i.test(entry.card?.name ?? ""))
      )
  ) {
    markRouteFamily("trigger_seen");
  }
  if (promptModeScenario && promptModeResolvedFromSnapshot(snapshot)) {
    promptModeChoiceResolved = true;
    markRouteFamily("choose_mode");
  }
  recordGauntletSnapshot(snapshot);
}

function recordPromptSample(snapshot: SmokeSnapshot) {
  if (!(promptOrderScenario || promptModeScenario || promptAmountScenario || promptMultiAmountScenario || promptPileScenario || scenario === "prompt-variety" || damageAssignmentScenario)) {
    return;
  }
  if (!snapshot.promptEnvelopeV2 || promptSamples.length >= 10) {
    return;
  }
  promptSamples.push({
    turn: snapshot.turn,
    phase: snapshot.phase,
    step: snapshot.step,
    promptText: snapshot.promptText,
    promptEnvelopeV2: snapshot.promptEnvelopeV2,
    legalActions: snapshot.legalActions?.map((action) => ({
      type: action.type,
      label: action.label,
      promptId: action.promptId,
      messageId: action.messageId,
      targetIds: action.targetIds,
      orderedIds: action.orderedIds,
      choiceIds: action.choiceIds,
      pile: action.pile,
      cardName: action.cardName,
      responseKind: action.responseKind
    }))
  });
}

function scenarioSatisfied() {
  if (scenario === "core-flow") {
    const realGameActionSeen = Boolean(
      actionsByType.play_land
        || actionsByType.make_mana
        || actionsByType.cast_spell
        || actionsByType.activate_ability
        || actionsByType.answer_yes_no
        || promptChecks.length > 0
    );
    return turnsObserved.size >= 4
      && Boolean(actionsByType.keep_hand || actionsByType.mulligan)
      && Boolean(actionsByType.pass_priority || actionsByType.pass_until_response || actionsByType.pass_until_next_turn || actionsByType.advance_phase)
      && aiProgressObserved
      && combatStepSeen
      && realGameActionSeen;
  }
  if (scenario === "opening-start-player" || scenario === "starting-player-choice") return actionsByType.choose_player > 0;
  if (scenario === "ai-turn-progress") return aiProgressObserved;
  if (scenario === "blocker-flow") return blockerAssignmentExercised;
  if (scenario === "commander-replacement-tax") return commanderTaxChanges.length > 0;
  if (scenario === "commander-damage") return commanderDamageChanges.length > 0;
  if (scenario === "mana-rock") return manaRockCastSeen && manaRockPaymentSourceSeen && manaRockResolvedSeen;
  if (scenario === "drag-cast-regression") return dragCastLandSeen && manaRockCastSeen && manaRockPaymentSourceSeen && manaRockResolvedSeen;
  if (scenario === "drag-cast-phone-regression") return manaRockCastSeen && manaRockPaymentSourceSeen && stackSeen;
  if (scenario === "search-select") return gauntlet.searchResolved || actionsByType.search_select > 0;
  if (scenario === "prompt-variety") return promptVarietyRouteFamiliesSatisfied();
  if (scenario === "prompt-mode") return missingRouteFamilies().length === 0 && promptModeChoiceSubmitted && promptModeChoiceResolved;
  if (scenario === "prompt-order") return missingRouteFamilies().length === 0 && promptOrderChoiceSubmitted;
  if (scenario === "prompt-amount") return missingRouteFamilies().length === 0 && promptAmountChoiceSubmitted;
  if (promptMultiAmountScenario) return missingRouteFamilies().length === 0 && promptMultiAmountChoiceSubmitted && promptMultiAmountChoiceResolved;
  if (promptPileScenario) return missingRouteFamilies().length === 0 && promptPileChoiceSubmitted && promptPileChoiceResolved;
  if (damageAssignmentScenario) return missingRouteFamilies().length === 0 && damageAssignmentPromptSeen && damageAssignmentChoiceSubmitted;
  if (scenario === "activated-ability-stack" || scenario === "triggered-ability-stack") return missingRouteFamilies().length === 0;
  if (scenario === "choose-mana" || scenario === "mana-color-choice") return missingRouteFamilies().length === 0;
  if (scenario === "commander-gauntlet") return commanderGauntletMissingSteps().length === 0;
  return false;
}

function promptModeResolvedFromSnapshot(snapshot: SmokeSnapshot) {
  return humanZone(snapshot, "battlefield").some((entry) => {
    const name = entry.card?.name ?? "";
    const oracleText = entry.card?.oracleText ?? "";
    return /lavabrink venturer/i.test(name) && /chosen mode:/i.test(oracleText);
  });
}

function isManaOrPaymentPrompt(snapshot: SmokeSnapshot) {
  const prompt = snapshot.promptEnvelopeV2;
  if (!prompt) return false;
  const expected = `${prompt.responseCommand?.type ?? ""} ${prompt.responseKind ?? ""} ${prompt.method ?? ""} ${prompt.message ?? ""}`.toLowerCase();
  return expected.includes("mana") || expected.includes("pay") || expected.includes("cost");
}

function isDamageAssignmentPromptSnapshot(snapshot: SmokeSnapshot) {
  const prompt = snapshot.promptEnvelopeV2;
  if (!prompt) return false;
  const text = `${snapshot.promptText ?? ""} ${prompt.method ?? ""} ${prompt.responseKind ?? ""} ${prompt.responseCommand?.type ?? ""} ${prompt.message ?? ""}`.toLowerCase();
  const combatDamageMultiAmount = damageAssignmentScenario
    && snapshot.phase === "combat"
    && snapshot.step === "combat-damage"
    && prompt.method === "GAME_GET_MULTI_AMOUNT"
    && prompt.responseCommand?.type === "choose_multi_amount"
    && (prompt.multiAmounts?.length ?? 0) > 1;
  return text.includes("assign damage to")
    || text.includes("assign its combat damage")
    || text.includes("assign combat damage")
    || text.includes("combat damage divided")
    || combatDamageMultiAmount;
}

function isDamageAssignmentPromptAction(action: SmokeAction) {
  const text = `${action.type ?? ""} ${action.label ?? ""} ${action.responseKind ?? ""} ${action.commandTemplate?.type ?? ""}`.toLowerCase();
  return (action.type === "answer_yes_no" || action.type === "choose_amount" || action.type === "choose_multi_amount")
    && (text.includes("assign damage") || text.includes("combat damage") || damageAssignmentPromptSeen);
}

function isGameOverSnapshot(snapshot: SmokeSnapshot) {
  const prompt = snapshot.promptEnvelopeV2;
  if (!prompt) return false;
  return prompt.method === "GAME_OVER"
    || prompt.responseKind === "game_over"
    || prompt.responseCommand?.type === "game_over";
}

function formatActions(snapshot: SmokeSnapshot) {
  return snapshot.legalActions?.map((action) => `${action.type}:${action.label ?? action.id}`).join(", ") || "none";
}

function looksLikeManaAction(action: SmokeAction) {
  const text = `${action.label ?? ""} ${action.cardName ?? ""} ${(action.producedMana ?? []).join(" ")}`.toLowerCase();
  return action.type === "make_mana" || text.includes("add {") || text.includes("mana") || (action.producedMana?.length ?? 0) > 0;
}

function smokeDebug(label: string, snapshot: SmokeSnapshot) {
  return `${label}: ${JSON.stringify({
    id: snapshot.id,
    source: snapshot.source,
    bridgeRevision: snapshot.bridgeRevision,
    xmageCycle: snapshot.xmageCycle,
    pendingStatus: snapshot.pendingStatus,
    phase: snapshot.phase,
    step: snapshot.step,
    turn: snapshot.turn,
    promptText: snapshot.promptText,
    priorityPlayerId: snapshot.priorityPlayerId,
    waitingOnPlayerId: snapshot.waitingOnPlayerId,
    humanManaPool: humanPlayer(snapshot)?.manaPool ?? {},
    humanBattlefield: humanZone(snapshot, "battlefield").map((entry) => ({
      name: entry.card?.name,
      tapped: entry.tapped,
      instanceId: entry.instanceId,
      oracleText: entry.card?.oracleText
    })),
    humanCommand: humanZone(snapshot, "command").map((entry) => ({
      name: entry.card?.name,
      oracleText: entry.card?.oracleText
    })),
    aiCommand: snapshot.players?.find((player) => player.playerId === aiPlayerId)?.zones?.command?.map((entry) => ({
      name: entry.card?.name,
      oracleText: entry.card?.oracleText
    })),
    humanHand: humanZone(snapshot, "hand").map((entry) => entry.card?.name).slice(0, 10),
    promptEnvelopeV2: snapshot.promptEnvelopeV2,
    legalActions: (snapshot.legalActions ?? []).map((action) => ({
      id: action.id,
      type: action.type,
      label: action.label,
      cardInstanceId: action.cardInstanceId,
      sourceInstanceId: action.sourceInstanceId,
      abilityId: action.abilityId,
      manaType: action.manaType,
      responseKind: action.responseKind,
      commandTemplate: action.commandTemplate
    })).slice(0, 16)
  }, null, 2)}`;
}

type SmokeSnapshot = {
  id: string;
  source?: string;
  bridgeRevision?: number;
  xmageCycle?: number;
  phase?: string;
  step?: string;
  turn?: number;
  promptText?: string;
  pendingStatus?: string;
  log?: Array<{ id?: string; message?: string }>;
  staleActionRecovered?: boolean;
  activePlayerId?: string;
  priorityPlayerId?: string;
  waitingOnPlayerId?: string;
  promptEnvelopeV2?: {
    method?: string;
    responseKind?: string;
    responseCommand?: { type?: string };
    minChoices?: number;
    maxChoices?: number;
    totalMin?: number;
    totalMax?: number;
    multiAmounts?: SmokePromptMultiAmount[];
    message?: string;
    id?: string;
    messageId?: number;
  };
  xmage?: { combat?: unknown; stack?: unknown[] };
  players?: SmokePlayer[];
  legalActions?: SmokeAction[];
  fixtureHarness?: {
    enabled?: boolean;
    fixtureName?: string;
    schemaVersion?: number;
    directStateSeeded?: boolean;
    fallback?: string;
    reason?: string;
    productionDisabled?: boolean;
    setupMethod?: string;
    source?: string;
    gameId?: string | null;
    bridgeRevision?: number | null;
    xmageCycle?: number | null;
    seededZones?: string[];
    blockedReason?: string;
    classProcessBoundary?: string;
    nextImplementationStep?: string;
    expectedRouteCoverage?: string[];
    expectedRoutes?: string[];
  };
};

type SmokePlayer = {
  playerId: string;
  life?: number;
  manaPool?: Record<string, number>;
  commanderTax?: number;
  commanderDamage?: Record<string, number>;
  zones?: Record<string, Array<{ card?: { name?: string; oracleText?: string; typeLine?: string }; tapped?: boolean; instanceId?: string }>>;
};

type SmokeAction = {
  id?: string;
  type: string;
  playerId?: string;
  label?: string;
  promptId?: string;
  messageId?: number;
  cardInstanceId?: string;
  cardName?: string;
  typeLine?: string;
  isBasicLand?: boolean;
  sourceInstanceId?: string;
  sourceZone?: string;
  abilityId?: string;
  commandTemplate?: SmokeCommandTemplate;
  responseKind?: string;
  choiceIds?: string[];
  targetIds?: string[];
  validTargetIds?: string[];
  cardInstanceIds?: string[];
  validCardInstanceIds?: string[];
  modeIds?: string[];
  playerIds?: string[];
  validPlayerIds?: string[];
  manaType?: string;
  manaTypes?: string[];
  producedMana?: string[];
  orderedIds?: string[];
  confirmed?: boolean;
  pay?: boolean;
  amount?: number;
  amounts?: number[];
  multiAmounts?: SmokePromptMultiAmount[];
  pile?: number;
  useCommandZone?: boolean;
  attackers?: Array<{ attackerId: string; defenderId: string }>;
  blockers?: Array<{ blockerId: string; attackerId: string }>;
};

type SmokeCommandTemplate = {
  type?: string;
  playerId?: string;
  promptId?: string;
  messageId?: number;
  cardInstanceId?: string;
  sourceInstanceId?: string;
  sourceZone?: string;
  abilityId?: string;
  choiceIds?: string[];
  targetIds?: string[];
  cardInstanceIds?: string[];
  modeIds?: string[];
  playerIds?: string[];
  manaType?: string;
  manaTypes?: string[];
  producedMana?: string[];
  orderedIds?: string[];
  confirmed?: boolean;
  pay?: boolean;
  amount?: number;
  amounts?: number[];
  multiAmounts?: SmokePromptMultiAmount[];
  pile?: number;
  useCommandZone?: boolean;
  attackers?: Array<{ attackerId: string; defenderId: string }>;
  blockers?: Array<{ blockerId: string; attackerId: string }>;
};

type SmokePromptMultiAmount = {
  id: string;
  label: string;
  min: number;
  max: number;
  defaultValue?: number;
};

type ScenarioModule = {
  id: string;
  usesFixture: boolean;
  scenarioSet: string[];
  requiredSteps: string[];
};
