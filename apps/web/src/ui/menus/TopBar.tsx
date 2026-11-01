/**
 * Arena's top bar on every menu page (iOS ArenaTopBar): the mark, the five tabs as engraved emblems with labels, and on
 * the right your rank, messages, news and the gear. The utility whose panel is open lights instead of a tab. The phone's
 * Downloads (card art kept on the phone) has no web counterpart: the browser fetches art as it needs it.
 */
import type { RankTier } from "../../core/rankLadder";
import { gameAudio } from "../audio";
import { BrandMark } from "./BrandMark";
import { Emblem, TabBar, UnreadPip } from "./kit";

export type MenuTab = "home" | "profile" | "decks" | "ranked" | "learn";

export const MENU_TABS: { tab: MenuTab; title: string; symbol: string }[] = [
  { tab: "home", title: "Home", symbol: "home" },
  { tab: "profile", title: "Profile", symbol: "profile" },
  { tab: "decks", title: "Decks", symbol: "decks" },
  { tab: "ranked", title: "Ranked", symbol: "ranked" },
  { tab: "learn", title: "Learn", symbol: "learn" },
];

/** A tier's emblem: the rendered badge art (RankEmblem). */
export function RankEmblem({ tier, size = 96, grey = false }: { tier: RankTier; size?: number; grey?: boolean }) {
  return <img className={`mrankemblem ${grey ? "grey" : ""}`} src={`/menus/tavern-rank-${tier}.webp`} width={size} height={size} alt="" draggable={false} />;
}

export function TopBar({ selected, select, rank, openRank, unread, messages, updates, settings, lit }: {
  selected?: MenuTab; select: (tab: MenuTab) => void;
  rank?: { tier: RankTier; title: string; placing?: boolean }; openRank?: () => void;
  unread?: boolean; messages?: () => void; updates?: () => void; settings: () => void;
  /** The utility a panel is open for ("settings", "updates", "messages"). */
  lit?: string;
}) {
  const icon = (id: string, symbol: string, label: string, action: () => void, pip = false) => (
    <button type="button" className="mtopicon" aria-label={label} data-id={`menu.${id}`} onClick={() => { gameAudio.play("ui-open"); action(); }}>
      <Emblem name={symbol} size={17} lit={lit === id} />
      <TabBar on={lit === id} />
      {pip && <span className="mtoppip"><UnreadPip /></span>}
    </button>
  );
  return (
    <nav className="mtopbar" aria-label="Menu">
      <span className="mtopmark" role="img" aria-label="MagicMobile"><BrandMark size={28} /></span>
      {MENU_TABS.map(({ tab, title, symbol }) => {
        const on = selected === tab;
        return (
          <button key={tab} type="button" className={`mtoptab ${on ? "on" : ""}`} aria-current={on ? "page" : undefined} data-id={`menu.tab.${tab}`}
            onClick={() => { if (on && tab !== "learn") return; gameAudio.play("ui-tap"); select(tab); }}>
            <Emblem name={symbol} size={17} lit={on} />
            <span>{title}</span>
          </button>
        );
      })}
      <span className="grow" />
      {rank && (
        <button type="button" className="mrankchip" aria-label={`Your rank, ${rank.title}`} data-id="menu.rank"
          onClick={() => { gameAudio.play("ui-open"); openRank?.(); }}>
          <RankEmblem tier={rank.tier} size={22} grey={rank.placing} /><span>{rank.title}</span>
        </button>
      )}
      {messages && icon("messages", "messages", "Friends and messages", messages, unread)}
      {updates && icon("updates", "updates", "Updates", updates)}
      {icon("settings", "settings", "Settings", settings)}
    </nav>
  );
}
