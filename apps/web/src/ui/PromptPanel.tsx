/**
 * The current decision, as the apps' prompt surfaces present it (PromptEnvelopeV2 kinds): yes/no,
 * choices, modes, amounts, piles, abilities, target lists and mana payment, plus the prompt's own
 * legal actions (pass, done, cancel, special). Board and hand taps answer the rest.
 */
import { useState } from "react";
import { EngineDisplayText } from "../core/displayText";
import { type GameCommand, type GameSnapshot, type LegalAction, pileNumber, promptKind, type ZoneCard } from "../core/models";
import { cardImageURL } from "./cardArt";

export type Send = (command: Omit<GameCommand, "gameId" | "playerId" | "promptId" | "messageId">, label: string) => void;
export type SendAction = (action: LegalAction) => void;

const CardChoice = ({ card, onClick, disabled }: { card: ZoneCard; onClick: () => void; disabled?: boolean }) => (
  <button type="button" className="choice" disabled={disabled} onClick={onClick} title={card.card.oracleText}>
    <img src={cardImageURL(card.card.name, "normal")} alt="" loading="lazy" crossOrigin="anonymous" />
    <span>{card.card.name}<br /><span className="small-print">{card.disabledReason ?? card.card.typeLine}</span></span>
  </button>
);

function Stepper({ value, min, max, onChange }: { value: number; min: number; max: number; onChange: (v: number) => void }) {
  return (
    <div className="stepper">
      <button type="button" aria-label="Less" onClick={() => onChange(Math.max(min, value - 1))}>−</button>
      <output>{value}</output>
      <button type="button" aria-label="More" onClick={() => onChange(Math.min(max, value + 1))}>+</button>
    </div>
  );
}

