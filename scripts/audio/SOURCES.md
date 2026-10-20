# Game audio sources

Every sound in `apps/ios/MagicMobile/Resources/Audio` is rendered by `build_game_audio.py`
from the recordings below (trimmed, faded and loudness-matched; nothing synthesized).
Convert each source to 44.1 kHz float WAV named after the original file
(`afconvert -f WAVE -d LEF32@44100 <source> <name>.wav`) and pass the three folders
to the script with `--sonniss`, `--kenney` and `--music`.

## Sonniss.com GDC Game Audio Bundles
Royalty-free for commercial use, no attribution required, not to be resold as a sound
library (the license PDF sits beside each bundle). Files come one by one from the official
mirror listed on https://sonniss.com/gameaudiogdc (`ftpmirror.your.org/pub/misc/sonniss<year>/individual/`).
Bundle / pack / file:

- GDC 2019 / Sound Spark LLC – Magic Spells, Buffs and Attacks / `Arcane_Spell_Doppler_Shift_03.wav`
- GDC 2020 / Scoba Sounds – Scoba Ui Essentials / `BALAFON - NOTIF OCT UP.wav`
- GDC 2016 / George Karagioules - SFX for Board Games / `Backgammon Piece 21.wav`
- GDC 2018 / Bluezone Corporation - MOVIE TRAILER / `Bluezone_BC0237_impact_017.wav`
- GDC 2020 / Bluezone - Switch And Button Sound Effects / `Bluezone_BC0268_switch_button_click_small_005.wav`
- GDC 2019 / Touchdown Audio -The White Stuff / `CATALOGUE_Page_Turn_9.wav`
- GDC 2017 / Articulated Sounds - Dice / `DICE on Hard Wood, Throw and Roll , Standard, 2 Two Dice, v1.wav`
- GDC 2019 / Sound Spark LLC – Magic Spells, Buffs and Attacks / `Dark_Spell_Life_Tap_03.wav`
- GDC 2017 / Double Trouble Audio - Wood Impacts and Debris / `Drop Soft - Single Plank, Drop 02.wav`
- GDC 2015 / Mechanical Wave - Hits Whoosh / `Fast Action Swish_HW 05.wav`
- GDC 2019 / Sound Spark LLC – Magic Spells, Buffs and Attacks / `Fire_Spell_Dragon_Trap_03.wav`
- GDC 2018 / Sound Ex Machina - PAPER & CARDBOARD / `Gathering a pile of small cards 05.wav`
- GDC 2019 / Sound Spark LLC – Magic Spells, Buffs and Attacks / `Ice_Spell_Ice_Spell_Buff_Positive_02.wav`
- GDC 2019 / Airborne Sound - Crisis Accents / `Impact,Sound Design,Hit,Chime,Resonant Hit,Chime Accent,Tinkle,Fast.wav`
- GDC 2019 / Articulated Sounds - Magic Elements vol.1 / `MAGIC AIR Large Whoosh, Swirl, Wind Gust, Foliage 01.wav`
- GDC 2020 / David Dumais Audio - Magic Sound FX Pack 1 / `Magic_Explosion_Short19.wav`
- GDC 2020 / David Dumais Audio - Spells Magic 1 / `Magic_Spells_CastShort_Push14.wav`
- GDC 2020 / David Dumais Audio - Water Magic 1 / `Magic_Spells_CastShort_Water_General07.wav`
- GDC 2020 / David Dumais Audio - Spells Magic 1 / `Magic_Spells_Impact_Creation20.wav`
- GDC 2020 / David Dumais Audio - Magic Sound FX Pack 1 / `Magic_Transformation03.wav`
- GDC 2019 / Impact Soundworks - Super FX 8 and 16-bit Video Game SFX / `Misc_Glass_Crystal_Shatter.wav`
- GDC 2019 / Touchdown Audio -The White Stuff / `NOTEPAD_Page_Turn_4.wav`
- GDC 2016 / George Karagioules - SFX for Board Games / `Placing Pieces on the Board 2.wav`
- GDC 2019 / L.A. Sounds - Game & UI Interface 001 / `Scatter Plops 04.wav`
- GDC 2019 / InspectorJ - UI - Mechanical / `UI_Mechanical_Move_40.wav`
- GDC 2015 / Kpow Sounds - UI SOUNDPACKS / `UI_SoundPack11_Back_v1.wav`
- GDC 2018 / Glitchedtones - User Interface / `User Interface Notification Bubbles 04.wav`
- GDC 2017 / Double Trouble Audio - Medieval Armor and Impacts / `Weapon_Impact_Parry_01.wav`
- GDC 2018 / Airborne Sound - Eclectic Whooshes / `Whoosh,Sound Design,Logo,Airy to Shiver,Uncertain,Low.wav`
- GDC 2017 / Gamemaster Audio - Fun Casual Sounds / `collect_item_14.wav`
- GDC 2016 / Timothy McHugh - Playing Cards & Betting Chips / `games - Deck of cards handled, shuffled and tapped onto table 1.wav`
- GDC 2019 / 3maze - UI FX / `marimba_tone_007.wav`
- GDC 2019 / 3maze - UI FX / `owl_notification_005.wav`
- GDC 2017 / Gamemaster Audio - Punch Sound Pack / `punch_general_body_impact_03.wav`
- GDC 2017 / Gamemaster Audio - Punch Sound Pack / `punch_heavy_huge_distorted_01.wav`
- GDC 2018 / 3maze - Books & Magazines / `shut_small_book_002.wav`

