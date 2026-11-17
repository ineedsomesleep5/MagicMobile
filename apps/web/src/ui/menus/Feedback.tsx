/**
 * Send feedback (Options and About): Bug or Feature idea, the note, an optional contact. The account attaches the
 * build and a short device label. Success and failure stay on this page; a failure keeps the note.
 */
import { useState } from "react";
import { FeedbackDraft } from "../../core/account";
import { Pill, Segmented } from "./kit";

export function FeedbackForm({ send }: { send: (kind: string, message: string, contact: string) => Promise<string> }) {
  const [kind, setKind] = useState<"bug" | "feature">("bug");
  const [message, setMessage] = useState("");
  const [contact, setContact] = useState("");
  const [sending, setSending] = useState(false);
  const [outcome, setOutcome] = useState<string>();
  const sent = outcome === "sent";
  const contactOk = FeedbackDraft.contact(contact).ok;
  const canSend = !sending && !sent && FeedbackDraft.message(message) !== undefined && contactOk;
  const edit = () => { if (outcome !== "sent") setOutcome(undefined); };
  const submit = () => {
    if (!canSend) return;
    setSending(true);
    void send(kind, message, contact).then((code) => { setOutcome(code); setSending(false); });
  };
  if (sent) {
    return (
      <div className="mfeedback">
        <p className="mfeedbackstatus ok" data-id="feedback.status">{FeedbackDraft.notice("sent")}</p>
        <Pill id="feedback.another" onClick={() => { setOutcome(undefined); setMessage(""); setContact(""); }}>Send another</Pill>
      </div>
    );
  }
  return (
    <div className="mfeedback">
      <Segmented id="feedback.kind" stretch label="Kind of note" value={kind} onChange={setKind}
        options={[{ label: "Bug", value: "bug" }, { label: "Feature idea", value: "feature" }]} />
      <label>
        <textarea className="mfeedbackbox" value={message} data-id="feedback.message" aria-label="Message"
          placeholder="What happened, or what should MagicMobile do?"
          onChange={(event) => { setMessage(FeedbackDraft.cleanMessage(event.target.value)); edit(); }} />
        <span className="count">{FeedbackDraft.chars(message)}/{FeedbackDraft.MAX_MESSAGE}</span>
      </label>
      <label>
        <input className="mfeedbackbox" value={contact} data-id="feedback.contact" aria-label="Contact" inputMode="email" autoCapitalize="none"
          placeholder="Email or handle, if you want a reply"
          onChange={(event) => { setContact(FeedbackDraft.cleanContact(event.target.value)); edit(); }} />
        {!contactOk && <span className="mfeedbackstatus bad">{FeedbackDraft.notice("invalid_contact")}</span>}
      </label>
      {outcome && outcome !== "sent" && <p className="mfeedbackstatus bad" data-id="feedback.status">{FeedbackDraft.notice(outcome)}</p>}
      <Pill lit id="feedback.send" disabled={!canSend} onClick={submit}>{sending ? "Sending…" : "Send"}</Pill>
    </div>
  );
}
