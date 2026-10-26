/**
 * How to Play (iOS HowToPlay.swift's two tutorials) as a glass panel: the chooser, then one page at a time with its
 * progress, Back and Next. The words follow the phones' (tutorial-cases.json) with the desktop's controls in place of
 * touch (click for tap, right-click or hold for a long press, Space to pass); pages for what a browser can't do yet
 * (resuming a game, Deck Studio) say what it does instead.
 */
import { useEffect, useState } from "react";
import { gameAudio } from "../audio";
import { DeckArt } from "./DeckBox";
import { Btn, CloseButton, BackChevron } from "./kit";

interface LearnPage { id: string; title: string; body: string }
/** `art`: the card whose art fills the tutorial's tile, `colors` its glass until the art loads. */
interface Tutorial { id: string; title: string; subtitle: string; art: string; colors: string[]; pages: LearnPage[] }

export const TUTORIALS: Tutorial[] = [
  { id: "table", title: "How MagicMobile works", subtitle: "Eleven short pages on the table and its controls.", art: "Teferi, Temporal Archmage", colors: ["U"], pages: [
    { id: "welcome", title: "Welcome to the tavern", body: "Play Commander against AI opponents or your friends, right in your browser. The XMage rules engine runs on this computer and handles every rule for you." },
    { id: "decks", title: "Choose your deck", body: "Click Decks, or Play, to see every deck as a box. Click a box to choose it: it opens and its commander rises out." },
    { id: "start", title: "Start a game", body: "Click Play and pick Quick, Ranked or Custom. A Custom Table takes one to three AI opponents and their skill. Under Who goes first, choose the starting player or roll a D20: the highest roll starts. Then keep your opening hand or take a mulligan." },
    { id: "board", title: "Know the table", body: "Your hand rests along the bottom, with your battlefield above it. Opponents sit across the table: click a medallion for that player's zones, counters, poison and commander damage. The phase strip shows the turn and the current step." },
    { id: "casting", title: "Cast a spell", body: "Drag a card from your hand onto the table to play it, or click it. When a spell needs mana, Auto Pay taps your lands, or click them yourself. The spell rises to the centre of the table while it waits on the stack." },
    { id: "glow", title: "Follow the glow", body: "A cyan glow means a card can be played or chosen; a pale glow marks something you can target, even when it's tapped. Tapped permanents turn grey until they untap. Your commander's medallion glows whenever you can cast it." },
    { id: "priority", title: "Pass with Space", body: "When you're done, press Space or click the corner plaque to pass priority and let this step continue. With a spell on the stack, respond with an instant or ability, or pass to let it resolve. Hold Space for full control." },
    { id: "combat", title: "Attack and block", body: "To attack, click each creature you want to send, or All Attack, then confirm with Enter or the plaque. To block, click your creature, then the attacker it blocks. Take Back lets you change your mind before you confirm." },
    { id: "piles", title: "Big boards", body: "Once you have eight or more identical tokens, they stack into one pile with a count. Click the pile to pick the next token, or spread them out." },
    { id: "reading", title: "Read a card", body: "Point at any card to read it, and right-click it to see it up close with its full rules text. Open the game log to look back at every play." },
    { id: "friends", title: "Play with friends", body: "On a Custom Table, choose Online and enter a friend's table code to join the table their phone is hosting. Online works with iPhone and Android." },
  ] },
  { id: "commander", title: "Commander basics", subtitle: "Nine pages on the rules of the format.", art: "The Ur-Dragon", colors: ["W", "U", "B", "R", "G"], pages: [
    { id: "format", title: "The format", body: "Commander is Magic for a table of friends: usually three or four players, each with a 100-card deck led by a legendary creature. Every card but basic lands is a single copy, and everyone starts at 40 life." },
    { id: "commander", title: "Your commander", body: "Your commander starts in the command zone, and you can cast it from there whenever you could cast a creature. If it would leave the battlefield, you may send it back to the command zone instead. Each time you cast it again, it costs two more mana: the commander tax." },
    { id: "colors", title: "Colour identity", body: "Your commander's colours decide your deck. Every card may only use mana symbols that appear on your commander, in its cost or its rules text. A colourless commander means a deck of colourless cards." },
    { id: "turn", title: "A turn", body: "Each turn untaps your permanents, then you draw a card. In your main phases you may play one land and cast your spells, and combat comes between them. Then the turn passes to the player on your left." },
    { id: "mana", title: "Mana and costs", body: "Lands tap for mana, and a card's cost sits in its corner. Creatures, sorceries and other permanents are cast in your main phase with nothing on the stack. Instants and abilities can be used whenever you have priority, even on another player's turn." },
    { id: "stack", title: "The stack", body: "Spells and abilities don't happen at once: they wait on the stack, and everyone may respond. The last thing added resolves first. When every player passes in a row, the top of the stack resolves." },
    { id: "combat", title: "Combat", body: "Attacking creatures tap, and each one attacks a player or a planeswalker. The defender chooses blockers, and an unblocked creature deals its damage to the player. Flying creatures can only be blocked by flying or reach, and trample pushes extra damage through a blocker." },
    { id: "permanents", title: "Permanents", body: "Creatures, artifacts, enchantments, planeswalkers and lands stay on the battlefield. A creature can't attack or tap for an ability on the turn it arrives unless it has haste. Right-click any card to read its keywords and rules in full." },
    { id: "winning", title: "Winning", body: "A player loses at 0 life, with 10 poison counters, or when they must draw from an empty library. Taking 21 combat damage from one commander over the game loses too. The last player at the table wins." },
  ] },
];