export function PromptPanel({ snapshot, send, sendAction, pending, waitingFor }: {
  snapshot: GameSnapshot; send: Send; sendAction: SendAction; pending: boolean; waitingFor?: string;
}) {
  const envelope = snapshot.promptEnvelopeV2;
  const [amount, setAmount] = useState<number>();
  const [amounts, setAmounts] = useState<Record<string, number>>({});
  const promptActions = (snapshot.legalActions ?? []).filter((a) => a.cardInstanceId === undefined && a.sourceInstanceId === undefined);
  if (!envelope) {
    return (
      <div className="prompt-box">
        <div className="prompt-message">{waitingFor ? <><span className="thinking" /> Waiting for {waitingFor}…</> : snapshot.gameStatus === "completed" ? "The game is over." : "Waiting for the game…"}</div>
      </div>
    );
  }
  const kind = promptKind(envelope);
  const reset = () => { setAmount(undefined); setAmounts({}); };
  const choose = (command: Parameters<Send>[0], label: string) => { reset(); send(command, label); };
  const priority = envelope.responseKind === "priority";
  const combat = envelope.method === "GAME_SELECT" && envelope.responseKind === "target";
  const player = (id: string) => snapshot.players.find((p) => p.playerId === id);
  return (
    <div className="prompt-box" aria-busy={pending}>
      <div className="prompt-message">{envelope.message || (priority ? "Your priority" : "Make a choice")}</div>
      {snapshot.manaPayment?.active && <div className="small-print">Tap glowing mana sources on the table, or pay from your pool.</div>}
      {combat && <div className="small-print">Click your creatures on the table, then Done.</div>}

      {envelope.confirmation && (
        <div className="row">
          <button type="button" className="plaque primary" disabled={pending} onClick={() => choose({ type: "answer_yes_no", confirmed: true }, envelope.confirmation?.yesLabel ?? "Yes")}>
            {envelope.confirmation.yesLabel ?? "Yes"}</button>
          <button type="button" className="plaque" disabled={pending} onClick={() => choose({ type: "answer_yes_no", confirmed: false }, envelope.confirmation?.noLabel ?? "No")}>
            {envelope.confirmation.noLabel ?? "No"}</button>
        </div>
      )}

      {envelope.manaChoices && envelope.manaChoices.length > 0 && (
        <div className="row">
          {envelope.manaChoices.map((choice) => (
            <button key={choice.id} type="button" className="plaque compact" disabled={pending}
              onClick={() => choose({ type: "play_mana", manaType: choice.manaType }, choice.label)}>
              <span className="sym" style={{ backgroundImage: `url(/tavern/mana-${choice.manaType}.webp)` }} /> ×{choice.amount}
            </button>
          ))}
        </div>
      )}

      {envelope.responseKind === "x_mana" && (
        <div className="amount-row">
          <Stepper value={amount ?? envelope.minChoices ?? 0} min={envelope.minChoices ?? 0} max={envelope.maxChoices ?? 0} onChange={setAmount} />
          <button type="button" className="plaque primary compact" disabled={pending}
            onClick={() => choose({ type: "play_x_mana", amount: amount ?? envelope.minChoices ?? 0 }, "Choose X")}>Choose X</button>
        </div>
      )}

      {kind === "amount" && (envelope.amounts && envelope.amounts.length > 0 ? (
        <div className="row">
          {envelope.amounts.map((value) => (
            <button key={value} type="button" className="plaque compact" disabled={pending} onClick={() => choose({ type: "choose_amount", amount: value }, String(value))}>{value}</button>
          ))}
        </div>
      ) : (
        <div className="amount-row">
          <input className="slot" type="number" min={envelope.minChoices} max={envelope.maxChoices} value={amount ?? envelope.minChoices ?? 0}
            onChange={(e) => setAmount(Number.parseInt(e.target.value, 10))} />
          <button type="button" className="plaque primary compact" disabled={pending}
            onClick={() => choose({ type: "choose_amount", amount: amount ?? envelope.minChoices ?? 0 }, "Choose amount")}>Choose</button>
        </div>
      ))}

      {envelope.multiAmounts && (
        <>
          {envelope.multiAmounts.map((row) => (
            <div key={row.id} className="amount-row">
              <span>{row.label}</span>
              <Stepper value={amounts[row.id] ?? row.defaultValue ?? row.min} min={row.min} max={row.max} onChange={(v) => setAmounts({ ...amounts, [row.id]: v })} />
            </div>
          ))}
          <div className="small-print">Total {envelope.totalMin}–{envelope.totalMax}</div>
          <button type="button" className="plaque primary" disabled={pending}
            onClick={() => choose({ type: "choose_multi_amount", amounts: envelope.multiAmounts!.map((row) => amounts[row.id] ?? row.defaultValue ?? row.min) }, "Assign")}>Assign</button>
        </>
      )}

      {envelope.piles && (
        <div className="row" style={{ alignItems: "flex-start" }}>
          {envelope.piles.map((pile) => (
            <div key={pile.id} style={{ flex: 1 }} className="choice-list">
              <button type="button" className="plaque compact" disabled={pending || pileNumber(pile) === undefined}
                onClick={() => choose({ type: "choose_pile", pile: pileNumber(pile) }, pile.label)}>{pile.label}</button>
              {pile.cards.map((card) => <span key={card.instanceId} className="small-print">{card.card.name}</span>)}
            </div>
          ))}
        </div>
      )}

      {envelope.abilities && (
        <div className="choice-list">
          {envelope.abilities.map((ability) => (
            <button key={ability.id} type="button" className="choice" disabled={pending} onClick={() => choose({ type: "choose_ability", abilityId: ability.id }, ability.label)}>
              {ability.sourceName && <img src={cardImageURL(ability.sourceName, "normal")} alt="" crossOrigin="anonymous" />}
              <span>{ability.label}</span>
            </button>
          ))}
        </div>
      )}

      {envelope.modes && (
        <div className="choice-list">
          {envelope.modes.map((mode) => (
            <button key={mode.id} type="button" className="choice" disabled={pending} onClick={() => choose({ type: "choose_mode", modeIds: [mode.id] }, mode.label)}>{mode.label}</button>
          ))}
        </div>
      )}

      {envelope.choices && (
        <div className="choice-list">
          {envelope.choices.map((choice) => (
            <button key={choice.id || "cancel"} type="button" className="choice" disabled={pending} onClick={() => choose({ type: "resolve_choice", choiceIds: [choice.id] }, choice.label)}>{choice.label}</button>
          ))}
        </div>
      )}

      {kind === "target" && (
        <div className="choice-list">
          {(envelope.cards ?? []).map((card) => (
            <CardChoice key={card.instanceId} card={card} disabled={pending || card.selectable === false}
              onClick={() => choose({ type: "choose_target", targetIds: [card.instanceId] }, card.card.name)} />
          ))}
          {(envelope.targets ?? []).map((target) => (
            <button key={target.id} type="button" className="choice" disabled={pending} onClick={() => choose({ type: "choose_target", targetIds: [target.id] }, target.label)}>
              {player(target.id) ? `${target.label} (player)` : target.label}
            </button>
          ))}
        </div>
      )}

      {promptActions.length > 0 && (
        <div className="row">
          {promptActions.map((action) => (
            <button key={action.id} type="button" disabled={pending}
              className={`plaque ${action.type === "pass_priority" || (action.type === "answer_yes_no" && action.confirmed) ? "primary" : ""}`}
              onClick={() => { reset(); sendAction(action); }}>
              {action.type === "pass_priority" ? (snapshot.xmage?.stack.length ? "Resolve" : "Pass") : EngineDisplayText.label(action.label)}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
