"use client";

import { useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { createSupabaseBrowserClient } from "@/lib/supabase/browser";

export function AccountClient() {
  const [email, setEmail] = useState("");
  const [user, setUser] = useState<User>();
  const [status, setStatus] = useState<"loading" | "ready" | "sending" | "sent" | "error">("loading");
  const [message, setMessage] = useState<string>();

  useEffect(() => {
    try {
      const client = createSupabaseBrowserClient();
      void client.auth.getUser().then(({ data }) => {
        setUser(data.user ?? undefined);
        setStatus("ready");
      });
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Cloud sign-in is not configured.");
      setStatus("error");
    }
  }, []);

  const signIn = async () => {
    setStatus("sending");
    setMessage(undefined);
    try {
      const client = createSupabaseBrowserClient();
      const { error } = await client.auth.signInWithOtp({
        email: email.trim(),
        options: { emailRedirectTo: `${window.location.origin}/auth/callback?next=/decks` }
      });
      if (error) throw error;
      setStatus("sent");
      setMessage("Check your email for a secure MagicMobile sign-in link.");
    } catch (error) {
      setStatus("error");
      setMessage(error instanceof Error ? error.message : "Sign-in link could not be sent.");
    }
  };

  const signOut = async () => {
    const client = createSupabaseBrowserClient();
    await client.auth.signOut();
    setUser(undefined);
    setStatus("ready");
  };

  return (
    <section className="account-screen">
      <div className="account-panel">
        <span className="account-rune" aria-hidden="true">M</span>
        <p className="home-eyebrow">MagicMobile account</p>
        {user ? (
          <>
            <h1>Your collection travels with you.</h1>
            <p>Signed in as <strong>{user.email ?? "Commander player"}</strong>. Your cloud decks are available on web and iPhone.</p>
            <button className="home-button" type="button" onClick={() => void signOut()}>Sign out</button>
          </>
        ) : (
          <>
            <h1>Keep every spellbook in sync.</h1>
            <p>Enter your email and we’ll send a password-free sign-in link.</p>
            <label>Email address<input type="email" autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" /></label>
            <button className="home-button home-button-primary" type="button" disabled={!email.trim() || status === "sending" || status === "loading"} onClick={() => void signIn()}>
              {status === "sending" ? "Sending…" : "Send sign-in link"}
            </button>
          </>
        )}
        {message ? <p className={status === "error" ? "cloud-error" : "cloud-success"} role="status">{message}</p> : null}
      </div>
    </section>
  );
}
