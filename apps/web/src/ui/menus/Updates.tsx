/**
 * Updates as Arena's inbox (iOS NativeUpdateNewsView): a blade from the right over the dimmed menu, one column of
 * messages, each a ◆, its title and its date, the newest tagged New in ember; a click opens it in place with its art.
 * The release notes are the phones' (UpdateNews), with the web's own first; the links sit in the last message.
 */
import { useState } from "react";
import { gameAudio } from "../audio";
import { SUPPORT } from "./Options";
import { DeckArt } from "./DeckBox";
import { Caps, PanelHeader } from "./kit";

interface Message { id: string; title: string; day: number; art: string; colors: string[]; lede: string; notes: string[] }

const MESSAGES: Message[] = [
  { id: "web-arena", title: "MagicMobile on your desktop", day: 23, art: "The Ur-Dragon", colors: ["W", "U", "B", "R", "G"],
    lede: "The browser game now opens on Arena's menus: Play, your deck boxes, the Custom Table, Ranked and Options, over the tavern room.",
    notes: ["Quick Match picks an AI at your deck's bracket, or the bracket, deck and skill you choose.", "Ranked against the AI moves your rank in this browser, from Bronze to Mythic.",
      "Music plays in the menus and at the table; choose the tracks in Options › Audio › Sound Lab."] },
  { id: "arena-menus", title: "The menus follow the Arena board", day: 22, art: "Rhystic Study", colors: ["U"],
    lede: "Every menu now matches the Arena board: Play opens a panel beside your deck boxes, and the boxes open when you choose one.",
    notes: ["Your decks stand in boxes with the commander on the front; the one you choose opens and its commander rises out.",
      "Play is a panel on the right with Find Match, Friends and Recently Played, and a search waits in it with a timer.",
      "Decks, Options, Updates, Downloads and How to Play open as panels over the room.",
      "Held sideways, the deck builder shows the cards to add beside your deck as a list."] },
  { id: "messages", title: "Messages and the Ranked Hall", day: 17, art: "Kynaios and Tiro of Meletis", colors: ["W", "U", "R", "G"],
    lede: "Message your friends from Friends, or from the game menu in the middle of a game. A banner shows a new message.",
    notes: ["Repeat a combo: do the same thing three times in a turn and the game offers to repeat it, as many times as you pick, until you can't, or until they lose. It waits for your triggers and keeps choosing the same kind of target.",
      "Ranked opens the Ranked Hall, with a live leaderboard of this season's players and who's online.", "Spread-out token piles stack back up with the Stack chip."] },
  { id: "sign-in", title: "Keep your profile", day: 8, art: "Atraxa, Praetors' Voice", colors: ["W", "U", "B", "G"],
    lede: "Sign in with Apple or Google on the Profile screen, and your name, friends and rank follow you to any phone.", notes: [] },
  { id: "turns", title: "Smoother turns", day: 7, art: "Thousand-Year Storm", colors: ["U", "R"],
    lede: "Your spells resolve without an extra tap. Turn off Pass After Casting in Options to hold priority.",
    notes: ["Don't ask again: tick it on a card's \"you may\" question and the game answers it for you for the rest of the game. Change your mind in the game menu.",
      "Resolve all: one tap lets a pile of triggers on the stack resolve, and it stops if an opponent responds.",
      "Pick any number of cards at once with Select all, and remember which of your triggers goes first.",
      "The AI waits less while your triggers resolve, and XMage is updated with 78 new cards and many card fixes."] },
  { id: "table", title: "More on the table", day: 7, art: "Courser of Kruphix", colors: ["G"],
    lede: "When you can see the top of your library, it sits beside your portrait. Tap it to see it large and cast or play it.",
    notes: ["The stack shows what resolves next, whose it is, its targets, and Resolve all.",
      "Your portrait glows when you can cast from your graveyard, exile or the top of your library, not only your commander, and the zone menu says which.",
      "A small sun or moon shows when it's day or night, the storm count shows under the turn plate, and City's Blessing shows on your medallion.",
      "The starting roll has more table: the header sits at the top and the dice get the room below it."] },
  { id: "art", title: "Choose your card art", day: 7, art: "Krenko, Mob Boss", colors: ["R"],
    lede: "Choose the artwork for any card in Deck Studio. Your pick shows in games and offline, survives export and import, and online images match it.",
    notes: ["The offline download now includes every token and emblem."] },
  { id: "profile", title: "Your games at a glance", day: 6, art: "Edgar Markov", colors: ["W", "B", "R"],
    lede: "Your profile shows win rate, favourite commanders, colours and rank history. Your game history lives there now.",
    notes: ["Find friends as you type their name, and open any player's profile. Choose whether yours is public, friends only or private.",
      "The starting roll happens on the table: every player's d20 tumbles across it and lands."] },
  { id: "battery", title: "Easier on your battery", day: 5, art: "Lightning Greaves", colors: [], lede: "The game rests while it waits for you, and the app is a smaller download.", notes: [] },
  { id: "ranked", title: "Ranked seasons", day: 4, art: "Elesh Norn, Grand Cenobite", colors: ["W"],
    lede: "Climb from Bronze to Mythic in monthly seasons, against players near your rank or an AI at your tier.",
    notes: ["Quick Match: one AI at your deck's bracket, or choose its bracket, deck and skill.",
      "Challenge a friend to a Quick Match, or to Ranked when you're in the same tier. Friend ranked games count.",
      "Every deck shows its Commander bracket, with the Game Changers and combos behind it.",
      "Your profile: rank, season history, stats, achievements, titles and match history. Your profile picture is your favorite commander's art.",
      "21 new included decks from Bracket 1 to 4, for you and for the AI.", "A real 3D tavern room behind the menu that shifts as you tilt your phone, with flickering candles."] },
  { id: "tavern", title: "A new table", day: 3, art: "Prossh, Skyraider of Kher", colors: ["B", "R", "G"],
    lede: "A new table with painted card frames, in portrait and landscape, and every spell cast with its own moment at the centre of it.",
    notes: ["Tap a player's medallion for their counters, poison and commander damage, and swap between opponents.", "Big boards run smoother: identical tokens stack once there are eight.",
      "A Back button while declaring attackers and blockers.", "Friends, table chat and invite links that open straight into your table."] },
];

