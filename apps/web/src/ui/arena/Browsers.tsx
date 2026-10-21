/**
 * Arena browsers (docs/ARENA_STYLE.md): a decision that isn't answered by clicking the table takes the whole table,
 * dimmed, with a serif title, one line of instructions, the cards or rows in the middle and plaques at the foot.
 * They send exactly the commands the old prompt panel sent, so the engine never changes for a look.
 */
import { useState } from "react";
import { EngineDisplayText } from "../../core/displayText";
import { type GameCommand, type GameSnapshot, type LegalAction, pileNumber, promptKind, type PromptEnvelopeV2, type ZoneCard } from "../../core/models";
import { cardImageURL } from "../cardArt";
import { AbilityCard } from "./AbilityCard";

export type Send = (command: Omit<GameCommand, "gameId" | "playerId" | "promptId" | "messageId">, label: string) => void;
export type SendAction = (action: LegalAction) => void;
export type BrowserKind = "mulligan" | "question" | "amount" | "split" | "piles" | "abilities" | "modes" | "choices" | "cards" | "players";

/** Which browser a prompt needs, or none when it is answered on the table (priority, combat, payment, table targets). */
export function browserKind(envelope: PromptEnvelopeV2 | undefined, onTable: (id: string) => boolean): BrowserKind | undefined {
  if (!envelope) return undefined;
  if (envelope.confirmation) return /mulligan/i.test(envelope.message) ? "mulligan" : "question";
  if (envelope.responseKind === "priority") return undefined;
  if (envelope.method === "GAME_SELECT" && envelope.responseKind === "target") return undefined;
  if (envelope.responseKind === "x_mana") return "amount";
  const kind = promptKind(envelope);
  if (kind === "payment") return undefined;
  if (envelope.multiAmounts) return "split";
  if (envelope.piles) return "piles";
  if (envelope.abilities) return "abilities";
  if (envelope.modes) return "modes";
  if (envelope.choices) return "choices";
  if (kind === "amount") return "amount";
  if (kind === "target") {
    const targets = envelope.targets ?? [];
    if (/starting player/i.test(envelope.message)) return "players";
    const ids = [...(envelope.cards ?? []).map((c) => c.instanceId), ...targets.map((t) => t.id), ...(envelope.targetIds ?? [])];
    return ids.length > 0 && ids.every(onTable) ? undefined : "cards";
  }
  return undefined;
}

/** "Choose target creature or player" → a title and an instruction line, cleaned of XMage's ids and markup. */
function heading(envelope: PromptEnvelopeV2, kind: BrowserKind): { title: string; line?: string } {
  const text = EngineDisplayText.text(envelope.message).replace(/\s*\[[0-9a-f]{3,}\]/gi, "").trim();
  const [first, ...rest] = text.split("\n").map((s) => s.trim()).filter(Boolean);
  const fallback: Record<BrowserKind, string> = {
    mulligan: "Mulligan?", question: "Decide", amount: "Choose a number", split: "Divide it up", piles: "Choose a pile",
    abilities: "Choose an ability", modes: "Choose a mode", choices: "Choose one", cards: "Choose", players: "Choose a player",
  };
  if (!first) return { title: fallback[kind] };
  if (first.length <= 48) return { title: first, line: rest.join(" ") || undefined };
  return { title: fallback[kind], line: [first, ...rest].join(" ") };
}

const zoneName = (snapshot: GameSnapshot, card: ZoneCard) => {
  for (const player of snapshot.players) {
    for (const [zone, cards] of Object.entries(player.zones)) {
      if (Array.isArray(cards) && cards.some((c: ZoneCard) => c.instanceId === card.instanceId)) {
        const whose = player.playerId === snapshot.viewerPlayerId ? "Your" : `${player.displayName ?? "Their"}’s`;
        return `${whose} ${zone === "battlefield" ? "table" : zone}`;
      }
    }
  }
  return undefined;
};

function Stepper({ value, min, max, onChange }: { value: number; min: number; max: number; onChange: (v: number) => void }) {
  return (
    <div className="aamount">
      <button type="button" aria-label="Five less" onClick={() => onChange(Math.max(min, value - 5))}>−5</button>
      <button type="button" aria-label="Less" onClick={() => onChange(Math.max(min, value - 1))}>−</button>
      <output>{value}</output>
      <button type="button" aria-label="More" onClick={() => onChange(Math.min(max, value + 1))}>+</button>
      <button type="button" aria-label="Five more" onClick={() => onChange(Math.min(max, value + 5))}>+5</button>
    </div>
  );
}

