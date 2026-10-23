/**
 * A conversation with a friend (iOS Ranked/FriendConversationView.swift): their messages in dark glass, yours in gold,
 * a day heading between days, "Read" under your last one once they've seen it, Earlier messages to page back, quick
 * replies over the composer, and new messages every few seconds while the page is visible. Their words show with strong
 * language masked, like table chat. Report and Block sit in the ⋯ menu.
 *
 * Content for a centred MenuPanel. Opening the newest page marks their messages read and refreshes the unread count
 * (PlayerAccount.thread), as iOS does.
 */
import { useEffect, useRef, useState } from "react";
import { FriendMessageRules, type FriendMessage, type PlayerAccount, PlayerAccountRules } from "../../core/account";
import { QUICK_REPLIES, startsNewDay } from "../../core/socialText";
import { SupabaseLite } from "../../core/supabaseLite";
import { gameAudio } from "../audio";
import { MoreMenu, OnlineDot, SocialGlyph, SocialNotice, SocialQuestion, SocialWaiting, useAccountState } from "./FriendsPanel";
import { Btn, CloseButton } from "./kit";
import "./social.css";

const dayHeading = new Intl.DateTimeFormat(undefined, { weekday: "long", month: "short", day: "numeric" });
const timeOfDay = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" });

export function Conversation({ account, username, onClose, openProfile }: {
  account: PlayerAccount;
  username: string;
  onClose: () => void;
  /** Opens this friend's profile from the ⋯ menu; the item is left out without it. */
  openProfile?: (username: string) => void;
}) {
  const state = useAccountState(account);
  const [messages, setMessages] = useState<FriendMessage[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [failure, setFailure] = useState<string>();
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [loadingEarlier, setLoadingEarlier] = useState(false);
  const [confirmBlock, setConfirmBlock] = useState(false);
  const transcript = useRef<HTMLDivElement>(null);
  const field = useRef<HTMLTextAreaElement>(null);

  const online = state.friends.find((f) => f.username === username)?.online;

  // The newest page every few seconds while the page is visible; it replaces what it covers, earlier pages stay.
  useEffect(() => {
    let stopped = false;
    let first = true;
    let timer: number | undefined;
    setMessages([]); setLoaded(false); setFailure(undefined); setHasMore(false);
    const refresh = async () => {
      if (document.visibilityState === "visible" || first) {
        try {
          const page = await account.thread(username);
          if (stopped) return;
          setMessages((list) => FriendMessageRules.merged(list, page.messages));
          if (first) setHasMore(page.hasMore);
          first = false;
          setLoaded(true);
          setFailure(undefined);
        } catch (error) {
          if (stopped) return;
          setLoaded(true);
          setFailure(PlayerAccountRules.message(SupabaseLite.code(error)));
        }
      }
      if (!stopped) timer = window.setTimeout(() => { void refresh(); }, FriendMessageRules.pollSeconds * 1000);
    };
    void refresh();
    return () => { stopped = true; window.clearTimeout(timer); };
  }, [account, username]);

  const lastID = messages[messages.length - 1]?.id;
  useEffect(() => {
    const element = transcript.current;
    if (element && lastID !== undefined) element.scrollTo({ top: element.scrollHeight, behavior: "smooth" });
  }, [lastID]);

  const loadEarlier = async () => {
    const first = messages[0];
    if (!first) return;
    setLoadingEarlier(true);
    try {
      const page = await account.thread(username, first.id);
      setMessages((list) => FriendMessageRules.merged(list, page.messages));
      setHasMore(page.hasMore);
    } catch { /* stays as it was; the button remains */ }
    setLoadingEarlier(false);
  };

  const send = async (text: string) => {
    if (sending || FriendMessageRules.sanitize(text) === undefined) return;
    setSending(true);
    const typed = text === draft;
    if (typed) setDraft("");
    gameAudio.play("ui-tap");
    const sent = await account.sendMessage(username, text);
    if (sent) setMessages((list) => FriendMessageRules.merged(list, [sent]));
    else if (typed) setDraft(text);
    setSending(false);
    field.current?.focus();
  };

  const lastMine = [...messages].reverse().find((m) => m.fromMe)?.id;
  const menu = [
    ...(openProfile ? [{ title: "View profile", id: "conversation.more.profile", onClick: () => { gameAudio.play("ui-open"); openProfile(username); } }] : []),
    {
      title: `Report ${username}`, id: "conversation.more.report",
      onClick: () => { void account.report(username, [...messages].reverse().find((m) => !m.fromMe)?.body, "message"); },
    },
    { title: "Block", id: "conversation.more.block", destructive: true, onClick: () => setConfirmBlock(true) },
  ];

  return (
    <div className="msocial mconversation">
      <header className="mpanelhead">
        <h2 data-id="conversation.title">{username}</h2>
        <MoreMenu label={`More about ${username}`} id="conversation.more" items={menu} size={17} />
        <CloseButton onClose={onClose} id="conversation.close" />
      </header>
      {online !== undefined && (
        <span className={`mpresence ${online ? "on" : ""}`} data-id="conversation.presence">
          {online && <OnlineDot size={8} />}{online ? "Online now" : "Offline"}
        </span>
      )}
      <div className="mtranscript mscroll" ref={transcript} data-id="conversation.transcript" aria-live="polite">
        <div className="mtranscriptbody">
          {hasMore && (
            <div className="mearlier">
              <Btn kind="secondary" compact sound="ui-tap" id="conversation.earlier" disabled={loadingEarlier} onClick={() => void loadEarlier()}>
                Earlier messages
              </Btn>
            </div>
          )}
          {!loaded ? <div className="mtranscriptnote"><SocialWaiting text="Opening your messages…" /></div>
            : failure !== undefined && messages.length === 0 ? (
              <p className="mcard msocialcard msocialtext" data-id="conversation.error"><SocialGlyph name="wifi" size={16} />{failure}</p>
            ) : messages.length === 0 ? (
              <div className="mtranscriptempty" data-id="conversation.empty">
                <SocialGlyph name="chat" size={30} />
                <p>Say hello to {username}. Messages stay between you two.</p>
              </div>
            ) : null}
          {messages.map((message, index) => (
            <div key={message.id} className="mbubblewrap">
              {(index === 0 || startsNewDay(message.sentAt, messages[index - 1].sentAt)) && <em className="mdayheading">{dayHeading.format(message.sentAt)}</em>}
              <div className={`mbubbleline ${message.fromMe ? "mine" : ""}`} data-id={`conversation.message.${message.id}`}
                aria-label={`${message.fromMe ? "You" : username}: ${FriendMessageRules.shown(message)}`}>
                <p className="mbubble">{FriendMessageRules.shown(message)}</p>
                <small>{timeOfDay.format(message.sentAt)}{message.id === lastMine && message.read ? " · Read" : ""}</small>
              </div>
            </div>
          ))}
        </div>
      </div>
      <div className="mcomposer">
        <div className="mquickreplies">
          {QUICK_REPLIES.map((reply) => (
            <button key={reply} type="button" disabled={sending} data-id={`conversation.quick.${reply}`} onClick={() => void send(reply)}>{reply}</button>
          ))}
        </div>
        <div className="mcomposerrow">
          <textarea ref={field} className="msocialfield" rows={1} value={draft} placeholder={`Message ${username}`} aria-label={`Message ${username}`}
            data-id="conversation.field"
            onChange={(e) => setDraft([...e.target.value].slice(0, FriendMessageRules.maxScalars).join(""))}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); void send(draft); } }} />
          <button type="button" className="msend" aria-label="Send" data-id="conversation.send" disabled={sending || FriendMessageRules.sanitize(draft) === undefined}
            onClick={() => void send(draft)}>
            <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M2.5 11.2 21 3l-6.2 18.5-3.3-7.6zm9 2.7 2.4 5.5L19 5.3z" /></svg>
          </button>
        </div>
      </div>
      {state.notice !== undefined && state.phase === "ready" && <SocialNotice text={state.notice} onDismiss={() => account.setNotice(undefined)} lift={120} />}
      {confirmBlock && (
        <SocialQuestion id="conversation.confirmBlock" title={`Block ${username}?`} confirm="Block"
          message="They're removed from your friends and this conversation closes. You can unblock them in Friends later."
          onCancel={() => setConfirmBlock(false)}
          onConfirm={() => { setConfirmBlock(false); void account.block(username).then(onClose); }} />
      )}
    </div>
  );
}
