# Reviewed engine candidate for 0.1.1 build 5

The owner approved upstream `4825513287ba6c42c32fd205d227f4a5fc44c2f3`
and the separate generated inventory. This replaces pinned
`8aea65ae9ae3c89970fe865e1316105539e097ca`; it does not itself establish native
execution, mobile distribution, hosted multiplayer or physical acceptance.

## Review and validation evidence

- Detection digest: `2e3cd230219d71b550c9874ce4fdcbca433140bcce4e814a33cf6200d4a72b7e`.
- Generated review digest: `80bbfa1ad9e8b8def2eb0e6e10f4ddac0dfd71c183dccba34ecba99a7e851dfa`.
- Reviewed baseline: `910028add4ebbaa0fdb1101e883330f8c8848532`.
- Regeneration run: [35524573624](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35524573624).
- Successful full validation: [35525308284](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35525308284).
- Validation artifact: `10610282341`; ZIP SHA-256
  `89130c58abdba268959fe3571d7573214382a75b859f9545aac039a1a47e6295`.
- Exported app catalogue SHA-256:
  `e73072c6f360fae327281a74255b96d16b79a4eb693038ed7ec84066e76e0ef9`.

The validated catalogue has 31,881 supported names, up from 31,726. No previous
supported names or aliases disappeared. Ninety names select another canonical
printing; their previous printings remain in the raw engine catalogue. Decks
persist names, counts and sections, not those selected printing identifiers.
Additional iOS and Android saved-deck regressions are included in the release
branch and will also run in its exact-source gates.

All 13 maintenance validation commands passed, including exporter checks, 229
tooling tests, native-boundary fixtures, 34 Swift protocol tests, 358 portable
app tests (two intentionally skipped), runtime-manager fixtures, real JVM
regressions, 10 lifecycle scenarios, dependency checks and all five freshly
Swift-resolved included decks. JVM and fixture results are not native-phone
acceptance. The receipt and per-command logs are in the validation artifact.

## Remaining release gates

Rebuild both native engines from the final integrated source, verify iOS product
linkage and signed export, execute fresh Android packaged-engine acceptance,
then publish the verified artifacts. Keep marketing version 0.1.1. Preserve
Game Center and keep dedicated Online disabled while its independent hosting,
database and cross-platform device gates remain outstanding. Render stays on
hold. Update website links and merge only after the applicable checks pass.
