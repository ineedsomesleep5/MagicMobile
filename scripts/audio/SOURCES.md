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
- GDC 2020 / David Dumais Audio - Air Magic 1 / `Magic_Spells_Impact_Air24.wav`
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
