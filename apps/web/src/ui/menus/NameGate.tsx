/**
 * The first thing a player without a name sees (iOS NameGateView, Android menus/NameGate.kt; Caleb, 2026-10-29: "make
 * them have to login"): a name for every table, or sign in to the Google account that already has one. Covers the menus
 * until the profile has a name; offline, or with the profile server down, the menus open as before (needsName is false).
 */
import { useState } from "react";
import { PlayerAccountRules } from "../../core/account";
import { account, signInWithGoogle, useAccount } from "./accountSession";
import { Btn } from "./kit";

/** The profile is reachable but has no name yet. */
export const needsName = (state: { phase: string; username?: string }) => state.phase === "ready" && state.username === undefined;

export function NameGate() {
  const a = useAccount();
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  if (!needsName(a.state)) return null;
  const busy = saving || a.state.isSigningIn;
  const valid = PlayerAccountRules.isValidUsername(name);
  const save = () => {
    if (!valid || busy) return;
    setSaving(true);
    void account.claim(name).finally(() => setSaving(false));
  };
  return (
    <div className="mnamegate" role="dialog" aria-modal="true" aria-label="Choose your name" data-id="nameGate">
      <div className="mnamegate-body">
        <h2>Choose your name</h2>
        <form className="mcard mnamegate-card" onSubmit={(event) => { event.preventDefault(); save(); }}>
          <input autoFocus aria-label="Player name" placeholder="Player name" value={name} maxLength={20} autoCapitalize="none" autoCorrect="off"
            spellCheck={false} data-id="nameGate.field"
            onChange={(event) => setName(event.target.value.replace(/[^A-Za-z0-9_]/g, "").slice(0, 20))} />
          <p className={a.state.notice ? "warn" : undefined} role="status">{a.state.notice ?? "3–20 letters, numbers or underscores"}</p>
          <Btn kind="primary" id="nameGate.continue" disabled={!valid || busy} onClick={save}>Continue</Btn>
        </form>
        <div className="mnamegate-signin">
          <span className="mcaps">ALREADY HAVE A PROFILE?</span>
          <Btn kind="secondary" id="nameGate.google" disabled={busy}
            onClick={() => { void signInWithGoogle().catch(() => account.setNotice(PlayerAccountRules.message("error"))); }}>Sign in with Google</Btn>
        </div>
      </div>
    </div>
  );
}
