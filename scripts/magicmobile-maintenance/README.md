# XMage maintenance orchestration

Python 3.12+, Git, and a trusted integrated copy of this tooling are required.
Work from the selected MagicMobile root. This directory is outside the guarded
native package; no source-identity guard is weakened. The
[maintenance procedure](../../packages/ondevice-engine/docs/UPSTREAM_MAINTENANCE.md)
remains authoritative for release acceptance.

## Detection and inactive schedule

```sh
python3 scripts/magicmobile-maintenance/upstream.py detect
python3 scripts/magicmobile-maintenance/upstream.py detect --output /tmp/NEW-detection.json
python3 scripts/magicmobile-maintenance/upstream.py detect \
  --upstream /path/to/trusted/mage --candidate EXACT_UPSTREAM_SHA --output /tmp/NEW-local.json
```

Default detection fetches exact old and candidate Git objects from the fixed public
XMage remote into a temporary bare repository, never checking out or executing
upstream code. Local detection performs no fetch. Without --output, only stdout
and stderr change; output files cannot overwrite existing files.

Reports include exact commits, upstream compare URL, changed nearest-POM modules
("(root)" for repository files), changed paths with old/new modes, blob IDs and
SHA-256, dependency/build-file paths, and reviewed patch inputs from both upstream.lock.json
and platform/repository-sources.json. The latter covers all five original repository
Java files; both old and candidate inputs must be regular non-executable source blobs.
--repository-lock defaults to platform/repository-sources.json beside --lock.
Modules use POM
directories present in either commit, not an evaluated Maven reactor. Dependencies are a conservative file
inventory, not transitive resolution; review changed parent/BOM/plugins and notices.
Renames are delete/add. Missing objects, mismatched old blobs and network errors fail.

The manual workflow defaults to detection. A commented activation proposal is
`23 9 * * 1`: Mondays at 09:23 UTC, weekly detection only. To activate later, the
owner must explicitly approve uncommenting schedule and merging that workflow to
the default branch. Change that cron for a different conservative cadence. Nothing
scheduled is active, and a schedule cannot activate candidate mode or publication.

Detection prints a canonical JSON SHA-256 digest. Approval means a human reviewed
that exact report; it is not a signature or automated source-safety proof. Inspect
exact sources with `git show SHA:path` and the full `git diff OLD CANDIDATE`.

## Deduplication

Detection key = canonical SHA-256 of repository, old SHA and candidate SHA.
Optional --records DIRECTORY reads DIRECTORY/<dedupKey>.json:

```json
{"dedupKey":"<key>","detectionDigest":"<digest>","status":"reviewed","url":"<optional review URL>"}
```

Records are never auto-written. Malformed/conflicting records fail. The owner can
retain detected/reviewed/prepared/rejected/published decisions in durable storage.
A future scheduled publisher would need serialized claims and atomic records;
artifact retention is not a durable dedup database. The implemented explicit
publisher instead reconciles PRs by a stable upstream-candidate branch.

## Prepare a fresh reviewed candidate

```sh
python3 scripts/magicmobile-maintenance/upstream.py prepare \
  --project /path/to/clean/committed/MagicMobile --upstream /path/to/trusted/mage \
  --report /tmp/NEW-detection.json --approve-digest REVIEWED_DETECTION_DIGEST \
  --destination /path/to/NEW-candidate
```

Preparation rechecks the full report, refuses no-update/dirty-source/occupied-target
cases, and exports fresh project and upstream trees. It rejects symlinks, unsafe
paths and submodules. It applies the existing trusted exact-signature transformers
without fuzzy patching, verifies original blobs, stamps patched outputs, updates
both candidate source locks and all four code identity locations (XmageEngine,
CommanderSetExporter, CardMetadataExporter, export_ios_catalogue), and creates the exact
upstream HEAD needed by bootstrap. It never executes upstream programs.
implementation-status.json is explicitly upstream-candidate-unverified, with null
current commit/artifact claims and unrun verification. Its complete original record,
including prior candidate artifacts and verification, is preserved under the labeled
historical previousStatus.record. Fixture manifests and historical documentation
remain unchanged. The
repository-source lock bytes are hash-bound in the candidate receipt and rechecked
before generated review.