export function Browser({ kind, snapshot, envelope, send, sendAction, pending, onHide }: {
  kind: Exclude<BrowserKind, "mulligan">; snapshot: GameSnapshot; envelope: PromptEnvelopeV2; send: Send; sendAction: SendAction; pending: boolean; onHide: () => void;
}) {
  const [amount, setAmount] = useState<number>();
  const [split, setSplit] = useState<Record<string, number>>({});
  const promptActions = (snapshot.legalActions ?? []).filter((a) => a.cardInstanceId === undefined && a.sourceInstanceId === undefined);
  const ordering = kind === "abilities" && /trigger|goes to the stack first/i.test(envelope.message);
  const { title, line } = ordering
    ? { title: "Order your triggers", line: "Choose the one that goes on the stack first: it resolves last." }
    : heading(envelope, kind);
  const top = snapshot.xmage?.stack[0];
  const answers = promptActions.length > 0 && (
    <div className="answers">
      {promptActions.map((action) => (
        <button key={action.id} type="button" disabled={pending} onClick={() => sendAction(action)}
          className={`aplaque ${action.type === "answer_yes_no" && action.confirmed ? "ember" : "leather"}`}>{EngineDisplayText.label(action.label)}</button>
      ))}
    </div>
  );

  if (kind === "question") {
    const confirmation = envelope.confirmation!;
    return (
      <div className="aoverlay question">
        <div className="aquestion glass">
          {top && <img className="source" src={cardImageURL(top.sourceCard?.card.name ?? top.sourceName ?? top.name, "normal")} alt={top.name} crossOrigin="anonymous" />}
          <h2>{title}</h2>
          {line && <p>{line}</p>}
          <div className="answers" style={{ display: "flex", gap: 12 }}>
            <button type="button" className="aplaque ember" disabled={pending} onClick={() => send({ type: "answer_yes_no", confirmed: true }, confirmation.yesLabel ?? "Yes")}>
              {confirmation.yesLabel ?? "Yes"}</button>
            <button type="button" className="aplaque leather" disabled={pending} onClick={() => send({ type: "answer_yes_no", confirmed: false }, confirmation.noLabel ?? "No")}>
              {confirmation.noLabel ?? "No"}</button>
          </div>
        </div>
      </div>
    );
  }

  let body: React.ReactNode = null;
  let footer: React.ReactNode = answers;
  switch (kind) {
    case "amount": {
      const x = envelope.responseKind === "x_mana";
      const min = envelope.minChoices ?? 0;
      const max = envelope.maxChoices ?? Math.max(min, 99);
      const value = amount ?? min;
      body = envelope.amounts && envelope.amounts.length > 0 && !x ? (
        <div className="answers">{envelope.amounts.map((n) => (
          <button key={n} type="button" className="aplaque leather" disabled={pending} onClick={() => send({ type: "choose_amount", amount: n }, String(n))}>{n}</button>
        ))}</div>
      ) : <Stepper value={value} min={min} max={max} onChange={setAmount} />;
      footer = (
        <div className="answers">
          {!(envelope.amounts && envelope.amounts.length > 0 && !x) && (
            <button type="button" className="aplaque ember" disabled={pending}
              onClick={() => send(x ? { type: "play_x_mana", amount: value } : { type: "choose_amount", amount: value }, x ? `X = ${value}` : String(value))}>
              {x ? `Pay X = ${value}` : `Choose ${value}`}</button>
          )}
          {answers}
        </div>
      );
      break;
    }
    case "split": {
      const rows = envelope.multiAmounts!;
      const values = rows.map((row) => split[row.id] ?? row.defaultValue ?? row.min);
      const total = values.reduce((a, b) => a + b, 0);
      const legal = (envelope.totalMin === undefined || total >= envelope.totalMin) && (envelope.totalMax === undefined || total <= envelope.totalMax);
      body = (
        <div className="rows">
          {rows.map((row, i) => (
            <div key={row.id} className="arow" style={{ justifyContent: "space-between" }}>
              <span>{EngineDisplayText.label(row.label)}</span>
              <Stepper value={values[i]} min={row.min} max={row.max} onChange={(v) => setSplit({ ...split, [row.id]: v })} />
            </div>
          ))}
        </div>
      );
      footer = (
        <div className="answers">
          <button type="button" className="aplaque ember" disabled={pending || !legal} onClick={() => send({ type: "choose_multi_amount", amounts: values }, "Assign")}>
            Assign{envelope.totalMax !== undefined ? <small>{total} of {envelope.totalMax}</small> : null}</button>
          {answers}
        </div>
      );
      break;
    }
    case "piles":
      body = (
        <div className="cards" style={{ gap: 36 }}>
          {envelope.piles!.map((pile) => (
            <div key={pile.id} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10 }}>
              <div style={{ display: "flex", gap: 6 }}>{pile.cards.map((card) => (
                <img key={card.instanceId} src={cardImageURL(card.card.name, "normal")} alt={card.card.name} crossOrigin="anonymous" style={{ width: 92, borderRadius: 7 }} />
              ))}</div>
              <button type="button" className="aplaque ember" disabled={pending || pileNumber(pile) === undefined} style={{ position: "relative", minWidth: 150, height: 36 }}
                onClick={() => send({ type: "choose_pile", pile: pileNumber(pile) }, pile.label)}>{pile.label}</button>
            </div>
          ))}
        </div>
      );
      break;
    case "abilities":
      // The reference's ability browser: the abilities as Arena ability cards in a row; a click picks one (to order
      // triggers, XMage asks for the one that resolves first, then the next).
      body = (
        <div className="cards">
          {envelope.abilities!.map((ability) => (
            <button key={ability.id} type="button" className="ability-pick" disabled={pending}
              onClick={() => send({ type: "choose_ability", abilityId: ability.id }, ability.label)}>
              <AbilityCard source={ability.sourceCard} name={ability.sourceName} text={ability.rulesText ?? ability.label} width={160} />
            </button>
          ))}
        </div>
      );
      break;
    case "modes":
    case "choices": {
      const rows = kind === "modes" ? envelope.modes! : envelope.choices!;
      body = (
        <div className="rows">
          {rows.map((row, index) => (
            <button key={row.id || `cancel-${index}`} type="button" className="arow" disabled={pending}
              onClick={() => send(kind === "modes" ? { type: "choose_mode", modeIds: [row.id] } : { type: "resolve_choice", choiceIds: [row.id] }, row.label)}>
              {kind === "modes" && <span className="sub" style={{ minWidth: 54, color: "#fad584" }}>Mode {index + 1}</span>}
              <span>{EngineDisplayText.label(row.label)}</span>
            </button>
          ))}
        </div>
      );
      break;
    }
    case "players":
      body = (
        <div className="answers" style={{ gap: 18 }}>
          {(envelope.targets ?? []).map((target) => {
            const player = snapshot.players.find((p) => p.playerId === target.id);
            const you = target.id === snapshot.viewerPlayerId;
            return (
              <button key={target.id} type="button" className={`aplaque ${you ? "ember" : "leather"}`} disabled={pending} style={{ position: "relative", minWidth: 170, height: 40 }}
                onClick={() => send({ type: "choose_target", targetIds: [target.id] }, target.label)}>{you ? "You" : player?.displayName ?? target.label}</button>
            );
          })}
        </div>
      );
      break;
    case "cards": {
      const cards = envelope.cards ?? [];
      const listed = new Set(cards.map((c) => c.instanceId));
      const others = (envelope.targets ?? []).filter((t) => !listed.has(t.id));
      body = (
        <>
          <div className="cards">
            {cards.map((card) => (
              <button key={card.instanceId} type="button" className="bcard" disabled={pending || card.selectable === false} title={card.disabledReason ?? card.card.oracleText}
                onClick={() => send({ type: "choose_target", targetIds: [card.instanceId] }, card.card.name)}>
                <img src={cardImageURL(card.card.name, "normal")} alt={card.card.name} crossOrigin="anonymous" />
                <span className="zone">{zoneName(snapshot, card) ?? ""}</span>
              </button>
            ))}
          </div>
          {others.length > 0 && (
            <div className="rows">
              {others.map((target) => (
                <button key={target.id} type="button" className="arow" disabled={pending} onClick={() => send({ type: "choose_target", targetIds: [target.id] }, target.label)}>
                  {EngineDisplayText.label(target.label)}</button>
              ))}
            </div>
          )}
        </>
      );
      break;
    }
  }
  return (
    <div className="aoverlay dim">
      <div className="abrowser">
        <button type="button" className="view" onClick={onHide}>View battlefield</button>
        <h2>{title}</h2>
        {line && <p className="instr">{line}</p>}
        {body}
        {footer}
      </div>
    </div>
  );
}
