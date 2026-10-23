/**
 * The Custom Table as Arena's event page (iOS OnDeviceRootView.setupContent): your seat on one glass plate (your open
 * deck box, its bracket, your name written on the plate, Change deck) and the table on the other (who plays, the AI seats
 * as deck boxes with × and a "+" seat, the AI's skill and who goes first), with the status and Start on a strip below.
 * An online table joins a friend's with their code (the phones host; a browser can't host yet).
 */
import { useEffect, useRef, useState } from "react";
import { CommanderBracket } from "../../core/brackets";
import { gameAudio } from "../audio";
import { boxGeometry, DeckBox, type DeckBoxModel, NewDeckBox } from "./DeckBox";
import { BackChevron, Caps, Emblem, Pill, PlayButton, Slider } from "./kit";

export interface AIDeckChoice { id: string; name: string; commander?: string; colors: string[]; bracket: number }
export interface AIDeckGroup { title: string; decks: AIDeckChoice[] }

export interface CustomTableModel {
  deck?: DeckBoxModel;
  bracket?: CommanderBracket;
  name: string;
  setName: (name: string) => void;
  validName: boolean;
  /** Your profile's player name: written on the plate, not edited here (setupNamePlate). */
  nameLocked?: boolean;
  playerMode: "ai" | "online";
  setPlayerMode: (mode: "ai" | "online") => void;
  seats: string[];
  setSeats: (seats: string[]) => void;
  aiGroups: AIDeckGroup[];
  aiSkill: number;
  setAISkill: (skill: number) => void;
  starting: "roll" | "choose";
  setStarting: (mode: "roll" | "choose") => void;
  joinCode: string;
  setJoinCode: (code: string) => void;
  status?: string;
  mayStart: boolean;
  start: () => void;
  join: () => void;
  changeDeck: () => void;
  back: () => void;
  explainBracket: () => void;
}