The trusted committed shipped catalogue must identify the old pinned SHA. Its
bytes are copied and hash-bound in maintenance-candidate.json for inventory review.
A failure can leave an inspectable partial tree without a success manifest; use a
new destination after resolving it. No existing work is deleted. The candidate is
an exported project tree, not a commit/branch; the owner later integrates reviewed
changes into a clean Git checkout.

## Generate first, review, then validate

```sh
# Preview; no build:
python3 scripts/magicmobile-maintenance/upstream.py regenerate /path/to/NEW-candidate
# Explicit execution on an authorized disposable builder:
python3 scripts/magicmobile-maintenance/upstream.py regenerate /path/to/NEW-candidate --execute
python3 scripts/magicmobile-maintenance/upstream.py generated-review /path/to/NEW-candidate
```

Regeneration runs only build_jvm.sh and retains its log. This produces registry,
catalogue and eligibility outputs without testing them against old expected hash
pins. Tooling, catalogue and real-engine gates run only after the separate review.

maintenance-review.json and maintenance-inventory.json retain the review artifacts.
The review digest covers generated hashes, registry fingerprint and an inventory
comparison against the trusted shipped baseline: exact printing additions/removals,
newly excluded and newly resolvable names, and before/after exclusion statistics.
Normalization uses trusted port code without calling its old-pin export check.
The comparison is Commander-exported inventory, not historical full raw registry
or semantic card-rule parity. Review the raw generated reports/metadata and
dependency resolution too. The baseline and normalizer hashes are included.

```sh
python3 scripts/magicmobile-maintenance/upstream.py accept-generated /path/to/NEW-candidate \
  --approve-digest REVIEWED_GENERATED_AND_INVENTORY_DIGEST
# Preview then explicit post-review execution:
python3 scripts/magicmobile-maintenance/upstream.py validate /path/to/NEW-candidate
python3 scripts/magicmobile-maintenance/upstream.py validate /path/to/NEW-candidate --execute
```

Acceptance updates all four exporter hash constants only after matching that
separate digest. Validation requires matching acceptance and regeneration receipts.
It executes, in order:

1. Catalogue self-test, export with reviewed pins, and exact regeneration check.
2. Tooling/protocol fixture suite and C native-boundary tests.
3. Swift protocol tests, then app tests exporting fresh bundled decks.
4. Swift-close and runtime-manager native-ABI lifecycle fixtures, then the real-engine
   suite and test_seeded_soak.py.
5. Compiled desktop-dependency audit.
6. Real XMage validation of all five freshly Swift-exported bundled decks.

The soak has ten bounded driver-seed configurations: 2/4 humans and 1/2/3 MAD,
opening/live teardown. These are not XMage RNG seeds. The root owns these scripts.
Failures stop immediately and no success receipt is written. Validation checks
exactly the five deck filenames and records their hashes. Old expected hashes are
never mechanically replaced merely to silence a failing test.

Use a disposable unprivileged macOS builder with JDK 21, Maven and the repository's
compatible Swift/Xcode. The manual candidate workflow specifies macos-26-intel,
Xcode_26.6 and Temurin 21, plus Python 3.12. Tool availability is checked before
building; no substitute paid runner or automatic tool installation is performed.
No signing secrets, repository write tokens or privileged/shared caches belong in
this job. Commands receive a stripped environment and a candidate-local isolated
HOME; its Maven cache remains because classpaths reference those JARs. Environment
filtering is not an OS sandbox. The build home is not uploaded.

Git discovery is bounded by GIT_CEILING_DIRECTORIES at the exported candidate root,
so a candidate inside another checkout cannot claim that enclosing repository's
HEAD. The real nested upstream checkout remains discoverable. Root-owned soak and
desktop-dependency provenance reporting support exported trees with an explicit
unverified/null MagicMobile HEAD. The root-owned desktop-dependency adjustment
keeps the jdeps audit enabled for exported sources. No commit identity is fabricated.

