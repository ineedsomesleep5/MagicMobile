# MagicMobile 0.1.1 — build 5

Marketing version remains **0.1.1**; shared visible build is **5**. Android installation versionCode is **2026092001**. **Release is on hold for an approved engine update.** The pre-upgrade candidate reused existing native engines; its test results below do not validate the new engine.

On September 20, upstream XMage was 190 commits ahead of our pin. The owner approved exact candidate `4825513287ba6c42c32fd205d227f4a5fc44c2f3` and detection digest `2e3cd230219d71b550c9874ce4fdcbca433140bcce4e814a33cf6200d4a72b7e`. Isolated regeneration is tracked in [maintenance run 35524573624](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35524573624). Both native engines, catalogue and server package must be rebuilt and checked before release; starting this run is not update acceptance.

## Scope and availability

- iOS retains Game Center and offline AI. Android retains offline AI and the previous build's deck, artwork, and battlefield features.
- Both apps include the dedicated-server online client and lobby foundation. With no verified server endpoint configured, Online clearly says **coming soon** and does not expose sign-in, create, or join actions.
- The server runs the real pinned XMage engine with Supabase authentication, private seat-bound views, exact build matching, validated Commander decks, invite-code lobbies, readiness checks, and bounded request handling.
- Client recovery distinguishes a lost reply from a failed create/join request. Authentication refresh and credential storage are protected; credential-bearing redirects are rejected.
- A server restart currently interrupts its games. Leaving an active online game ends it for everyone. Durable match recovery, public quick matchmaking, and host migration are not included.

## Verification

- Fresh current JVM core checks: 419 assertions; native-boundary checks: 88 assertions. Synthetic server contract checks passed separately.
- Real-engine HTTP tests reached normal priority after mulligans in two- and four-human Commander matches. They checked seat isolation, private hands, prompt ownership, and response retry semantics. Representative included decks passed with both a 2 GB and a 256 MB JVM heap. These are local opening-game tests, not full-match or cloud-capacity acceptance.
- Android: 30 unit tests and signed release compilation passed. All 10 instrumentation checks passed on the exact signed APK, including a complete native Commander game (14 turns, 70 responses), distinct AI decks, ten native reopen cycles, and unavailable Online behavior. Installed APK SHA-256 matched `4b9ab80d409d7481e68fae62185b658507bf516cebd877cc66e2ee14dfb24c33`. Evidence: `build_output/android-acceptance/instrumentation-MlaoQi`. Physical-phone acceptance and release delivery remain separate gates.
- iOS: 22 session and 10 online API runtime tests passed. The setup UI regression passed AI → Game Center → pending Online → Game Center → AI; the pending-state screenshot was inspected. Final native archive/signing checks and live Game Center gameplay remain separate gates.
- Server review added passing regressions for lost Supabase membership, failed cleanup retaining engine capacity, expiry retries, failed-start cleanup, and joining existing lobbies at the lobby limit. Portable runtime packaging preserves ordered dependencies and verifies payload checksums; Linux/free-host acceptance remains pending.
- Follow-up bridge fixes moved slow deck validation outside the global monitor, rejected overdue admission before database mutation, and bounded complete Supabase responses by 10 seconds and 256 KiB. The synthetic suite passed the existing transport/security lifecycle plus 6 failure, 7 admission, 6 response and 5 configuration checks. These fixes are not in the published pre-upgrade trial runtime; updated-engine real-game acceptance must rerun. Synchronous game initialization remains serialized; database reply-loss still uses current-lobby recovery.
- Release helpers: 10 Node and 20 Python checks passed.
- Local PostgreSQL-compatible migration tests cover expected-match leave, exact engine-build matching, reused waiting seats, and the authenticated public lobby lifecycle. The migration has not been applied to production. Actual concurrent PostgreSQL-session validation remains required before online deployment.

## Deployment gates

No live cross-platform availability is claimed. Oracle ARM capacity attempts failed. The isolated Render free-tier trial built but failed its real-engine HTTP admission test with a 60-second request timeout; this does not establish that memory or the bridge alone caused the failure. The owner put further Render deployment attempts on hold. No paid upgrade was made and production Supabase was not connected to the trial.

The [self-host launcher](../apps/multiplayer-server/selfhost/README.md) is published as a diagnostic prerelease, pinned to the pre-upgrade runtime. Its seven isolated launcher regressions passed; Windows execution is not yet verified. Before enabling Online: provision a suitable host, verify TLS and authentication, apply the reviewed database migration, validate concurrent matchmaking, and complete real iOS/Android two- and four-player gameplay/reconnect checks on that host.

Signed artifacts, store availability, public Android download verification, and website delivery will be recorded after they succeed. Physical-device acceptance is not implied by compilation, fixture tests, or an upload.
