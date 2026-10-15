# App audit, October 2026: iOS build 38 and Android build 22

A reverse-engineering pass over the builds people actually installed, done with REA (rea-agents 6.5.0)
on 2026-10-14. Caleb approved using REA on MagicMobile's own app and engine only. No other app was
inspected.

The audit covers the shipped artifacts, not the source tree. Source was read only to explain what the
binaries showed. Neither artifact was executed, and nothing was run on a device or simulator. Findings
are split into **observations** (seen in the artifact, with an evidence ID), **inferences** (reasoned
from observations, not confirmed at runtime) and **unknowns** (what would settle them).

| Artifact | SHA-256 |
|---|---|
| `MagicMobile.ipa`, iOS 0.1.1 (38), TestFlight export | `6c9ebebaaf472e8c06be9e2f9ff764c6f6b73566fd986280192bb90458b87056` |
| Main executable `Payload/MagicMobile.app/MagicMobile` (arm64, iOS 17.0+, SDK 27.0) | `db9448136d358a952285e1d57d668d18d096c24051630d5f185c6837401faa58` |
| `MagicMobile-Android-0.1.1-build22.apk` (GitHub release `android-v0.1.1-build.22`) | `e997bd38e7a8d5a1b142bcd73d1cbd0b560d5130a945f0b6d4375b409127bc4a` |
| `lib/arm64-v8a/libmmengine.so` from that APK | `bf6e033369a11069b102f6128c7797591a6566f33d57ee322149329cc1733d34` |

## Summary

