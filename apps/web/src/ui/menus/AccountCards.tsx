/**
 * The profile's account cards (iOS AccountSignInCard, PlayerProfileView.privacyCard): "Sign in" with Google opens the
 * profile of that Google account here (or keeps this browser's profile when the account has none yet), so the same name,
 * friends, rank and decks open on every phone and browser; signed in, it shows the account and Sign
 * Out (asked first in a small glass question, never a browser dialog). Then who may see the profile. Apple sign-in waits
 * for a web Services ID on the Apple account, so only Google is offered here.
 */
import { useState } from "react";
import { PlayerAccountRules, ProfileVisibility } from "../../core/account";
import { LinkedIdentity } from "../../core/supabaseLite";
import { gameAudio } from "../audio";
import { account, signInWithGoogle, useAccount } from "./accountSession";
import { Btn, Pill } from "./kit";

function CardTitle({ text }: { text: string }) {
  return <header className="mprofilesection"><h3>{text.toUpperCase()}</h3></header>;
}

export function AccountSignInCard() {
  const a = useAccount();
  const { phase, linkedIdentities, isSigningIn } = a.state;
  const [asking, setAsking] = useState(false);
  const busy = isSigningIn || phase === "loading";
  return (
    <section className="mcard mprofilecard" data-id="profile.accountCard">
      <CardTitle text={linkedIdentities.length === 0 ? "Sign in" : "Your account"} />
      {linkedIdentities.length === 0 ? (
        <>
          <p className="mprofilenote">Your name, friends, rank and decks follow your Google account to every phone and browser.</p>
          <Btn kind="primary" id="profile.account.google" disabled={busy}
            onClick={() => { void signInWithGoogle().catch(() => account.setNotice(PlayerAccountRules.message("error"))); }}>
            <svg className="mgoogle" viewBox="0 0 24 24" aria-hidden="true"><path d="M21.6 12.2c0-.7-.1-1.4-.2-2H12v3.8h5.4a4.6 4.6 0 0 1-2 3v2.5h3.2c1.9-1.7 3-4.3 3-7.3z" fill="#fff" /><path d="M12 22c2.7 0 5-.9 6.6-2.4l-3.2-2.5c-.9.6-2 1-3.4 1-2.6 0-4.8-1.8-5.6-4.1H3.1v2.6A10 10 0 0 0 12 22z" fill="#fff" opacity=".85" /><path d="M6.4 14c-.2-.6-.3-1.3-.3-2s.1-1.4.3-2V7.4H3.1a10 10 0 0 0 0 9.2z" fill="#fff" opacity=".7" /><path d="M12 6c1.5 0 2.8.5 3.8 1.5l2.9-2.9A10 10 0 0 0 3.1 7.4L6.4 10C7.2 7.7 9.4 6 12 6z" fill="#fff" opacity=".9" /></svg>
            Sign in with Google
          </Btn>
        </>
      ) : (
        <>
          {linkedIdentities.map((identity) => (
            <p key={`${identity.provider}${identity.email ?? ""}`} className="midentity">
              {identity.email ? `${LinkedIdentity.title(identity)} · ${identity.email}` : LinkedIdentity.title(identity)}
            </p>
          ))}
          <div><Btn kind="secondary" compact id="profile.account.signOut" onClick={() => setAsking(true)}>Sign Out</Btn></div>
        </>
      )}
      {a.state.notice && <p className="mprofilenote warn" role="status">{a.state.notice}</p>}
      {asking && (
        <div className="mquestion" role="alertdialog" aria-label="Sign out in this browser?">
          <b>Sign out in this browser?</b>
          <p>Your profile stays on your account. This browser starts a new one until you sign in again.</p>
          <div>
            <Btn kind="secondary" compact onClick={() => setAsking(false)}>Cancel</Btn>
            <Btn kind="danger" compact onClick={() => { setAsking(false); void account.signOut(); }}>Sign Out</Btn>
          </div>
        </div>
      )}
    </section>
  );
}

/** Who may open this profile: Public (the default), Friends only or Private; the server enforces it. */
export function PrivacyCard() {
  const a = useAccount();
  const { phase, username, visibility, visibilityKnown } = a.state;
  const signedIn = phase === "ready" && username !== undefined;
  const note = !signedIn ? "Choose your player name in Friends to share a profile with other players."
    : !visibilityKnown ? "Privacy settings arrive with the next server update. Until then your profile stays as it is."
    : ProfileVisibility.detail(visibility);
  return (
    <section className="mcard mprofilecard" data-id="profile.privacyCard">
      <CardTitle text="Who can see your profile" />
      <div className={`mprivacy ${signedIn && visibilityKnown ? "" : "off"}`} role="radiogroup">
        {ProfileVisibility.all.map((option) => (
          <button key={option} type="button" role="radio" aria-checked={visibility === option} className={visibility === option ? "on" : ""}
            disabled={!signedIn || !visibilityKnown} data-id={`profile.privacy.${option}`}
            onClick={() => { if (option !== visibility) { gameAudio.play("ui-tap"); void a.setVisibility(option); } }}>
            {ProfileVisibility.title(option)}<i className="mtabbar" />
          </button>
        ))}
      </div>
      <p className="mprofilenote" data-id="profile.privacy.note">{note}</p>
      {signedIn && a.state.profilesAvailable && username && (
        <div><Pill id="profile.privacy.preview" onClick={() => window.dispatchEvent(new CustomEvent("mm:open-profile", { detail: username }))}>See it as others do</Pill></div>
      )}
    </section>
  );
}