const date = (day: number) => new Date(2026, 9, day).toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });

export function UpdatesPanel({ onClose }: { onClose: () => void }) {
  const [open, setOpen] = useState<string>();
  const row = (id: string, title: string, when: string | undefined, isNew: boolean, body: React.ReactNode) => {
    const shown = open === id;
    return (
      <div key={id} className={`minboxrow ${shown ? "open" : ""}`}>
        <button type="button" data-id={`updates.inbox.${id}`} aria-expanded={shown}
          onClick={() => { gameAudio.play(shown ? "ui-back" : "ui-open"); setOpen(shown ? undefined : id); }}>
          <i className={`mdiamond ${isNew ? "lit" : ""}`} />
          <span className="grow">
            {isNew && <em>New</em>}
            <b>{title}</b>
            {when && <small className={isNew ? "new" : ""}>{when}</small>}
          </span>
        </button>
        {shown && <div className="minboxbody">{body}</div>}
      </div>
    );
  };
  return (
    <div className="minbox">
      <PanelHeader title="Inbox" onClose={onClose} />
      <div className="minboxlist mscroll">
        <Caps text="What's new" size={9.5} className="minboxhead" />
        {MESSAGES.map((m, index) => row(m.id, m.title, date(m.day), index === 0, (
          <>
            <div className="minboxart"><DeckArt name={m.art} colors={m.colors} /></div>
            <p className="lede">{m.lede}</p>
            {m.notes.map((note) => <p key={note}>{note}</p>)}
          </>
        )))}
        {row("about", "About & links", undefined, false, (
          <>
            <div className="minboxbuild"><span>Installed build</span><b>MagicMobile 0.1.1 (web)</b></div>
            <Section title="XMage news" footer="Opens GitHub. Upstream changes are not installed automatically. New cards and abilities become available only after a compatible MagicMobile build is tested and released.">
              <a href="https://github.com/magefree/mage/releases" target="_blank" rel="noopener">XMage release notes <i>↗</i></a>
              <a href="https://github.com/magefree/mage/commits/master/" target="_blank" rel="noopener">Latest upstream changes <i>↗</i></a>
            </Section>
            <Section title="About" footer="Independent fan project. Not affiliated with Wizards of the Coast. Magic: The Gathering and card artwork belong to their respective owners.">
              <span>Card images from Scryfall</span>
              <a href="https://magicmobile-downloads.vercel.app/privacy/" target="_blank" rel="noopener">Privacy <i>↗</i></a>
            </Section>
            <Section title="Support MagicMobile" footer={SUPPORT.note}>
              <a href={SUPPORT.url} target="_blank" rel="noopener">{SUPPORT.action} <i>↗</i></a>
            </Section>
          </>
        ))}
      </div>
    </div>
  );
}

function Section({ title, footer, children }: { title: string; footer?: string; children: React.ReactNode }) {
  return (
    <div className="mnewssection">
      <Caps text={title} />
      <div className="mnewsrows">{children}</div>
      {footer && <p>{footer}</p>}
    </div>
  );
}
