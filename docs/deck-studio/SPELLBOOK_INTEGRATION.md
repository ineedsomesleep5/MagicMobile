# Deck Studio: Commander Spellbook integration

Continuation of PR #10 from 67ec420ef15a2f51166ea6bae1984c42c162dae0. The approved Deck Studio 2.0 plan remains the scope; this slice adds the optional Combos surface without modifying XMage, native archive identity, signing, or release configuration.

## Provider contract checked September 16, 2026

- Official public API and usage guidance: https://backend.commanderspellbook.com/
- Public lookup: https://backend.commanderspellbook.com/find-my-combos
- Attribution and open-source information: https://commanderspellbook.com/about/
- Upstream reference inspected: SpaceCowMedia/commander-spellbook-backend at ec0e9d6ab436311f617127f821c904ffb3129f45; backend/spellbook/views/find_my_combos.py and backend/common/serializers.py.

Use the documented camelCase response, nullable count, all six result groups, POST JSON main/commanders entries with card and quantity, and explicit pagination. The service requests sparse unauthenticated calls, identification through User-Agent, credit, and handling of HTTP 429. Its public API is distinct from EDHREC's website; no EDHREC endpoint is queried by this integration.

## Behavior

Ideas now has Insights / Combos / EDHREC. A combo request requires an explicit confirmation for the exact resolved main deck and commanders. Titles, notes, sideboard, companion and maybeboard sections are not sent. No observation, cache read, tab change or draft edit starts an HTTP lookup. Each request fetches at most one page; Load next page is a separate user action.

The client sends no credentials/cookies, rejects redirects and untrusted pagination URLs, bounds streamed response size and cache size, spaces calls, and honors Retry-After. A clear operation or cancellation prevents a late request from restoring cached data. Results are cached on this device, dated, and never treated as fresh automatically. A disk-cache failure does not discard a successful lookup.

All named pieces present is not combo execution. Flexible templates, unknown cards, extra copies, changed commander roles, added colors, spoilers and non-legal provider status are distinguished. One-card-away additions require one absent named card, the current commander's known color identity, and a card resolved in the shipped catalogue. A fresh model check precedes the undoable addition to main deck or maybeboard. The app does not infer game-state prerequisites, silently replace cards or certify whole-deck Commander legality.

## Verification

Run bash scripts/deck-studio/test-spellbook.sh. Production Foundation code is compiled with warnings as errors. Tests use synthetic schema fixtures, injected HTTP, an intercepting URLProtocol for the production bounded streaming delegate, a temporary local cache, and no live provider calls. Combine model race/approval tests execute on macOS; Linux reports them as skipped. The existing test-core.sh invokes this suite in the established non-simulator PR gate.

The previous checkpoint passed workflow 35142246964 (Swift, app/test SDK compilation, native boundary/tooling, real XMage JVM) and CI 35142246957. Those results do not validate this new continuation. New hosted results must be recorded separately after publication.

Still required: hosted macOS/Apple SDK checks on the new source, a deliberate on-phone live Spellbook lookup and pagination/offline/cancel testing, and the remaining Deck Studio plan phases. No simulator, device, TestFlight, live POST integration, exhaustive combo coverage, or full-plan completion is claimed here.