- **The iOS privacy manifest was missing three required-reason API categories** (file timestamp,
  system boot time, disk space). App Store Connect refuses such builds at App Store submission.
  Fixed in [#155](https://github.com/ineedsomesleep5/MagicMobile/pull/155), with a test that scans
  the sources.
- **No secrets in either build.** The only credentials-like strings are public by design: the
  Supabase project URL, the publishable key and the Google OAuth client IDs. No build-machine paths
  leak into either binary.
- **Release builds are locked down.** Android isn't debuggable, has backups and cleartext traffic off,
  and every UI-test and design-preview hook is ignored outside debug builds. iOS is signed for
  distribution with `get-task-allow` false and links no third-party SDKs.
- **ML Kit is still in use**: Deck Studio's decklist-photo import on Android. It brings Google's
  usage telemetry with it, which the site's privacy policy ("no analytics") doesn't mention.
  The policy also predates Apple/Google sign-in (email) and ranked.
- **Size:** the engine is about two thirds of each download: 202 MB of AOT code plus a 167 MB GraalVM
  image heap. On the app side, the rank-badge spin frames are the largest single win, at about 7 MB
  per platform. Six unused Android backgrounds (1.4 MB) are removed in
  [#156](https://github.com/ineedsomesleep5/MagicMobile/pull/156).

## Prioritized fix list

| # | Priority | Platform | Fix | Size or effect | Status |
|---|---|---|---|---|---|
| 1 | P0 | iOS | Declare FileTimestamp C617.1, SystemBootTime 35F9.1, DiskSpace E174.1 in `PrivacyInfo.xcprivacy` | Unblocks App Store submission | [#155](https://github.com/ineedsomesleep5/MagicMobile/pull/155) |
| 2 | P1 | both + site | Bring the privacy policy, the iOS manifest's collected data types and the App Store privacy labels up to date: optional email from Apple/Google sign-in, ranked match records and ranks, Android ML Kit telemetry | Accurate disclosure | Needs Caleb's wording; touches the live site and App Store Connect |
| 3 | P1 | Android | Decide on ML Kit: keep and disclose; keep but initialise lazily (remove `MlKitInitProvider`); or move to the Play Services text-recognition model | Lazy init: less work at launch. Unbundled: about 5.7 MB smaller APK, 12.6 MB less installed | Needs a decision |
| 4 | P2 | both | Rank-badge spin animations: 6 tiers × 32 frames stored lossless. Use lossy frames with alpha, fewer frames, or spin one badge at draw time | iOS about 7.2 MB, Android 6.8 MB | Proposal |
| 5 | P2 | Android | `tavern_pass_flip_*`: 48 lossless frames | 2.2 MB | Proposal |
| 6 | P2 | both | Retired battlefield skins (moss, arena, tide, wood, ember) still ship. Keep only what UI tests pin (`arena`) or move test boards into test-only assets | iOS 2.75 MB, Android 1.74 MB | Needs a test plan |
| 7 | P2 | both | App icon sources are very heavy: iOS 1024 px icon 2.8 MB in `Assets.car`, Android `magicmobile_icon` 1.96 MB PNG | Estimated 1.5–2.5 MB per platform after re-encoding | Proposal |
| 8 | P2 | Android | Delete six unreferenced legacy backgrounds | 1.43 MB | [#156](https://github.com/ineedsomesleep5/MagicMobile/pull/156) |
| 9 | P3 | engine | Measure, then reduce, the 4.5 million load-time relocations in `libmmengine.so`. Options: relative image-heap references in the native-image build, or RELR (needs minSdk 28, currently 26) | Up to 12 MB of relocation data. Possible launch time and memory, still unmeasured | Engine release only |
| 10 | P3 | engine | Generate a GraalVM build report (`--emit build-report`) to see what fills the 167 MB image heap and 202 MB of code before trying `-Os` or trimming | Unknown until measured | Engine release only |
| 11 | P3 | Android | `useLegacyPackaging = true` means the 381.6 MB engine is extracted at install, next to the APK that already holds it compressed. Keep it for GitHub downloads; revisit for Play (AAB) | Installed size versus download size | Note for the Play track |
| 12 | P3 | both | Debug fixtures still compile into release: Android keeps all of `io.magicmobile.**` (DesignPreviewHost, GameBoardPreviewFixtures, SocialFixtures); iOS keeps `SoundLabView` (intentional) and two env checks. All are inert | Small | Optional |

Engine items (9, 10) are recommendations only. Engine changes ship in their own release, never
bundled with app features, and follow packages/ondevice-engine/AGENTS.md.

## 1. iOS build 38

### Observations

**Layout** (REA `inspect_macho`, `ev_5c4e1dec…`; segments view `ev_cded3057…`). The engine is
linked statically into the single executable (386,178,832 bytes, 106,855,605 compressed in the IPA):

| Segment / section | Bytes |
|---|---|
| `__TEXT,__text` (Swift app + GraalVM AOT code) | 212,305,192 |
| `__DATA,__svm_heap` (GraalVM image heap) | 167,280,640 |
| `__TEXT,__unwind_info` | 1,129,800 |
| `__LINKEDIT` | 1,728,272 |
| `__TEXT,__swift5_typeref` | 2,077,949 |

Build metadata (`ev_5bfedfad…`): platform iOS, minimum 17.0, SDK 27.0, ld 27037.1. The 58 dependencies
(`ev_6501e121…`) are all system frameworks or Swift overlays. Frameworks linked: Foundation, UIKit,
SwiftUI, SceneKit, Metal, GameKit, AuthenticationServices, Vision, PhotosUI, MetricKit, CoreMotion,
WebKit, Charts, CryptoKit, AVFoundation/AVFAudio, Security, ImageIO, Accessibility, Combine,
CoreTransferable. No third-party framework or dylib is embedded.

**IPA contents** (REA `inspect_artifact`, `ev_21785137…`, inventory `ev_ffda0842…`, 90 entries):

| Group | Compressed | Uncompressed |
|---|---|---|
| Main executable | 106.9 MB | 386.2 MB |
| `Assets.car` | 23.9 MB | 24.2 MB |
| `Symbols/` (dSYM upload for Apple; not installed on phones) | 19.0 MB | 81.1 MB |
| Music (8 tracks) | 9.4 MB | 9.6 MB |
| Card catalogue (`ondevice-catalogue.json.lzfse`) | 2.3 MB | 2.3 MB |
| Grimoire videos (4 × mp4) | 2.0 MB | 2.0 MB |
| D20 3D (glb + json) | 1.0 MB | 1.1 MB |
| Sound effects | 1.0 MB | 1.3 MB |
| Fonts (Cormorant SC Bold) | 0.2 MB | 0.8 MB |

**Asset catalog** (REA `inspect_asset_catalog`, `ev_5d39494a…`, 459 renditions, 24.1 MB):

| Group | Bytes | Renditions |
|---|---|---|
| `tavern-rank-*` (of which spin frames 7.17 MB: 6 tiers × 32 frames, 300×300 @3x, lossless `deepmap2`) | 8,322,133 | 198 |
| `battlefield-tavern-*` (pad, portrait, landscape JPEG) | 3,949,386 | 3 |
| `AppIcon` (1024 px rendition alone 2,827,817) | 2,929,646 | 23 |
| other `tavern-*` UI materials | 2,758,219 | 79 |
| retired `battlefield-{moss,arena,tide,wood,ember}` | 2,747,143 | 5 |
| `tavern-room-*` parallax layers | 1,193,087 | 6 |

**Info.plist** (REA `inspect_plist`, `ev_4c468c59…`): bundle `com.calebfeliciano.magicmobile`,
0.1.1 (38), `ITSAppUsesNonExemptEncryption` false, URL scheme `magicmobile`, one usage string
(`NSPhotoLibraryUsageDescription`, for the player icon), `MagicMobileEngineMode` embedded-xmage.

**Signature** (REA `inspect_signature`, `ev_231d4082…`): iPhone Distribution, team 82HPAY85M8.
Entitlements: `get-task-allow` false, `beta-reports-active`, Sign in with Apple,
`applinks:magicmobile-downloads.vercel.app`, Game Center. No push, iCloud or app groups.

**Privacy manifest as shipped** (REA `inspect_plist`, `ev_4b8093f0…`): tracking false; collected data
types UserID and OtherUserContent (linked, app functionality); accessed APIs: UserDefaults (CA92.1) only.

**Required-reason APIs in the binary** (REA imports view `ev_b53bab06…`, plus the selector strings):

| Category | Evidence in build 38 | App call sites |
|---|---|---|
| File timestamp | imports `_stat`, `_fstat`, `_lstat`, `URLResourceValues.contentModificationDate` | `DeckStudioScryfall.swift:299`, `CommanderSpellbookClient.swift:259`, `NativeArtworkCatalogue.swift:277` (cache pruning) |
| System boot time | selector `systemUptime`; import `_mach_absolute_time` | 39 uses: turn clock and rope, `GameAudio` ducking, artwork retry back-off |
| Disk space | import `_NSFileSystemFreeSize`, `_fstatfs`, `_fstatvfs`; selector `attributesOfFileSystemForPath:error:` | `NativeAssetDownloads.swift:115` (downloads pause below 1 GB free) |

The libc imports come at least partly from the engine's static JDK libraries (`-ljava -lnio -lzip …`
in `apps/ios/native-engine.yml`). They share one manifest with the app because they are linked into
the same executable.

**Debug hooks.** A `strings` dump of the binary holds only two `MAGICMOBILE_*` names:
`MAGICMOBILE_UI_TEST_GRIMOIRE_MOTION` (turns the grimoire film back on under UI tests) and
`MAGICMOBILE_DESIGN_PREVIEW` (used by `HowToPlayLaunch.isAutomated`). Every fixture screen,
`MAGICMOBILE_UI_TEST_SOCIAL`, the relay override and the design-preview board sit behind `#if DEBUG`
and are absent. `SoundLabView` ships on purpose: it is Settings → Sound Lab, with the music picker and
the licence credits. One `print(` remains in app sources, and `__oslogstring` is 133 bytes.

### Inferences

- With the three categories undeclared, an App Store submission of build 38 would have been refused.
  TestFlight evidently accepted it. Apple's docs describe reminder emails on upload; whether any arrived
  is unknown.
- `__text` on iOS is 10.3 MB larger than the Android engine's `.text` (212.3 vs 202.0 MB). That gap is
  roughly the size of the Swift app plus iOS glue. This assumes the two AOT targets are about the same
  size.
- FairPlay encrypts the executable's `__TEXT` for App Store and TestFlight delivery. Encrypted bytes
  don't compress, so the real download is likely well above the IPA's 166 MB minus `Symbols/`.

## 2. Android build 22

### Observations

**Manifest** (decoded with build-tools 36.0.0 `aapt2 dump xmltree` and `badging`; REA
`decode_android_resources` needs apktool, which isn't installed): package
`com.calebfeliciano.magicmobile.android`, versionCode 2026101401, minSdk 26, targetSdk 35, arm64-v8a
only. `android:debuggable` absent (not debuggable), `allowBackup` false, `usesCleartextTraffic` false,
`extractNativeLibs` true, `dataExtractionRules` set. `MainActivity` is the only exported app component:
launcher, `https://magicmobile-downloads.vercel.app/join/` (autoVerify) and `magicmobile://join`.
`ArtworkDownloadService` is not exported (`foregroundServiceType` dataSync).

**Permissions vs use:**

| Permission | Declared by | Used for |
|---|---|---|
| INTERNET | app | Supabase, relay, Scryfall, downloads |
| FOREGROUND_SERVICE, FOREGROUND_SERVICE_DATA_SYNC | app | `ArtworkDownloadService` |
| POST_NOTIFICATIONS | app | the download's notification, requested in `NativeDownloadsView.kt:198` |
| ACCESS_NETWORK_STATE | merged from `transport-runtime` 2.2.6 and `transport-backend-cct` 2.3.3 (Google datatransport, pulled in by ML Kit) | ML Kit's telemetry upload scheduling; the app itself never checks connectivity |
| `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | AndroidX core (signature-level) | internal receivers |

Library components in the merged manifest: `MlKitInitProvider` (a ContentProvider, so it runs at every
app start), `MlKitComponentDiscoveryService` with `TextRegistrar`, datatransport's
`JobInfoSchedulerService` and `AlarmManagerSchedulerBroadcastReceiver`, Credential Manager and Google
sign-in activities, `RevocationBoundService` (exported, guarded by `…signin.permission.REVOCATION_NOTIFICATION`) and
`ProfileInstallReceiver` (exported, guarded by `android.permission.DUMP`).

**APK size by group** (REA inventory `ev_63505c05…` from the first half of this audit, 988 entries; the
`res/` file names are shortened in release, so they were mapped back through `aapt2 dump resources`):

| Group | Compressed | Uncompressed |
|---|---|---|
| `libmmengine.so` | 99.8 MB | 381.6 MB |
| `res/` (of which rank spin frames 6.80 MB, `tavern_pass_flip_*` 2.24 MB, `magicmobile_icon` 1.96 MB, retired battlefields 1.74 MB, unused legacy backgrounds 1.43 MB) | 25.2 MB | 27.1 MB |
| `assets/audio` | 10.8 MB | 10.8 MB |
| ML Kit (`libmlkit_google_ocr_pipeline.so` + `assets/mlkit-google-ocr-models`) | 5.7 MB | 12.6 MB |
| dex (3 files) | 5.5 MB | 14.6 MB |
| Filament + gltfio (3D d20) | 2.8 MB | 6.0 MB |
| Catalogue, printings, precons, AI decks, brackets | 2.6 MB | 13.9 MB |

**Debug hooks.** The dex still contains 22 `MAGICMOBILE_*` names, because `proguard-rules.pro` keeps
all of `io.magicmobile.**`. All of them are read through `LaunchEnvironment`, which
`DesignPreview.extras` fills only when `BuildConfig.DEBUG` is true (`DesignPreviewHost.kt:58`), so a
release build ignores intent extras. `MAGICMOBILE_RELAY_URL` is doubly gated
(`RelayTransport.kt:233`). Release logging: two `Log.i` lines in `OnDeviceSetup.kt` (catalogue load
time, checkpoint saved); every `Log.d` runs only in debug builds (behind `BuildConfig.DEBUG` or inside the debug-only preview host). Also present:
`DebugProbesKt.bin` (1.7 KB, from kotlinx-coroutines).

### Inferences

- With `useLegacyPackaging = true`, the installer extracts the 381.6 MB engine and keeps the 154 MB APK
  as well, so the engine takes about 480 MB on disk after install (`app/build.gradle.kts:33` explains
  the choice: a smaller download).

## 3. Engine binaries

### Observations

`libmmengine.so` (REA `inspect_with_objdump` section headers, `ev_936ed8a3…`):

| Section | Bytes |
|---|---|
| `.text` | 201,958,400 |
| `.svm_heap` | 167,301,120 |
| `.rela.dyn` (Android APS2-packed) | 12,250,351 |
| everything else | under 0.1 MB |

There is no `.symtab` and no `.debug_*`: the library is already stripped, so
`keepDebugSymbols += "**/libmmengine.so"` keeps nothing extra. NDK r28 `llvm-readelf`: NEEDED
`libz libdl libandroid liblog libmmawtstub libm libc`; `BIND_NOW`; 4,508,867 `R_AARCH64_RELATIVE`
relocations, plus 125 JUMP_SLOT, 70 ABS64 and 5 GLOB_DAT. The iOS image heap is the same size
(167,280,640) and sits in `__DATA`.

**Secrets scan** (same 20 patterns on every target; `secrets_scan.sh` in the evidence folder):
JWTs, `sb_secret_`, `service_role`, Stripe/AWS/GitHub/Slack/OpenAI/Anthropic keys, private-key
blocks, `client_secret`, bearer tokens, `/Users/…` paths and private IPs.

| Target | Hits |
|---|---|
| iOS executable | Supabase URL, `sb_publishable_…`, iOS Google OAuth client ID (public by design); `password=<word>` pairs from the JDK's localized resource bundles |
| iOS bundle (json, plists, provisioning profile, `Assets.car`, metallib, catalogue) | none |
| `libmmengine.so` | only the same JDK `password=` labels |
| other APK `.so` files | none |
| APK dex, `resources.arsc`, assets | Supabase URL, publishable key, Android Google OAuth client ID |

### Inferences

- The dynamic loader applies all 4.5 million relocations before the engine runs, writing a pointer into
  the image heap each time. Most of the 167 MB heap is then likely private dirty memory rather than
  clean, file-backed pages, and loading takes longer. RELR would shrink the 12 MB table but still
  dirty the pages; relative (heap-base) references in the native-image build would avoid both.

## 4. ML Kit text recognition

### Observations

ML Kit is still used. Deck Studio → Import → photo calls `DeckStudioOCR.recognize`
(`DeckStudioImport.kt:189` → `DeckStudioServices.kt:476–504`, `com.google.mlkit:text-recognition:16.0.1`,
the bundled Latin model). iOS does the same with Apple's `VNRecognizeTextRequest`
(`DeckStudioImportScreen.swift:492`). The code comment says "The image never leaves the phone", which is
true of the image. Google's ML Kit data-disclosure page (last updated 2026-07-15) says the SDKs collect
device information, package name and version, per-installation identifiers (for bundled features),
performance metrics, API configuration and event/error codes, for diagnostics and usage analytics.
The APK carries the transport for that: `transport-backend-cct`, `JobInfoSchedulerService`, and the
`ACCESS_NETWORK_STATE` it merges in.

### Options (item 3 above)

1. Keep it and disclose ML Kit's diagnostics in the privacy policy, the Play data safety form (when
   that track resumes) and any store listing.
2. Keep it, but remove `MlKitInitProvider` with `tools:node="remove"` and call `MlKit.initialize`
   just before the first scan, so launch doesn't pay for it. Needs a device check of the import flow.
3. Switch to `play-services-mlkit-text-recognition`, where the model comes from Google Play services:
   about 5.7 MB smaller download and 12.6 MB less installed. Phones without Play services lose
   photo import, and telemetry stays.
4. Drop photo import on Android, losing parity with iOS. Not recommended.

## 5. Privacy declarations vs behaviour

| Area | Declared | Seen in the build or source | Gap |
|---|---|---|---|
| iOS required-reason APIs | UserDefaults | + file timestamp, boot time, disk space | fixed in #155 |
| iOS collected data | UserID, OtherUserContent | Sign in with Apple requests `.email` (`AccountSignInCard.swift:88`); Google sign-in; ranked stores `ranked_matches` / `ranked_profiles` linked to the account (docs/RANKED.md) | EmailAddress and GameplayContent likely belong in the manifest and the App Store labels |
| Site privacy policy (2026-10-01) | "anonymous account (no email, no password)", "no ads, no analytics and no tracking" | optional Apple/Google sign-in with email (TF 35 / Android 20), ranked and friend challenges, public profiles, ML Kit diagnostics on Android | policy predates these |
| iOS tracking | false | no ATT, no IDFA, no third-party SDKs | consistent |
| Android permissions | 5 app + 1 library | all used; ACCESS_NETWORK_STATE comes from ML Kit's transport | consistent once item 3 is decided |
| `NSPhotoLibraryUsageDescription` | "player icon" | photo picking uses `PhotosPicker`, which doesn't prompt for permission | harmless; mention decklist photos if the string ever shows |

The data-type and policy changes are not in #155. They are disclosure decisions for Caleb, and the
manifest, the App Store Connect privacy questionnaire and the site have to change together.

## Unknowns and next probes

| Unknown | Probe |
|---|---|
| Real App Store / TestFlight download and install size for build 38 | App Store Connect → TestFlight → build 38 → App File Sizes |
| Whether ITMS-91053 warning emails arrived for earlier uploads | Caleb's developer-account inbox |
| Does ML Kit send anything at launch, or only on a scan? | Emulator + network capture over a launch and one decklist scan (REA `capture_process_scenario` / adb) |
| Engine load cost of the relocations: Private_Dirty of the `.svm_heap` mapping, time to `JNI_OnLoad` | `adb shell cat /proc/<pid>/smaps` on a release install; a startup trace |
| What fills the 167 MB image heap and 202 MB of code | GraalVM `--emit build-report` on the next engine build |
| Installed size on Android | Settings → Apps → MagicMobile → Storage, or `adb shell du` on `/data/app/…` |
| Engine logging during a game | `adb logcat` while playing a release build |
| Whether rank spin frames survive lossy encoding visually | Encode one tier as lossy HEIF/WebP with alpha and compare on device |

## Evidence index

REA evidence (exported bundle `rea-evidence-bundle-2026-10-14.json`, 15 records, kept with the
other raw outputs in the session notes folder `rea-audit-evidence/`, outside the repo):

| ID | Operation | Subject |
|---|---|---|
| `ev_217851374510d1ff435378b93fe260487932d78c28e9aed26b9fb52b05bcd5d5` | inspect_artifact | IPA |
| `ev_ffda084263a7eaac924fbc49eee4d343697684f82140d20e2c8d852ee2163793` | inventory_artifact | IPA (90 entries) |
| `ev_5c4e1dec1c64c5699a38a401d99754f92bf308f5ccadff8779697f66164626ca` | inspect_macho | iOS executable |
| `ev_cded3057b293008d0554b58153549c566a7bb3decc9b5e5989153f435c89c454` | view: segments | iOS executable |
| `ev_6501e1213a1a71048b357527573600a5ef73a3cc46cb00eab8457829335377c7` | view: dependencies | iOS executable |
| `ev_5bfedfad2cf9225c2ff8bc441d34c92061ac6eb873f59f89542e085443a7ca6f` | view: build metadata | iOS executable |
| `ev_b53bab0698338cf611b8258a4717e7bfd89cc3d063322afb6d3c3f90e444c18a` | view: imports (3,210 rows) | iOS executable |
| `ev_4c468c590bede6464ce8dc8d593c17350efc9ebb94a3cec2b0aa8ec3f9b5be0d` | inspect_plist | Info.plist |
| `ev_4b8093f0d3696bd54832d459b355bcf9f10afb512bde395b328a95688bba0f8e` | inspect_plist | PrivacyInfo.xcprivacy |
| `ev_231d40824fa926bd8873b5520ceb50d2807abe99067ed15c44b22460e5408f5c` | inspect_signature | iOS executable |
| `ev_5d39494adad5d83216f6288bbcf3308bb0a4df40ca21efcba51d547150050f17` | inspect_asset_catalog | Assets.car |
| `ev_936ed8a3cdf283e273feb67322ec500b0c0c8d6493997168654f48f7d688cdfe` | inspect_with_objdump (section headers) | libmmengine.so |
| `ev_c01ba86c5b697eade56cb8deb715a14abf8460a29609e0136a03809b96d26a58` | inspect_artifact | APK |
| `ev_63505c057c7f1f2d3d8b7fb43b465c4b450f51c1e34e2938c7c520510c137f2b` | inventory_artifact | APK (988 entries) |

The other evidence is command output from SDK tools, not REA: `aapt2 dump xmltree/badging/resources`
(build-tools 36.0.0), NDK r28 `llvm-readelf -d/-n/-r`, `strings`, and the secrets scan. REA had no
provider for these: `inspect_binary_layout` supports only Linux x86-64 ELF, and
`decode_android_resources` and `inspect_android_package` need apktool or JADX, which aren't installed.
Nothing new was installed for this audit.