export function LearnPanel({ onClose }: { onClose: () => void }) {
  const [tutorial, setTutorial] = useState<Tutorial>();
  const [index, setIndex] = useState(0);
  const page = tutorial?.pages[index];
  const step = (delta: number) => {
    if (!tutorial) return;
    const next = index + delta;
    if (next < 0) { setTutorial(undefined); return; }
    if (next >= tutorial.pages.length) { onClose(); return; }
    gameAudio.play("page-flip");
    setIndex(next);
  };
  useEffect(() => {
    if (!tutorial) return;
    const key = (e: KeyboardEvent) => {
      if (e.key === "ArrowRight") { e.preventDefault(); step(1); }
      if (e.key === "ArrowLeft") { e.preventDefault(); step(-1); }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  });
  return (
    <div className="mlearn">
      <header className="mpanelhead centered">
        {tutorial ? <BackChevron onBack={() => setTutorial(undefined)} /> : <span className="mspacer" />}
        <h2>{tutorial?.title ?? "How to play"}</h2>
        <CloseButton onClose={onClose} />
      </header>
      {!tutorial || !page ? (
        <div className="mlearnchooser">
          {TUTORIALS.map((t) => (
            // Arena's Learn tile (HowToPlayChooser.upright): the art fills it, framed on its upper part, the title and plaque on a
            // shade along its foot. What it teaches is the screen reader's.
            <button key={t.id} type="button" className="mlearncard" data-id={`learn.${t.id}`} aria-label={`${t.title}. ${t.subtitle}`}
              onClick={() => { gameAudio.play("ui-open"); setTutorial(t); setIndex(0); }}>
              <DeckArt name={t.art} colors={t.colors} focus={0.3} />
              <i className="mlearnshade" />
              <span className="mlearntitle"><b>{t.title}</b><span className="mbtn secondary compact">Begin ›</span></span>
            </button>
          ))}
        </div>
      ) : (
        <div className="mlearnpage">
          <div key={page.id} className="mlearntext">
            <h3>{page.title}</h3>
            <p>{page.body}</p>
          </div>
          <footer className="mlearnfoot">
            <Btn kind="secondary" compact onClick={() => step(-1)}>Back</Btn>
            <div className="mlearndots" role="progressbar" aria-valuetext={`Page ${index + 1} of ${tutorial.pages.length}`}>
              {tutorial.pages.map((p, i) => <i key={p.id} className={i === index ? "on" : i < index ? "seen" : ""} />)}
            </div>
            <Btn compact onClick={() => step(1)}>{index === tutorial.pages.length - 1 ? "Done" : "Next"}</Btn>
          </footer>
        </div>
      )}
    </div>
  );
}
