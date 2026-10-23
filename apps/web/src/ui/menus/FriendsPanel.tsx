/**
 * Arena's social panel (iOS FriendsView.swift with Ranked/SocialComponents.swift, and FriendConversationView.swift's
 * FriendMessagesList): your name at the top with Change, Friends and Messages as a tab strip with the unread count, a
 * live search in one slim field, requests folded into a row, your friends one line each (status, rank, Join, Message
 * and a ⋯ menu), what you sent and whom you blocked, and the Delete my profile link at the foot. Questions are small
 * glass prompts drawn in the panel, never system alerts.
 *
 * Rendered inside the shell's MenuPanel placement="leading": this is the panel's content only. The profile and
 * conversation open through the shell (openProfile, openConversation).
 *
 * Left out for now: the Challenge menu on a friend's row (friend challenges need hosting from the browser; a later
 * phase).
 *
 * The small pieces the other social screens share (Conversation, PublicProfile, Leaderboard) live here too, as iOS's
 * SocialComponents.swift: the floating notice, the waiting line, a player's heading, the glass question and pop-over.
 */
import { type ReactNode, useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";
import {
  type AccountState, FriendMessageRules, type MessageConversation, type PlayerAccount, PlayerAccountRules, PlayerFriend, PlayerSearchResult,
  PlayerSearchRules, ProfileVisibility, SearchCancelled,
} from "../../core/account";
import type { RankPosition } from "../../core/rankLadder";
import {
  conversationLabel, friendLabel, friendStatus, messagePreview, searchHint, searchResultLabel, searchResultLine, usernameDraft, withRelation,
} from "../../core/socialText";
import { SupabaseLite } from "../../core/supabaseLite";
import { gameAudio } from "../audio";
import { DeckArt } from "./DeckBox";
import { Btn, Caps, OptionRow, PanelHeader, Pill, SearchField } from "./kit";
import { RankEmblem } from "./TopBar";
import "./social.css";

// MARK: Shared pieces

/** The account's state, re-read on every change. */
export function useAccountState(account: PlayerAccount): AccountState {
  const subscribe = useCallback((listener: () => void) => account.subscribe(listener), [account]);
  useSyncExternalStore(subscribe, () => account.version);
  return account.state;
}

/** Small glyphs the social screens draw (SF Symbols' shapes, filled, in a 24-unit box). */
const GLYPH: Record<string, ReactNode> = {
  person: <><circle cx="12" cy="8" r="4.5" /><path d="M3.5 21c.6-5 4-8 8.5-8s7.9 3 8.5 8z" /></>,
  bubble: <path d="M4 3.5h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-9l-5.5 4v-4H4a2 2 0 0 1-2-2v-10a2 2 0 0 1 2-2z" />,
  ellipsis: <><circle cx="5" cy="12" r="2.3" /><circle cx="12" cy="12" r="2.3" /><circle cx="19" cy="12" r="2.3" /></>,
  arrow: <path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm.6 5 5 5-5 5-1.5-1.4 2.6-2.6H6.5v-2h7.2l-2.6-2.6z" fillRule="evenodd" />,
  xmark: <path d="M6.3 4.9 12 10.6l5.7-5.7 1.4 1.4-5.7 5.7 5.7 5.7-1.4 1.4-5.7-5.7-5.7 5.7-1.4-1.4 5.7-5.7-5.7-5.7z" />,
  shield: <path d="M12 2.5 4 5.5v6c0 5 3.4 9 8 10.5 4.6-1.5 8-5.5 8-10.5v-6zm0 2.1v15.2c-3.3-1.4-6-4.5-6-8.3V6.9z" fillRule="evenodd" />,
  people: <><circle cx="9" cy="7.5" r="3.6" /><circle cx="16.5" cy="8.4" r="3" /><path d="M2 20c.5-4.2 3.2-6.6 7-6.6s6.5 2.4 7 6.6zm14.5 0c-.2-2.3-1-4.2-2.4-5.4.9-.5 1.9-.7 2.8-.7 3 0 5.3 2.2 5.6 6.1z" /></>,
  chat: <path d="M3 3h12a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H9l-4 3v-3H3a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zm16 4h1a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-1v3l-4-3h-4a2 2 0 0 1-2-2h7a3 3 0 0 0 3-3z" />,
  magnifier: <path d="M10.5 3a7.5 7.5 0 0 1 6 12l4.8 4.8-1.5 1.5-4.8-4.8A7.5 7.5 0 1 1 10.5 3zm0 2.2a5.3 5.3 0 1 0 0 10.6 5.3 5.3 0 0 0 0-10.6z" fillRule="evenodd" />,
  hourglass: <path d="M6 2h12v2h-1v2.5c0 2-1.3 3.7-3.2 4.5v2c1.9.8 3.2 2.5 3.2 4.5V20h1v2H6v-2h1v-2.5c0-2 1.3-3.7 3.2-4.5v-2C8.3 10.2 7 8.5 7 6.5V4H6z" />,
  sparkles: <path d="M10 3c.6 4 2.5 6 6.5 6.5C12.5 10 10.6 12 10 16c-.6-4-2.5-6-6.5-6.5C7.5 9 9.4 7 10 3zm8 10c.3 2 1.2 2.9 3.2 3.2-2 .3-2.9 1.2-3.2 3.2-.3-2-1.2-2.9-3.2-3.2 2-.3 2.9-1.2 3.2-3.2z" />,
  hand: <path d="M10 2.5a1.5 1.5 0 0 1 1.5 1.5v7h.7V3.2a1.5 1.5 0 0 1 3 0V11h.7V5a1.5 1.5 0 0 1 3 0v9.5c0 4.2-3 7.5-7 7.5-2.6 0-4.5-1.2-5.8-3.3L3.3 13.5a1.5 1.5 0 0 1 2.5-1.6l2.7 3.3V4a1.5 1.5 0 0 1 1.5-1.5z" />,
  wifi: <path d="M12 18.5a2 2 0 1 1 0 4 2 2 0 0 1 0-4zM2 8.6A15 15 0 0 1 17.7 5l-.9 2A13 13 0 0 0 3.4 10zm3 3.3a10.5 10.5 0 0 1 10.6-2.4l-.8 2a8.4 8.4 0 0 0-8.3 1.9zm3.1 3.2a6 6 0 0 1 5.1-1.6l-.6 2.1a3.9 3.9 0 0 0-3 1zM19 8h2v8h-2zm0 10h2v2h-2z" />,
  question: <path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-1 15h2v2h-2zm1-11.5c2.2 0 3.8 1.4 3.8 3.3 0 1.6-1 2.4-1.9 3-.6.4-.9.7-.9 1.4v.3h-2v-.5c0-1.4.8-2.1 1.6-2.6.7-.5 1.2-.8 1.2-1.6 0-.9-.8-1.5-1.8-1.5-1.1 0-1.9.7-2 1.7H8.1c.1-2.1 1.7-3.5 3.9-3.5z" fillRule="evenodd" />,
};

/** One of the social screens' glyphs, gold by default. */
export function SocialGlyph({ name, size = 16, className = "" }: { name: string; size?: number; className?: string }) {
  return <svg className={`msocialglyph ${className}`} viewBox="0 0 24 24" width={size} height={size} aria-hidden="true">{GLYPH[name]}</svg>;
}

/** A notice that floats at the bottom of the panel; a click dismisses it (SocialNotice). */
export function SocialNotice({ text, onDismiss, lift = 0 }: { text: string; onDismiss: () => void; lift?: number }) {
  return (
    <div className="msocialnoticewrap" style={{ bottom: 10 + lift }}>
      <button type="button" className="msocialnotice" data-id="friends.notice" aria-live="polite" onClick={onDismiss}>{text}</button>
    </div>
  );
}

/** A line of waiting without a system spinner: three gold pips that breathe in turn (SocialWaiting). */
export function SocialWaiting({ text }: { text: string }) {
  return (
    <div className="msocialwaiting" role="status" aria-label={text}>
      <span aria-hidden="true"><i /><i /><i /></span>
      <em>{text}</em>
    </div>
  );
}

/** A line saying what will fill an empty list (ProfileEmptyNote). */
export function SocialEmpty({ text, glyph = "sparkles", id }: { text: string; glyph?: string; id?: string }) {
  return <p className="msocialempty" data-id={id}><SocialGlyph name={glyph} size={16} />{text}</p>;
}

/** A small capital tag in a dark lozenge (TavernTag in the Arena look). */
export function SocialTag({ text, accent }: { text: string; accent?: "online" | "ember" }) {
  return <i className={`msocialtag ${accent ?? ""}`}>{text}</i>;
}

/** A glowing green dot with a slow ring pulsing out of it: online now (LeaderboardOnlineDot). */
export function OnlineDot({ size = 8 }: { size?: number }) {
  return <i className="monlinedot" style={{ width: size, height: size }} aria-hidden="true" />;
}

/** A commander's art in a gold ring, or a figure when there is none (CommanderArtMedallion). */
export function Medallion({ name, size }: { name?: string; size: number }) {
  const shown = name !== undefined && name.trim() !== "" ? name : undefined;
  return (
    <span className="mmedallion" style={{ width: size, height: size }} role="img" aria-label={shown ? `Profile picture: ${shown}` : "Profile picture"}>
      {shown ? <DeckArt name={shown} colors={[]} /> : <SocialGlyph name="person" size={size * 0.46} className="dim" />}
    </span>
  );
}

/**
 * A player's name in a list as Arena's one-line row: their commander's art in a ring (a dot for who is online), the
 * name, a line under it, and their rank's emblem (SocialPlayerHeading, compact).
 */
export function PlayerHeading({ username, commander, line, online, rank }: {
  username: string; commander?: string; line: string; online?: boolean; rank?: RankPosition;
}) {
  return (
    <span className="mplayerheading">
      <span className="mplayerpicture">
        <Medallion name={commander} size={32} />
        {online !== undefined && <i className={`mplayerdot ${online ? "on" : ""}`} aria-hidden="true" />}
      </span>
      <span className="grow">
        <b>{username}</b>
        <small>{line}</small>
      </span>
      <span className="mplayerrank" aria-hidden="true">
        {rank ? <RankEmblem tier={rank.tier} size={24} /> : <SocialGlyph name="shield" size={15} className="faint" />}
      </span>
    </span>
  );
}

export interface MenuItem { title: string; id: string; destructive?: boolean; onClick: () => void }

/** A ⋯ button that opens a small glass pop-over of choices under it (TavernMenu in the Arena look). */
export function MoreMenu({ label, id, items, size = 16 }: { label: string; id: string; items: MenuItem[]; size?: number }) {
  const [open, setOpen] = useState(false);
  const [up, setUp] = useState(false);
  const root = useRef<HTMLSpanElement>(null);
  const toggle = () => {
    // Opens upward when the list it sits in has too little room below for it.
    const button = root.current?.getBoundingClientRect();
    const bounds = root.current?.closest(".mscroll")?.getBoundingClientRect();
    setUp(button !== undefined && bounds !== undefined && bounds.bottom - button.bottom < 40 * items.length + 40);
    setOpen(!open);
  };
  useEffect(() => {
    if (!open) return;
    const away = (e: PointerEvent) => { if (!root.current?.contains(e.target as Node)) setOpen(false); };
    window.addEventListener("pointerdown", away, true);
    return () => window.removeEventListener("pointerdown", away, true);
  }, [open]);
  return (
    <span className="mmore" ref={root}>
      <button type="button" className="mmorebutton" aria-label={label} aria-haspopup="menu" aria-expanded={open} data-id={id}
        onClick={() => { gameAudio.play("ui-tap"); toggle(); }}>
        <SocialGlyph name="ellipsis" size={size} />
      </button>
      {open && (
        <span className={`mmorepop glass ${up ? "up" : ""}`} role="menu">
          {items.map((item) => (
            <button key={item.id} type="button" role="menuitem" className={item.destructive ? "danger" : ""} data-id={item.id}
              onClick={() => { gameAudio.play("ui-tap"); setOpen(false); item.onClick(); }}>{item.title}</button>
          ))}
        </span>
      )}
    </span>
  );
}

/**
 * A question as a small glass panel over the screen it belongs to (ArenaPromptPanel): the title, the message, a dark
 * pill to step back and a red pill to go ahead.
 */
export function SocialQuestion({ title, message, confirm, onConfirm, onCancel, id }: {
  title: string; message: string; confirm: string; onConfirm: () => void; onCancel: () => void; id: string;
}) {
  return (
    <div className="msocialquestion" data-id={id}>
      <div className="mdim" onClick={() => { gameAudio.play("ui-back"); onCancel(); }} />
      <div className="msocialprompt glass" role="alertdialog" aria-modal="true" aria-label={title}>
        <h2>{title}</h2>
        <p>{message}</p>
        <div className="msocialpromptactions">
          <Btn kind="secondary" compact id={`${id}.cancel`} onClick={onCancel}>Cancel</Btn>
          <Btn kind="danger" compact id={`${id}.confirm`} onClick={onConfirm}>{confirm}</Btn>
        </div>
      </div>
    </div>
  );
}

// MARK: The panel

type Search = { kind: "idle" } | { kind: "searching" } | { kind: "done" } | { kind: "failed"; message: string };
type Tab = "friends" | "messages";

export function FriendsPanel({ account, onClose, join, openProfile, openConversation }: {
  account: PlayerAccount;
  onClose: () => void;
  /** Joins a friend's open table by its code (the same path as an invite link). */
  join: (code: string) => void;
  openProfile: (username: string) => void;
  openConversation: (username: string) => void;
}) {
  const state = useAccountState(account);
  const [nameDraft, setNameDraft] = useState("");
  const [editingName, setEditingName] = useState(false);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<PlayerSearchResult[]>([]);
  const [search, setSearch] = useState<Search>({ kind: "idle" });
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [confirmBlock, setConfirmBlock] = useState<PlayerFriend>();
  const [tab, setTab] = useState<Tab>("friends");
  const [showRequests, setShowRequests] = useState(false);

  useEffect(() => {
    if (account.state.phase === "ready") void account.refresh(); else void account.start();
  }, [account]);

  // Typing: wait a moment after the last key, and drop the answer a newer search replaced.
  useEffect(() => {
    const text = PlayerSearchRules.normalized(query);
    if (!account.state.searchAvailable || text === undefined) { setResults([]); setSearch({ kind: "idle" }); return; }
    setSearch({ kind: "searching" });
    let cancelled = false;
    const timer = window.setTimeout(async () => {
      try {
        const found = await account.search(text);
        if (cancelled) return;
        setResults(found);
        setSearch({ kind: "done" });
      } catch (error) {
        if (cancelled || error instanceof SearchCancelled) return;
        setResults([]);
        // Without the server's search the field turns into a plain "add by name" one.
        setSearch(account.state.searchAvailable ? { kind: "failed", message: PlayerAccountRules.message(SupabaseLite.code(error)) } : { kind: "idle" });
      }
    }, 250);
    return () => { cancelled = true; window.clearTimeout(timer); };
  }, [account, query]);

  const now = Date.now();
  const ready = state.phase === "ready";
  const showsDeleteLink = ready && state.username !== undefined && !editingName;
  const incoming = state.friends.filter(PlayerFriend.isIncoming);
  const outgoing = state.friends.filter(PlayerFriend.isOutgoing);
  const friends = state.friends.filter(PlayerFriend.isFriend);

  const open = (name: string) => { gameAudio.play("ui-open"); openProfile(name); };
  const message = (name: string) => { gameAudio.play("ui-open"); openConversation(name); };
  const addByName = () => { const name = query; setQuery(""); void account.addFriend(name); };
  const addFromSearch = async (result: PlayerSearchResult) => {
    setResults((list) => list.map((r) => (r.username === result.username ? withRelation(r, "outgoing") : r)));
    await account.addFriend(result.username);
    await account.refresh();
    // A request they had already sent you makes you friends at once.
    const after = account.state.friends.find((f) => f.username === result.username);
    if (after) setResults((list) => list.map((r) => (r.username === result.username ? withRelation(r, after.relation) : r)));
  };
  const acceptFromSearch = (result: PlayerSearchResult) => {
    const friend = account.state.friends.find((f) => f.username === result.username);
    if (!friend) return;
    setResults((list) => list.map((r) => (r.username === result.username ? withRelation(r, "friend") : r)));
    void account.respond(friend, true);
  };
  const saveName = async () => { if (await account.claim(nameDraft)) setEditingName(false); };

  const nameCard = (
    <div className="mcard msocialcard" data-id="friends.nameCard">
      <Caps text="Your player name" />
      <input className="msocialfield" value={nameDraft} placeholder="Player name" spellCheck={false} autoCapitalize="off" autoComplete="off"
        aria-label="Player name" data-id="friends.nameField" onChange={(e) => setNameDraft(usernameDraft(e.target.value))}
        onKeyDown={(e) => { if (e.key === "Enter" && PlayerAccountRules.isValidUsername(nameDraft)) void saveName(); }} />
      <div className="msocialrow">
        <Pill lit id="friends.saveName" disabled={!PlayerAccountRules.isValidUsername(nameDraft)} onClick={() => void saveName()}>
          {editingName ? "Save name" : "Choose name"}
        </Pill>
        {editingName && <Pill onClick={() => setEditingName(false)}>Cancel</Pill>}
      </div>
      <small className="msocialdim">Used at every table, and friends add you by it. 3–20 letters, numbers or underscores.</small>
    </div>
  );

  const profileCard = (
    <div className="msocialme">
      <button type="button" className="msocialmebutton grow" data-id="friends.myProfile" aria-label={`Your profile, ${state.username ?? ""}`}
        onClick={() => { if (state.username) open(state.username); }}>
        <SocialGlyph name="person" size={30} />
        <span className="grow">
          <b>{state.username}</b>
          <small>{state.visibilityKnown ? `Profile: ${ProfileVisibility.title(state.visibility)}` : "Your name at every table"}</small>
        </span>
      </button>
      <Pill id="friends.changeName" onClick={() => { setNameDraft(state.username ?? ""); setEditingName(true); }}>Change</Pill>
    </div>
  );

  const tabPicker = (
    <div className="msegmented stretch msocialtabs" role="tablist" aria-label="Friends">
      {(["friends", "messages"] as Tab[]).map((option) => {
        const on = tab === option;
        return (
          <button key={option} type="button" role="tab" aria-selected={on} className={on ? "on" : ""} data-id={`friends.tab.${option}`}
            onClick={() => { if (on) return; gameAudio.play("ui-tap"); setTab(option); }}>
            {option === "friends" ? "Friends" : "Messages"}
            {option === "messages" && state.unreadMessages > 0 && <span className="msocialcount">{state.unreadMessages}</span>}
            <i className="mtabbar" />
          </button>
        );
      })}
    </div>
  );

  const trimmed = query.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");
  const hint = searchHint(trimmed);
  const searchRow = (
    <div className="msocialsearch" data-id="friends.searchCard">
      <div className="msocialrow">
        <div className="grow" data-id={state.searchAvailable ? "friends.search" : "friends.addField"}
          onKeyDown={(e) => { if (e.key === "Enter" && !state.searchAvailable && trimmed !== "") addByName(); }}>
          <SearchField placeholder={state.searchAvailable ? "Find players" : "Their exact player name"} value={query} onChange={setQuery} />
        </div>
        {!state.searchAvailable && <Pill lit id="friends.add" disabled={trimmed === ""} onClick={addByName}>Add</Pill>}
      </div>
      {state.searchAvailable ? (
        <>
          {hint !== undefined ? <small className="msocialdim" data-id="friends.search.hint">{hint}</small>
            : search.kind === "failed" ? <small className="msocialerror" data-id="friends.search.error">{search.message}</small>
              : search.kind === "searching" && results.length === 0 ? <SocialWaiting text="Looking for players…" />
                : search.kind === "done" && results.length === 0 ? <SocialEmpty text={`No players found starting with “${trimmed}”.`} glyph="magnifier" id="friends.search.empty" />
                  : null}
          {results.length > 0 && hint === undefined && trimmed !== "" && (
            <div className={`msocialresults ${search.kind === "searching" ? "stale" : ""}`} data-id="friends.search.results">
              {results.map((result) => (
                <div key={result.username} className="msocialrowcard">
                  <button type="button" className="msocialheadbutton" aria-label={searchResultLabel(result, now)} data-id={`friends.result.${result.username}`}
                    onClick={() => open(result.username)}>
                    <PlayerHeading username={result.username} commander={result.favoriteCommander} line={searchResultLine(result)}
                      online={result.relation === "friend" ? result.online : undefined} rank={PlayerSearchResult.position(result, now)} />
                  </button>
                  <div className="msocialrow">
                    {result.visibility !== "public" && <SocialTag text={result.visibility === "friends" ? "FRIENDS ONLY" : "PRIVATE"} />}
                    <span className="grow" />
                    <Pill id={`friends.result.profile.${result.username}`} onClick={() => open(result.username)}>Profile</Pill>
                    {result.relation === "friend" ? <SocialTag text="FRIENDS" accent={result.online === true ? "online" : undefined} />
                      : result.relation === "outgoing" ? <SocialTag text="REQUESTED" />
                        : result.relation === "incoming"
                          ? <Pill lit id={`friends.result.accept.${result.username}`} onClick={() => acceptFromSearch(result)}>Accept</Pill>
                          : <Pill lit id={`friends.result.add.${result.username}`} onClick={() => void addFromSearch(result)}>Add friend</Pill>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </>
      ) : query !== "" ? (
        <small className="msocialdim" data-id="friends.searchUnavailable">
          Live search arrives with the next server update. Until then, add a friend by their exact player name.
        </small>
      ) : null}
    </div>
  );

  const requestsRow = incoming.length > 0 && (
    <div className="msocialrequests">
      <OptionRow title="Requests" value={`${incoming.length}`} chevron id="friends.requests" onClick={() => setShowRequests(!showRequests)} />
      {showRequests && incoming.map((friend) => (
        <div key={friend.id} className="msocialrowcard line mrise">
          <button type="button" className="msocialheadbutton grow" aria-label={`${friend.username} wants to be your friend`} data-id={`friends.request.${friend.username}`}
            onClick={() => open(friend.username)}>
            <PlayerHeading username={friend.username} line="Wants to be your friend" rank={state.friendRanks[friend.username]} />
          </button>
          <button type="button" className="msocialicon dim" aria-label="Decline" data-id={`friends.decline.${friend.username}`}
            onClick={() => { gameAudio.play("ui-back"); void account.respond(friend, false); }}>
            <SocialGlyph name="xmark" size={12} />
          </button>
          <Pill lit id={`friends.accept.${friend.username}`} onClick={() => void account.respond(friend, true)}>Accept</Pill>
        </div>
      ))}
    </div>
  );

  const friendsList = (
    <div className="msociallist" data-id="friends.list">
      <div className="msocialsection"><Caps text="Friends" />{friends.length > 0 && <small>{state.onlineFriendCount} online</small>}</div>
      {friends.length === 0 && (
        <SocialEmpty glyph="people" text="Search for a player above to add your first friend. You'll see when they're online and can join their tables." />
      )}
      {friends.map((friend) => {
        const code = PlayerFriend.joinableCode(friend);
        return (
          <div key={friend.id} className="msocialfriend">
            <button type="button" className="msocialheadbutton grow" aria-label={friendLabel(friend, state.friendRanks[friend.username], now)}
              data-id={`friends.card.${friend.username}`} onClick={() => open(friend.username)}>
              <PlayerHeading username={friend.username} line={friendStatus(friend, now)} online={friend.online} rank={state.friendRanks[friend.username]} />
            </button>
            {code !== undefined && (
              <button type="button" className="msocialjoin" aria-label={`Join ${friend.username}'s table`} data-id={`friends.join.${friend.username}`}
                onClick={() => { gameAudio.play("ui-confirm"); join(code); onClose(); }}>
                <i><SocialGlyph name="arrow" size={16} /></i>
              </button>
            )}
            {state.messagesAvailable && (
              <button type="button" className="msocialicon" aria-label={`Message ${friend.username}`} data-id={`friends.message.${friend.username}`}
                onClick={() => message(friend.username)}>
                <SocialGlyph name="bubble" size={15} />
              </button>
            )}
            <MoreMenu label={`More about ${friend.username}`} id={`friends.more.${friend.username}`} items={[
              { title: "View profile", id: "friends.more.profile", onClick: () => open(friend.username) },
              { title: "Message", id: "friends.more.message", onClick: () => message(friend.username) },
              { title: "Remove friend", id: "friends.more.remove", destructive: true, onClick: () => void account.remove(friend) },
              { title: "Block", id: "friends.more.block", destructive: true, onClick: () => setConfirmBlock(friend) },
            ]} />
          </div>
        );
      })}
    </div>
  );

  const sentList = outgoing.length > 0 && (
    <div className="msociallist">
      <div className="msocialsection"><Caps text="Sent" /><small>{outgoing.length}</small></div>
      {outgoing.map((friend) => (
        <div key={friend.id} className="msocialplain">
          <button type="button" className="msocialname grow" aria-label={`${friend.username}, request sent`} data-id={`friends.sent.${friend.username}`}
            onClick={() => open(friend.username)}>{friend.username}</button>
          <Pill id={`friends.cancel.${friend.username}`} onClick={() => void account.remove(friend)}>Cancel</Pill>
        </div>
      ))}
    </div>
  );

  const blockedList = state.blocked.length > 0 && (
    <div className="msociallist">
      <div className="msocialsection"><Caps text="Blocked" /><small>{state.blocked.length}</small></div>
      {state.blocked.map((name) => (
        <div key={name} className="msocialplain">
          <span className="msocialname grow">{name}</span>
          <Pill id={`friends.unblock.${name}`} onClick={() => void account.unblock(name)}>Unblock</Pill>
        </div>
      ))}
    </div>
  );

  let content: ReactNode;
  if (state.phase === "unavailable") {
    content = (
      <div className="mcard msocialcard">
        <p className="msocialtext">{state.notice ?? PlayerAccountRules.message("offline")}</p>
        <div><Pill id="friends.retry" onClick={() => void account.start()}>Try again</Pill></div>
      </div>
    );
  } else if (!ready) {
    content = <div className="mcard msocialcard"><SocialWaiting text="Loading your profile…" /></div>;
  } else if (state.username === undefined || editingName) {
    content = nameCard;
  } else {
    content = (
      <>
        {profileCard}
        {tabPicker}
        {tab === "messages" ? <FriendMessagesList account={account} open={message} /> : (
          <>
            {searchRow}
            {requestsRow}
            {friendsList}
            {sentList}
            {blockedList}
          </>
        )}
      </>
    );
  }

  return (
    <div className="msocial">
      <PanelHeader title="Friends" onClose={onClose} />
      <div className="msocialscroll mscroll" data-id="friends.scroll">
        {content}
        {showsDeleteLink && (
          <button type="button" className="msocialdelete" data-id="friends.deleteAccount" onClick={() => { gameAudio.play("ui-open"); setConfirmDelete(true); }}>
            Delete my profile
          </button>
        )}
      </div>
      {state.notice !== undefined && ready && <SocialNotice text={state.notice} onDismiss={() => account.setNotice(undefined)} />}
      {confirmDelete && (
        <SocialQuestion id="friends.confirmDelete" title="Delete your profile?" confirm="Delete profile"
          message="Your player name, friends, blocks and game history are removed from MagicMobile's server for good. Your decks and games in this browser stay."
          onCancel={() => setConfirmDelete(false)}
          onConfirm={() => { setConfirmDelete(false); void account.deleteAccount().then((done) => { if (done) onClose(); }); }} />
      )}
      {confirmBlock && (
        <SocialQuestion id="friends.confirmBlock" title={`Block ${confirmBlock.username}?`} confirm="Block"
          message="They're removed from your friends and can't send you requests. You can unblock them here later."
          onCancel={() => setConfirmBlock(undefined)}
          onConfirm={() => { const name = confirmBlock.username; setConfirmBlock(undefined); void account.block(name); }} />
      )}
    </div>
  );
}

// MARK: Messages

/**
 * The Messages tab (FriendMessagesList): friends you've written to by their last message (newest first, unread counts
 * in ember), then friends you haven't written to yet. Asks for conversations every 10 seconds while shown.
 */
export function FriendMessagesList({ account, open }: { account: PlayerAccount; open: (username: string) => void }) {
  const state = useAccountState(account);
  const [conversations, setConversations] = useState<MessageConversation[]>([]);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let stopped = false;
    let timer: number | undefined;
    const poll = async () => {
      const list = await account.conversations();
      if (stopped) return;
      if (list) setConversations(list);
      setLoaded(true);
      timer = window.setTimeout(() => { void poll(); }, 10_000);
    };
    void poll();
    return () => { stopped = true; window.clearTimeout(timer); };
  }, [account]);

  const friends = state.friends.filter(PlayerFriend.isFriend);
  const rows = FriendMessageRules.ordered(friends.map((f) => f.username), conversations);
  return (
    <div className="msociallist" data-id="messages.list">
      <div className="msocialsection"><Caps text="Messages" />{state.unreadMessages > 0 && <small>{state.unreadMessages} unread</small>}</div>
      {!state.messagesAvailable ? <SocialEmpty glyph="hourglass" text="Messages arrive with the next server update." />
        : friends.length === 0 ? <SocialEmpty glyph="chat" text="Add a friend to start a conversation. Messages stay between the two of you." />
          : !loaded ? <SocialWaiting text="Opening your messages…" />
            : rows.map((row) => {
              const friend = friends.find((f) => f.username === row.name);
              const unread = row.conversation?.unread ?? 0;
              return (
                <button key={row.name} type="button" className="msocialrowcard msocialmessage" aria-label={conversationLabel(row.name, row.conversation)}
                  data-id={`messages.row.${row.name}`} onClick={() => open(row.name)}>
                  <PlayerHeading username={row.name} line={messagePreview(row.conversation)} online={friend?.online} rank={state.friendRanks[row.name]} />
                  {unread > 0 && <span className="msocialcount big">{unread}</span>}
                </button>
              );
            })}
    </div>
  );
}