## Kenney.nl Casino Audio (CC0 1.0)
https://kenney.nl/assets/casino-audio, decoded to 44.1 kHz WAV as `casino-audio__<file>.wav`:

- `casino-audio__card-slide-1.wav`
- `casino-audio__card-slide-3.wav`
- `casino-audio__card-slide-4.wav`
- `casino-audio__card-shove-4.wav`
- `casino-audio__card-place-1.wav`
- `casino-audio__card-place-3.wav`

## Kevin MacLeod, incompetech.com (CC BY 4.0)
Download from `https://incompetech.com/music/royalty-free/mp3-royaltyfree/<Title>.mp3`.
Credited in the app's Sound Lab and in Resources/Audio/CREDITS.txt.

Music (whole tracks):

- Midnight Tale
- Industrious Ferret
- Village Consort
- Thatched Villagers
- Teller of the Tales
- Lord of the Land
- Suonatore di Liuto
- Pippin the Hunchback

Stingers (excerpts):

- Discovery Hit
- Greta Sting
- Danse Macabre - Big Hit 1

## Kenney – RPG Audio (CC0, https://kenney.nl/assets/rpg-audio)
Used by `steal` (2026-10-19): `metalLatch`, `beltHandle1`, `beltHandle2` (with Casino `card-place-1`). Kenney packs
are Ogg Vorbis, which `afconvert` does not read: convert with
`ffmpeg -i <file>.ogg -ar 44100 -c:a pcm_f32le <pack>__<file>.wav` (`rpg-audio__metalLatch.wav`).

## Play Commander (`menu-play`, 2026-10-19)
Sonniss: GDC 2015 / Soundopolis - Blades / `Knife_Sword_Shing_Fienup_001.wav`.

## Deck Studio's spell book (`book-open`, `book-close`, 2026-10-19)
Sonniss: GDC 2019 / PMSFX - Books Alive / `PM_BA_BOOK_0_29 Book, Open, Paper.wav`, `PM_BA_BOOK_2_6 Book, Paper, Page
Turn.wav`; GDC 2018 / 3maze - Books & Magazines / `shut_small_book_002.wav`. Kenney RPG: `metalClick`, `creak3`,
`bookPlace2`, `metalLatch`.

## Trials (not in the app yet)
`trials.py` renders candidates for cues being reworked next to the shipped ones, into `build_output/audio-trials/`,
for Caleb to audition before any is wired in (see its docstring). The Play Commander candidates use:

- GDC 2018 / Gregor Quendel - Designed Fire / `Designed Fire - Impacts - Large, ignition 03.wav`
- GDC 2017 / Mononeshot - MEDIEVAL, Smithy / `MEDIEVAL, Smithy - 24 - Bellows - Fire, oven accent.wav`

