# Commander polish candidate 0.1.0 (2026091601)

## Intended tester notes

- Deck Studio now opens on your deck, with compact artwork rows, search/filter,
  grouping/sorting, quantity edits, undo and local draft recovery.
- Paste plain-text exports from Moxfield or Archidekt, review quantities and
  commander/sideboard sections, and keep unresolved names as an editable draft.
  Printing and category annotations are shown during review. Import confirmation
  stays accessible below the form instead of being buried after all card rows.
- Improved local startup/validation reports and historical-report labeling.
- Card-backed ability choices, richer stack/source details and inspectable logs.
- Centered phase cues, life-change feedback, stronger playable-card outlines,
  and improved expanded-hand scrolling in portrait and landscape.
- Updates menu distinguishes this installed engine from upstream XMage news.

Please test imported Commander and partner decks, invalid-deck reports, manual
mana-rock/convoke payments, large sacrifice selections, card selection/search,
hand scrolling/inspection, phase changes and life gains/losses in both orientations.
Share diagnostics only by explicit choice; reports can include card information.

## Deliberate limitations

- Public deck links depend on provider availability. Text paste does not require
  provider authentication or network access for name resolution.
- EDHREC uses an explicit copy-deck/open-website flow, not undocumented scraping
  or a claim of native personalized recommendations.
- No Rive dependency was added. Its CLI was researched separately; commercial
  export clarity and device profiling are prerequisites to adopting it.
- Simulator fixtures and JVM regressions are not physical-iPhone gameplay proof.
- XMage can offer starting a cast that still cannot be fully paid (covered by the
  Tribunal/Jaspera regression). Highlights are engine-offered actions, not a
  client guarantee of affordability; manual payment and cancellation remain available.

## Release evidence in progress

- Selected checkout: MagicMobile-runtime-hardening, codex/native-runtime-hardening.
- Frozen engine: fca652a80f643d4a88fe2f8f0ac781be1fd096a4.
- Same-SHA non-simulator gate: 35046969413, success.
- Full native workflow: 35048126381, pending at preparation.
- Build number prepared via repository helper; live ASC query found no matching
  2026091601 build before signing. Recheck immediately before upload.
- Portable tests: 274, one optional live-provider skip, zero failures.
- Final SDK unit run: 477, one optional skip, zero failures.
- UI matrix plus targeted repairs cover 53 distinct cases: both provider paste
  flows, board gestures, exact ability submission, phase/life feedback, recovery,
  editing and keyboard behavior. Final deck-tool rerun: three tests, zero failures.
- Paired native artifact/product link, signing, upload, processing and requested
  beta-group availability remain separate uncompleted gates.

No delivery UUID or physical-device acceptance is implied by this candidate note.