export function CustomTable({ model }: { model: CustomTableModel }) {
  const online = model.playerMode === "online";
  return (
    <div className="mcustom">
      <header className="mcustomhead">
        <BackChevron onBack={model.back} />
        <h1>Custom Table</h1>
      </header>
      <div className="mcustomplates">
        <section className="mcard mcustomseat mscroll">
          {model.deck && (
            <div style={{ paddingTop: boxGeometry(124).rise * 1.6 + 4 }}><DeckBox deck={model.deck} selected width={124} /></div>
          )}
          <div className="mcustomdetails">
            {model.bracket !== undefined && (
              <button type="button" className="mbracketlink" data-id="play.deck.bracket" onClick={model.explainBracket}>
                {CommanderBracket.title(model.bracket)} <i>i</i>
              </button>
            )}
            <label className={`mnameplate ${model.nameLocked ? "locked" : ""}`}>
              <input value={model.name} maxLength={24} placeholder="Player name" spellCheck={false} autoComplete="nickname" readOnly={model.nameLocked}
                onChange={(e) => model.setName(e.target.value)} data-id="ondevice.playerName" aria-label="Player name" />
              {!model.nameLocked && <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20l1-4L16 5l3 3L8 19zM14.5 6.5l3 3" /></svg>}
            </label>
            {!model.validName && !model.nameLocked && <p className="mnote">Choose a name with 1–24 characters.</p>}
            <Pill id="setup.changeDeck" onClick={model.changeDeck}>Change deck</Pill>
          </div>
        </section>
        <section className="mcard mcustomtable mscroll">
          <div className="mcustomcols">
            <div className="mcustomcol">
              <Caps text="Players" />
              <div className="mtiles">
                <SetupTile title="AI" symbol="ai" on={!online} id="setup.mode.ai" onClick={() => model.setPlayerMode("ai")} />
                <SetupTile title="Online" symbol="online" on={online} id="setup.mode.online" onClick={() => model.setPlayerMode("online")} />
              </div>
              {!online && <>
                <hr />
                <Caps text="Seats" />
                <Seats model={model} />
              </>}
              {online && <JoinTable model={model} />}
            </div>
            {!online && (
              <div className="mcustomcol narrow">
                <div className="mskillhead"><Caps text="AI skill" /><b>{model.aiSkill}</b></div>
                <Slider label="AI skill" value={model.aiSkill} min={1} max={10} step={1} valueText={`AI skill: ${model.aiSkill}`}
                  onChange={(v) => model.setAISkill(Math.min(10, Math.max(1, Math.round(v))))} />
                <hr />
                <Caps text="Who goes first" />
                <div className="mtiles">
                  <SetupTile title="Choose" symbol="choose" on={model.starting === "choose"} id="setup.first.choose" onClick={() => model.setStarting("choose")} />
                  <SetupTile title="Roll D20" symbol="dice" on={model.starting === "roll"} id="setup.first.roll" onClick={() => model.setStarting("roll")} />
                </div>
              </div>
            )}
          </div>
        </section>
      </div>
      <footer className="mcustomstrip">
        <span className="grow">{model.status}</span>
        {!online && <div className="mcustomstart"><PlayButton size={19} id="setup.start" disabled={!model.mayStart} onClick={model.start}>Start</PlayButton></div>}
      </footer>
    </div>
  );
}

function SetupTile({ title, symbol, on, onClick, id }: { title: string; symbol: string; on: boolean; onClick: () => void; id: string }) {
  return (
    <button type="button" className={`msetuptile ${on ? "on" : ""}`} aria-pressed={on} data-id={id} onClick={() => { gameAudio.play("ui-tap"); onClick(); }}>
      <Emblem name={symbol} size={20} lit={on} /><span>{title}</span>
    </button>
  );
}

/** The AI seats as deck boxes: click one for its deck, its × empties it, and a "+" seat adds an opponent (up to three). */
function Seats({ model }: { model: CustomTableModel }) {
  const [picking, setPicking] = useState<number>();
  const all = model.aiGroups.flatMap((g) => g.decks);
  return (
    <div className="mseats">
      {model.seats.map((id, index) => {
        const deck = all.find((d) => d.id === id);
        return (
          <div key={index} className="mseat">
            <button type="button" className="mseatbox" data-id={`ondevice.aiDeck.${index + 1}`} aria-label={`AI ${index + 1} deck, ${deck?.name ?? "Choose"}`}
              onClick={() => { gameAudio.play("ui-open"); setPicking(picking === index ? undefined : index); }}>
              <DeckBox width={70} deck={{ id: deck?.id ?? `seat-${index}`, name: deck?.name ?? "Choose a deck", commander: deck?.commander, colors: deck?.colors ?? [],
                subtitle: deck ? CommanderBracket.name(deck.bracket as CommanderBracket) : "" }} />
            </button>
            {model.seats.length > 1 && (
              <button type="button" className="mseatremove" aria-label={`Remove AI ${index + 1}`} data-id={`ondevice.aiSeat.remove.${index + 1}`}
                onClick={() => { gameAudio.play("ui-back"); model.setSeats(model.seats.filter((_, i) => i !== index)); setPicking(undefined); }}>✕</button>
            )}
            {picking === index && (
              <DeckMenu groups={model.aiGroups} chosen={id} close={() => setPicking(undefined)}
                pick={(deckID) => { const next = [...model.seats]; next[index] = deckID; model.setSeats(next); setPicking(undefined); }} />
            )}
          </div>
        );
      })}
      {model.seats.length < 3 && (
        <button type="button" className="mseatadd" aria-label="Add an AI opponent" data-id="ondevice.aiSeat.add"
          onClick={() => { gameAudio.play("ui-tap"); model.setSeats([...model.seats, model.seats[model.seats.length - 1] ?? all[0]?.id ?? ""]); }}>
          <NewDeckBox width={70} />
        </button>
      )}
    </div>
  );
}

/** A seat's deck list in a glass pop-over, by shelf, the chosen one ticked. */
function DeckMenu({ groups, chosen, pick, close }: { groups: AIDeckGroup[]; chosen: string; pick: (id: string) => void; close: () => void }) {
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => {
    list.current?.querySelector(".on")?.scrollIntoView({ block: "center" });
    const outside = (e: PointerEvent) => { if (!list.current?.parentElement?.contains(e.target as Node)) close(); };
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); close(); } };
    window.addEventListener("pointerdown", outside);
    window.addEventListener("keydown", key, true);
    return () => { window.removeEventListener("pointerdown", outside); window.removeEventListener("keydown", key, true); };
  }, [close]);
  return (
    <div ref={list} className="mpopover glass mseatmenu" role="listbox">
      {groups.map((group) => (
        <div key={group.title}>
          <Caps text={group.title} size={9.5} className="mhead" />
          {group.decks.map((deck) => (
            <button key={deck.id} type="button" role="option" aria-selected={deck.id === chosen} className={deck.id === chosen ? "on" : ""}
              onClick={() => { gameAudio.play("ui-tap"); pick(deck.id); }}><i />{deck.name}{deck.commander ? ` · ${deck.commander}` : ""}</button>
          ))}
        </div>
      ))}
    </div>
  );
}

/** An online table: the six-letter code from the host's phone, and Join. */
function JoinTable({ model }: { model: CustomTableModel }) {
  const valid = /^[A-Z0-9]{6}$/.test(model.joinCode);
  return (
    <div className="mjoin">
      <hr />
      <Caps text="Table code" />
      <input className="mcode" value={model.joinCode} maxLength={6} placeholder="ABC234" spellCheck={false} aria-label="Table code"
        onChange={(e) => model.setJoinCode(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ""))}
        onKeyDown={(e) => { if (e.key === "Enter" && valid && model.validName) model.join(); }} />
      <div className="mjoinplay"><PlayButton size={18} id="setup.join" disabled={!valid || !model.validName} onClick={model.join}>Join Table</PlayButton></div>
    </div>
  );
}