Round 4 (cards entering by type) adds: GDC 2017 / Double Trouble Audio - Medieval Armor and Impacts /
`Plate_Impact_Hard_02.wav`; GDC 2020 / Articulated Sounds - Magic Elements vol.2 / `MAGIC GENERIC Texture, Shimmer,
Processed Glass, Reversed Layer, Disturbing, High.wav`, `MAGIC ENERGY Texture, Complex, Particles, Zap, Sparks,
Short-Circuit, High, Sweetener 03.wav`; GDC 2020 / David Dumais Audio - Spells Magic 1 / `Magic_Spells_Impact_Creation20.wav`
(already the colorless cast); Kenney Casino `card-fan-1`.

Round 5 (round 4 redone short and dry) uses Kenney Impact Sounds (CC0, https://kenney.nl/assets/impact-sounds) and
Interface Sounds (CC0, https://kenney.nl/assets/interface-sounds), named `impact-sounds__…`/`interface-sounds__…`, and
GDC 2016 / George Karagioules - SFX for Board Games / `Placing Pieces on the Board 2.wav`.

## Cards arriving (`slam-*`, `land-*` basics, `layer-*`, 2026-10-19; trials round 6)
Kenney Impact Sounds (CC0) for the slam's thuds and the colorless clink, and Sonniss: GDC 2016 / Timothy McHugh - Playing Cards &
Betting Chips / `games - Deck of cards dealt on to felt table surface 43.wav`; GDC 2018 / Bluezone - MOVIE TRAILER /
`Bluezone_BC0237_impact_017.wav`; GDC 2017 / Hzandbits - Wind In Trees / `Wind,Ext,Gust,Grasslands,Rustle,Buffeting.wav`;
GDC 2017 / Raconteur Sound - Spring in the Pacific Northwest / `Amb, Field, Birds, Wind, MS_01.wav`; GDC 2017 / West Wolf -
Nature Sounds / `NS01_007_Forest birds.wav`; GDC 2017 / RedSonic - Water on Rocks /
`water_lapping_sea_waves_sandy_beach_03.wav`; GDC 2020 / Articulated Sounds - Magic Elements vol.2 / `LIQUID HIT Lake,
Branch, Splash, Lake, Seaweed in Water, Small, CU 04.wav`; GDC 2016 / Alexander Kopeikin - Rocks / `soil and dirt debris
heavy 13.wav`, `rock impact medium 26.wav`, `rock tumble down debris long 06.wav`; GDC 2018 / Soundrangers - Foley
Elements Foliage / `leaves_pile_pick_up_04.wav`, `tree_dead_tree_limb_impact_05.wav`; GDC 2018 / Soundrangers - Nature
Ambience / `swamp_ambience_night_05_120_loop.wav` (the frog, ~38.6 s); GDC 2018 / The Sound Keeper - Small Fire /
`sm-fire-firewood-small-03-DPAmono.wav`; plus Kenney Impact Sounds.

Round 8 (one sound per card type; colour textures only for lands) adds Sonniss: GDC 2018 / Gibson and Ansell - Got Wood /
`PineBlock_8x22x100cm_FaceDropped100cmOntoMDF_BeyerdynamicTG137c_Medium.wav`, `BeechPlank_3x27x100cm_EndDropped30cmOntoMDF_SureSM57_Close.wav`;
GDC 2019 / Baxter Audio - IMPACT / `10 Hit Deep Thud.wav`, `03 Hit Big Drum.wav`; GDC 2020 / SmartSoundFX - Impacts, Hits &
Whooshes / `IMPACT METAL Short Slam_03.wav`, `IMPACT METAL Scratchy Short Punch_03.wav`, `WHOOSH AIR Steady Smooth_02.wav`;
GDC 2020 / Sound Spark LLC - Whooshes Impacts and Transitions / `Whoosh_Fast_02.wav`, `Transition_3.wav`; GDC 2017 / SoundBits -
Whooshes & Impacts 2 / `Whooshes_135.wav`; GDC 2017 / Double Trouble Audio - Wood Impacts and Debris / `Rustles - Pile, Debris
22.wav`; GDC 2019 / Airborne Sound - Organic Whooshes / `Whoosh,Organic,Fabric,Glove,Airy,Breathy,Punchy.wav`.

`sfx_synth/` holds the sound generators from claude-motion (MIT, https://github.com/whaleyxbt/claude-motion at
`e627941`, `sfx/`; only `SR` changed to 44.1 kHz), for quiet tonal layers under recordings (a trial's sparkle).
Its licence sits beside it. Everything runs in a scratch virtualenv with `numpy scipy pedalboard` (`~/.venvs/mm-audio`).

## Creature voices and card sounds (`creature-*`, `arrive-*`, `card-draw`, `card-play`, `shuffle`, 2026-10-19; round 13)
Caleb picked these in the Tavern Sound Bin (https://claude.ai/artifact/NvyW4nTABNGHk8ZchmZkxC; rounds 12-13 render
with `round12.py`). Nothing gets a wood knock: a voiced creature plays its voice alone, an unvoiced one a card placed
on the table. `build_game_audio.py --library build_output/audio-sources` reads the clips below from there.

- Sonniss voices: GDC 2017 / MatiasMacSD - CREATURES ZONE / `Creature_Dragon_Roar_01.wav`; GDC 2019 / Prismo Sound -
  Singing Bowls / `SINGING_BOWL_Strike_Sustain_D_02.wav` (elf); GDC 2017 / Double Trouble Audio - Medieval Armor and Impacts /
  `LeatherArmor_Rustle_03.wav` and GDC 2020 / 344 Audio - Medieval Battle / `Sword Scrapes Multiple, Battle, Metal, Slash,
  Draw.wav` (human); GDC 2020 / Phase 4 Libraries - Monster Roars / `MR - Insect Creature Attack VO 02.wav` and GDC 2020 /
  Bluezone - Crab - Creature / `Bluezone_BC0263_creature_crab_organic_texture_carapace_crack_squishy_003.wav` (sliver);
  GDC 2018 / Discover Oregon - Forest Meadow Birds / `Squirrel 2017 Lookout Hood Dawn Loud Squirrel 3.WAV`.
- Sonniss others: GDC 2020 / SmartSoundFX - Impacts, Hits & Whooshes / `IMPACT METAL Short Slam_03.wav` (artifact);
  GDC 2019 / Baxter Audio - IMPACT / `10 Hit Deep Thud.wav` (the big no-voice creature's soft thud); GDC 2020 / David
  Dumais Audio - Spells Magic 1 / `Magic_Spells_Impact_Creation20.wav` with Kenney `impactBell_heavy_002` (planeswalker).
- Pixabay (`pixabay-raw/<group>/`, fetched from `cdn.pixabay.com/download/audio/...`; Pixabay Content License, no
  attribution required, no standalone resale): the files named in `CREATURE_VOICES`, `card_placed`, `card-draw`,
  `shuffle` and `r_arrive_enchantment`, each ending in its Pixabay id. Uploaders are credited in CREDITS.txt.
- OpenGameArt CC0 (`oga-raw/`): rubberduck's "80 CC0 creature SFX" (`creatures1/`: `grunt_01`, `cute_01`, `bug_04`,
  `burble_01`) and "#2" (`creatures2/`: `slime_01`); https://opengameart.org/content/80-cc0-creature-sfx and
  https://opengameart.org/content/80-cc0-creture-sfx-2. artisticdude's CC0 goblins pack is downloaded but unused.

Round 14 adds the rat (Rat, Mouse) and Eldrazi voices: `pixabay-raw/rat/u_3yocsblk00-rat-squeaking-sound-effecthd-570216.mp3`
and `pixabay-raw/eldrazi/brvhrtz-creature-01-brvhrtz-232041.mp3`, from 27 candidates in `rat/` and `eldrazi/` (Sound
Bin round 14). Voices now keep their tails (`library(gentle=True)`, up to 1.6x the auditioned cut).

Downloaded but unused so far: the rest of `pixabay-raw/` (135 clips) and `oga-raw/`, all on the Sound Bin. The
Sonniss GDC 2026 bundle's Google Drive mirror honours HTTP Range (single members can be pulled from the 1.3-1.9 GB
zips), but it throttled every request on 2026-10-19.