Workflow mode=candidate requires an exact upstream SHA and reviewed detection digest.
It prepares and generates review artifacts. On a subsequent manual candidate run,
supply reviewed_generated_digest to regenerate fresh outputs, check the same
reviewed inventory/hash digest, accept pins and run post-review validation.
Changes to baseline or outputs require new review. There is no automatic approval.
The exported tree is not the final MagicMobile commit and cannot satisfy the
downstream exact-commit native gate until integrated and committed by the owner.

## Explicit publication and downstream dispatch

```sh
# Local plan only:
python3 scripts/magicmobile-maintenance/upstream.py publish \
  --project /path/to/clean/MagicMobile --candidate-commit EXACT_MAGICMOBILE_SHA --base main
# Future explicit permission to push and create/update a draft:
python3 scripts/magicmobile-maintenance/upstream.py publish \
  --project /path/to/clean/MagicMobile --candidate-commit EXACT_MAGICMOBILE_SHA --base main --execute
```

The target is fixed to ineedsomesleep5/MagicMobile. Branch identity is
maintenance/xmage-<exact upstream SHA from the committed lock>, so reviewed follow-up
MagicMobile commits update one candidate PR. The command requires exact clean HEAD.
It reuses an existing exact PR, or advances only an open draft whose previous head
is a local ancestor. It pushes without force and with hooks disabled. Missing
ancestry, non-fast-forward updates, closed/non-draft decisions and conflicting PRs
fail for owner reconciliation. No merge, release, title/body rewrite, reopen or
native acceptance is implied. Concurrent pushes may fail; retry rechecks PR state.
A separate credential-bearing process runs this trusted script; it executes no
candidate code. No publisher job or automatic publication is enabled.

Maintenance branches do not match the downstream push filter, and bot pushes may
not trigger another workflow. Explicit dispatch is implemented:

```sh
python3 scripts/magicmobile-maintenance/upstream.py dispatch-non-sim \
  --project /path/to/clean/MagicMobile --candidate-commit EXACT_MAGICMOBILE_SHA
# Future explicit dispatch authorization only:
python3 scripts/magicmobile-maintenance/upstream.py dispatch-non-sim \
  --project /path/to/clean/MagicMobile --candidate-commit EXACT_MAGICMOBILE_SHA --execute
```

This targets magicmobile-issue4-nonsimulator.yml in the fixed repository, verifies
the remote candidate branch still equals the exact requested commit, then dispatches
that ref. It does not claim a successful run. Dispatch by branch is not atomic with
a subsequent branch update: the root-owned scripts/magicmobile-native-gate/ must
reject every run whose headSha differs, require successful exact non-simulator
evidence, and require candidate SHA = github.sha for native activation. Never
substitute upstream XMage SHA for the MagicMobile commit. No duplicate expensive
native gate is implemented here. Workflow availability on the default branch and
Actions permission for the explicit dispatch are external activation prerequisites.

## Verification and limitations

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/magicmobile-maintenance -p 'test_*.py'
ruby -e 'require "yaml"; p YAML.load_file(".github/workflows/magicmobile-upstream-maintenance.yml")["jobs"].keys'
```

Ruby uses its existing YAML parser; no dependency installation is required. YAML
parsing does not establish hosted Actions semantics or runner availability.

Tests use local synthetic Git fixtures and mocked build/publish/dispatch commands.
They cover source/digest/freshness failures; inventory additions/removals/exclusions
and baseline tampering; reviewed stage ordering, fail-stop behavior and five-deck
receipts; exact target, draft fast-forward publication and closed-decision refusal;
and dispatch preview, remote-SHA mismatch and explicit mocked dispatch.
The actual prepare_mobile_repository.py guard/export transformation also runs on
synthetic local original-source fixtures, proving the coordinated repository lock
accepts the reviewed candidate and rejects old pins and source tampering without
a mocked builder or JVM. Production regeneration, dependency compatibility, real JVM/Swift/C execution,
hosted workflow behavior, native/device acceptance and external publishing remain
unverified. Hash receipts alone cannot prove outputs were produced by a particular
build; preserve hosted provenance and apply the independent exact-SHA gate.

No live upstream advancement, full real JVM build, schedule activation, dispatch,
external write, commit or push was performed during implementation.
