package io.magicmobile.android.ui

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.magicmobile.android.game.BoardFXCastSound
import kotlin.random.Random

/**
 * Port of apps/ios/MagicMobile/GameAudio.swift. The same recordings (staged from the iOS bundle
 * by prepare_audio.py), mix levels, voices, cooldowns and playlists. Effects mix with the
 * player's own audio: no audio focus is taken, like the iOS ambient session.
 */
enum class GameSoundCategory(val rawValue: String, val title: String, val detail: String) {
    INTERFACE("interface", "Menus & alerts", "Confirm buttons, sheets, “your decision” and emotes."),
    CARDS("cards", "Cards & board", "Drawing, playing, lands, creatures and their kinds, artifacts and counters."),
    SPELLS("spells", "Spells", "Instants, sorceries, other spells, big spells and your commander."),
    COMBAT("combat", "Combat & life", "Attacks, blocks, hits, deaths, exile and life changes."),
    MOMENTS("moments", "Big moments", "Your turn, the versus reveal, victory, defeat and dice.");
    val key: String get() = "magicmobile.sfx.$rawValue"
}

enum class GameSound(val rawValue: String, val category: GameSoundCategory, val title: String) {
    UI_TAP("ui-tap", GameSoundCategory.INTERFACE, "Game button"), UI_CONFIRM("ui-confirm", GameSoundCategory.INTERFACE, "Confirm"),
    UI_BACK("ui-back", GameSoundCategory.INTERFACE, "Back"), UI_OPEN("ui-open", GameSoundCategory.INTERFACE, "Open a panel"),
    UI_CLOSE("ui-close", GameSoundCategory.INTERFACE, "Close a panel"), UI_TOGGLE("ui-toggle", GameSoundCategory.INTERFACE, "Switch"),
    UI_TICK("ui-tick", GameSoundCategory.INTERFACE, "Slider tick"), UI_ERROR("ui-error", GameSoundCategory.INTERFACE, "Not allowed"),
    RESPONSE_ALERT("response-alert", GameSoundCategory.INTERFACE, "Your decision"), MENU_PLAY("menu-play", GameSoundCategory.INTERFACE, "Play"),
    PAGE_FLIP("page-flip", GameSoundCategory.INTERFACE, "Page turn"), EMOTE("emote", GameSoundCategory.INTERFACE, "Emote"),
    BOOK_OPEN("book-open", GameSoundCategory.INTERFACE, "Spell book opens"), BOOK_CLOSE("book-close", GameSoundCategory.INTERFACE, "Spell book closes"),
    CARD_DRAW("card-draw", GameSoundCategory.CARDS, "Draw a card"), CARD_PICKUP("card-pickup", GameSoundCategory.CARDS, "Pick up a card"),
    CARD_PLAY("card-play", GameSoundCategory.CARDS, "Play a card"), SHUFFLE("shuffle", GameSoundCategory.CARDS, "Shuffle (mulligan)"),
    LAND_DROP("land-drop", GameSoundCategory.CARDS, "Land"), COUNTER("counter", GameSoundCategory.CARDS, "Counter"),
    // A card arriving (BoardFXArrivalSound): one sound per kind of card, never a wood knock under it. A creature plays its
    // type's voice alone, or lands as a card placed on the table when its type has no voice yet; a basic land plays its
    // place. Water, fire and leaves are only ever the lands'.
    ARRIVE_CREATURE("arrive-creature", GameSoundCategory.CARDS, "Creature lands"),
    ARRIVE_CREATURE_HEAVY("arrive-creature-heavy", GameSoundCategory.CARDS, "Big creature lands"),
    ARRIVE_ARTIFACT("arrive-artifact", GameSoundCategory.CARDS, "Artifact"), ARRIVE_ENCHANTMENT("arrive-enchantment", GameSoundCategory.CARDS, "Enchantment"),
    ARRIVE_PLANESWALKER("arrive-planeswalker", GameSoundCategory.CARDS, "Planeswalker"),
    // Creature voices, one per BoardFXArrivalSound.creatureVoices slot
    CREATURE_HUMAN("creature-human", GameSoundCategory.CARDS, "Human"), CREATURE_GOBLIN("creature-goblin", GameSoundCategory.CARDS, "Goblin"),
    CREATURE_ELF("creature-elf", GameSoundCategory.CARDS, "Elf"), CREATURE_DRAGON("creature-dragon", GameSoundCategory.CARDS, "Dragon"),
    CREATURE_SLIVER("creature-sliver", GameSoundCategory.CARDS, "Sliver"), CREATURE_SQUIRREL("creature-squirrel", GameSoundCategory.CARDS, "Squirrel"),
    CREATURE_ORC("creature-orc", GameSoundCategory.CARDS, "Orc, ogre, troll"), CREATURE_GIANT("creature-giant", GameSoundCategory.CARDS, "Giant"),
    CREATURE_BEAR("creature-bear", GameSoundCategory.CARDS, "Bear"), CREATURE_DINOSAUR("creature-dinosaur", GameSoundCategory.CARDS, "Dinosaur"),
    CREATURE_BEAST("creature-beast", GameSoundCategory.CARDS, "Beast, hydra"), CREATURE_HORROR("creature-horror", GameSoundCategory.CARDS, "Horror, demon, wurm"),
    CREATURE_CRITTER("creature-critter", GameSoundCategory.CARDS, "Small critter"), CREATURE_FAERIE("creature-faerie", GameSoundCategory.CARDS, "Faerie"),
    CREATURE_ANGEL("creature-angel", GameSoundCategory.CARDS, "Angel"), CREATURE_VAMPIRE("creature-vampire", GameSoundCategory.CARDS, "Vampire"),
    CREATURE_ZOMBIE("creature-zombie", GameSoundCategory.CARDS, "Zombie"), CREATURE_WOLF("creature-wolf", GameSoundCategory.CARDS, "Wolf, dog"),
    CREATURE_CAT("creature-cat", GameSoundCategory.CARDS, "Cat"), CREATURE_BIRD("creature-bird", GameSoundCategory.CARDS, "Bird"),
    CREATURE_OOZE("creature-ooze", GameSoundCategory.CARDS, "Ooze"), CREATURE_WIZARD("creature-wizard", GameSoundCategory.CARDS, "Wizard"),
    CREATURE_INSECT("creature-insect", GameSoundCategory.CARDS, "Insect, spider"),
    CREATURE_RAT("creature-rat", GameSoundCategory.CARDS, "Rat, mouse"), CREATURE_ELDRAZI("creature-eldrazi", GameSoundCategory.CARDS, "Eldrazi"),
    LAND_PLAINS("land-plains", GameSoundCategory.CARDS, "Plains"), LAND_ISLAND("land-island", GameSoundCategory.CARDS, "Island"),
    LAND_SWAMP("land-swamp", GameSoundCategory.CARDS, "Swamp"), LAND_MOUNTAIN("land-mountain", GameSoundCategory.CARDS, "Mountain"),
    LAND_FOREST("land-forest", GameSoundCategory.CARDS, "Forest"),
    ABILITY("ability", GameSoundCategory.CARDS, "Your ability"), STEAL("steal", GameSoundCategory.CARDS, "Stolen permanent"),
    // Spells by card type (BoardFXCastSound), never colour
    CAST_INSTANT("cast-instant", GameSoundCategory.SPELLS, "Instant"), CAST_SORCERY("cast-sorcery", GameSoundCategory.SPELLS, "Sorcery"),
    CAST_PERMANENT("cast-permanent", GameSoundCategory.SPELLS, "Permanent spell"), SPELL_BIG("spell-big", GameSoundCategory.SPELLS, "Big spell"),
    COMMANDER_CAST("commander-cast", GameSoundCategory.SPELLS, "Commander"),
    ATTACK("attack", GameSoundCategory.COMBAT, "Attack"), BLOCK("block", GameSoundCategory.COMBAT, "Block"),
    STRIKE("strike", GameSoundCategory.COMBAT, "Creature hit"), PLAYER_HIT("player-hit", GameSoundCategory.COMBAT, "You’re hit"),
    DEATH("death", GameSoundCategory.COMBAT, "Creature dies"), EXILE("exile", GameSoundCategory.COMBAT, "Exile"),
    LIFE_GAIN("life-gain", GameSoundCategory.COMBAT, "Life gain"), LIFE_LOSS("life-loss", GameSoundCategory.COMBAT, "Life loss"),
    TURN_YOU("turn-you", GameSoundCategory.MOMENTS, "Your turn"), VERSUS("versus", GameSoundCategory.MOMENTS, "Versus"),
    VICTORY("victory", GameSoundCategory.MOMENTS, "Victory"), DEFEAT("defeat", GameSoundCategory.MOMENTS, "Defeat"),
    DICE_ROLL("dice-roll", GameSoundCategory.MOMENTS, "Dice roll"), DICE_LAND("dice-land", GameSoundCategory.MOMENTS, "Die lands");

    /** Numbered files ("attack-1…3") give repeated sounds natural variety; a creature type with several voices picks one. */
    val variants: Int get() = when (this) {
        ATTACK -> 3
        CREATURE_GIANT, CREATURE_FAERIE, CREATURE_ZOMBIE, CREATURE_CAT, CREATURE_OOZE, CREATURE_WIZARD, CREATURE_INSECT -> 2
        CREATURE_DRAGON, CREATURE_SQUIRREL, CREATURE_ORC, CREATURE_HORROR -> 3
        else -> 1
    }

    /** The files a sound plays from: Giants share the first two orc voices (Caleb: the third is not for giants). */
    val fileBase: String get() = if (this == CREATURE_GIANT) CREATURE_ORC.rawValue else rawValue

    val isCreatureVoice: Boolean get() = rawValue.startsWith("creature-")

    /** Mix level: interface quiet, the board clear, big moments on top. */
    val volume: Float get() = when (this) {
        UI_TAP, UI_TICK, UI_TOGGLE, UI_BACK, UI_OPEN, UI_CLOSE -> 0.5f
        UI_CONFIRM, UI_ERROR, PAGE_FLIP, EMOTE, BOOK_OPEN, BOOK_CLOSE -> 0.65f
        RESPONSE_ALERT, MENU_PLAY -> 0.8f
        CARD_DRAW, CARD_PICKUP, COUNTER, ABILITY -> 0.7f
        CARD_PLAY, SHUFFLE, LAND_DROP, ARRIVE_CREATURE, ARRIVE_CREATURE_HEAVY, ARRIVE_ARTIFACT, ARRIVE_ENCHANTMENT, ARRIVE_PLANESWALKER,
        LAND_PLAINS, LAND_ISLAND, LAND_SWAMP, LAND_MOUNTAIN, LAND_FOREST, CREATURE_HUMAN, CREATURE_GOBLIN, CREATURE_ELF, CREATURE_DRAGON, CREATURE_SLIVER, CREATURE_SQUIRREL, CREATURE_ORC, CREATURE_GIANT, CREATURE_BEAR, CREATURE_DINOSAUR, CREATURE_BEAST, CREATURE_HORROR, CREATURE_CRITTER, CREATURE_FAERIE, CREATURE_ANGEL, CREATURE_VAMPIRE, CREATURE_ZOMBIE, CREATURE_WOLF, CREATURE_CAT, CREATURE_BIRD, CREATURE_OOZE, CREATURE_WIZARD, CREATURE_INSECT, CREATURE_RAT, CREATURE_ELDRAZI -> 0.85f
        CAST_INSTANT, CAST_SORCERY, CAST_PERMANENT -> 0.85f
        SPELL_BIG, COMMANDER_CAST, ATTACK, BLOCK, STRIKE, PLAYER_HIT -> 0.9f
        DEATH, EXILE, LIFE_GAIN, LIFE_LOSS, STEAL -> 0.75f
        TURN_YOU, VERSUS, VICTORY, DEFEAT -> 0.9f
        DICE_ROLL, DICE_LAND -> 0.85f
    }

    /** A little pitch variation keeps repeated foley from sounding mechanical; musical cues stay in tune. */
    val pitchVariation: Float get() = when (this) {
        CARD_DRAW, CARD_PICKUP, CARD_PLAY, LAND_DROP, STRIKE, PLAYER_HIT, DEATH, ATTACK, BLOCK, COUNTER, SHUFFLE, DICE_LAND,
        ARRIVE_CREATURE, ARRIVE_CREATURE_HEAVY, ARRIVE_ARTIFACT -> 0.04f
        else -> 0f
    }

    /** Simultaneous copies allowed (a board wipe plays several deaths at once). */
    val voices: Int get() = when (this) {
        STRIKE, DEATH, CARD_DRAW, ARRIVE_CREATURE, ARRIVE_CREATURE_HEAVY, ARRIVE_ARTIFACT, ARRIVE_ENCHANTMENT, ARRIVE_PLANESWALKER,
        CREATURE_HUMAN, CREATURE_GOBLIN, CREATURE_ELF, CREATURE_DRAGON, CREATURE_SLIVER, CREATURE_SQUIRREL, CREATURE_ORC, CREATURE_GIANT, CREATURE_BEAR, CREATURE_DINOSAUR, CREATURE_BEAST, CREATURE_HORROR, CREATURE_CRITTER, CREATURE_FAERIE, CREATURE_ANGEL, CREATURE_VAMPIRE, CREATURE_ZOMBIE, CREATURE_WOLF, CREATURE_CAT, CREATURE_BIRD, CREATURE_OOZE, CREATURE_WIZARD, CREATURE_INSECT, CREATURE_RAT, CREATURE_ELDRAZI -> 3
        VICTORY, DEFEAT, VERSUS, TURN_YOU, MENU_PLAY, RESPONSE_ALERT -> 1
        else -> 2
    }

    /** Minimum seconds between two plays of this cue. */
    val cooldown: Double get() = when (this) {
        UI_TICK -> 0.08
        CARD_DRAW, UI_TAP -> 0.1
        STRIKE, DEATH, LAND_DROP, ARRIVE_CREATURE, ARRIVE_CREATURE_HEAVY, ARRIVE_ARTIFACT, ARRIVE_ENCHANTMENT, ARRIVE_PLANESWALKER,
        LAND_PLAINS, LAND_ISLAND, LAND_SWAMP, LAND_MOUNTAIN, LAND_FOREST -> 0.12
        COUNTER, LIFE_GAIN -> 0.3
        CAST_INSTANT, CAST_SORCERY, CAST_PERMANENT -> 0.25
        ABILITY -> 0.8
        RESPONSE_ALERT -> 1.2
        TURN_YOU, VERSUS, VICTORY, DEFEAT -> 1.5
        else -> 0.12
    }

    companion object {
        fun cast(kind: BoardFXCastSound): GameSound = when (kind) {
            BoardFXCastSound.INSTANT -> CAST_INSTANT; BoardFXCastSound.SORCERY -> CAST_SORCERY; BoardFXCastSound.PERMANENT -> CAST_PERMANENT
        }
        /** A creature voice slot (BoardFXArrivalSound.creatureVoices) to its sound. */
        fun voice(slot: String): GameSound? = entries.firstOrNull { it.rawValue == "creature-$slot" }
        fun sounds(category: GameSoundCategory): List<GameSound> = entries.filter { it.category == category }
    }
}

/** One recorded music track (Kevin MacLeod, incompetech.com, CC BY 4.0). */
data class MusicTrack(val file: String, val title: String)

/** Music plays as a playlist per scene: whole tracks, one after another. */
enum class GameMusic(val rawValue: String) {
    MENU("menu"), GAME("game");
    val level: Float get() = if (this == MENU) 0.6f else 0.42f
    /** "shuffle" or one track's file name. */
    val choiceKey: String get() = "magicmobile.music.$rawValue"
    val title: String get() = if (this == MENU) "Lobby music" else "In-game music"
    val tracks: List<MusicTrack> get() = when (this) {
        MENU -> listOf(MusicTrack("music-menu-1", "Midnight Tale"), MusicTrack("music-menu-2", "Industrious Ferret"),
            MusicTrack("music-menu-3", "Village Consort"), MusicTrack("music-menu-4", "Thatched Villagers"))
        GAME -> listOf(MusicTrack("music-game-1", "Teller of the Tales"), MusicTrack("music-game-2", "Lord of the Land"),
            MusicTrack("music-game-3", "Suonatore di Liuto"), MusicTrack("music-game-4", "Pippin the Hunchback"))
    }
}

object GameAudio {
    const val effectsKey = "magicmobile.boardSoundsEnabled"
    const val musicKey = "magicmobile.musicEnabled"
    const val effectsVolumeKey = "magicmobile.effectsVolume"
    const val musicVolumeKey = "magicmobile.musicVolume"
    const val defaultMusicVolume = 0.6

    private var context: Context? = null
    private val main = Handler(Looper.getMainLooper())
    private var pool: SoundPool? = null
    /** File name → loaded sample IDs (one per variant file). */
    private val samples = HashMap<String, Int>()
    private val loaded = HashSet<Int>()
    private val streams = HashMap<GameSound, ArrayDeque<Int>>()
    private val lastPlayed = HashMap<GameSound, Double>()
    private var musicPlayer: MediaPlayer? = null
    private var musicTarget = 0f
    var currentTrack: GameMusic? = null; private set
    var nowPlaying: MusicTrack? = null; private set
    private var previewing = false
    private val lastTrack = HashMap<GameMusic, String>()
    private var duckedUntil = 0.0

    val effectsEnabled: Boolean get() = AppPreferences.boolean(effectsKey, true).value
    /** A music level of zero is the same as music switched off. */
    val musicEnabled: Boolean get() = AppPreferences.boolean(musicKey, true).value && musicVolume > 0
    val effectsVolume: Float get() = AppPreferences.double(effectsVolumeKey, 0.9).value.toFloat()
    val musicVolume: Float get() = AppPreferences.double(musicVolumeKey, defaultMusicVolume).value.toFloat()
    fun isEnabled(category: GameSoundCategory): Boolean = AppPreferences.boolean(category.key, true).value

    fun init(context: Context) {
        this.context = context.applicationContext
        if (pool != null) return
        pool = SoundPool.Builder().setMaxStreams(12).setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build().apply {
            setOnLoadCompleteListener { _, sampleId, status -> if (status == 0) loaded += sampleId }
        }
    }

    private fun uptime(): Double = SystemClock.elapsedRealtime() / 1000.0

    private fun assetPath(file: String): String? {
        val assets = context?.assets ?: return null
        for (extension in listOf("wav", "m4a")) {
            val path = "audio/$file.$extension"
            if (runCatching { assets.openFd(path).close() }.isSuccess) return path
        }
        return null
    }

    private fun sample(file: String): Int? {
        samples[file]?.let { return it }
        val pool = pool ?: return null
        val path = assetPath(file) ?: return null
        val id = runCatching { context!!.assets.openFd(path).use { pool.load(it, 1) } }.getOrNull() ?: return null
        samples[file] = id
        return id
    }

    /** Warm up the samples used in the first seconds of a game so the first cast is instant. */
    fun preload(sounds: List<GameSound>) {
        for (sound in sounds) {
            if (sound.variants > 1) (1..sound.variants).forEach { sample("${sound.fileBase}-$it") } else sample(sound.fileBase)
        }
    }

    /** The board's sounds (cards, spells, combat), loaded when a game appears (NativeGameView) so a first arrival is not
     *  late while SoundPool decodes it. */
    val boardSounds: List<GameSound> get() = GameSound.entries.filter { it.category in setOf(GameSoundCategory.CARDS, GameSoundCategory.SPELLS, GameSoundCategory.COMBAT) }

    /** Seconds each file lasts (for a voice that should end as its card lands), read once from its header. */
    private val durations = HashMap<String, Double>()
    private fun duration(file: String): Double = durations.getOrPut(file) {
        val path = assetPath(file) ?: return 0.0
        runCatching {
            android.media.MediaMetadataRetriever().run {
                context!!.assets.openFd(path).use { setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                val ms = extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toDoubleOrNull() ?: 0.0
                release(); ms / 1000.0
            }
        }.getOrDefault(0.0)
    }

    /** Several cues due at the same moment (a combat flurry), started from one timer. */
    fun playTogether(cues: List<Pair<GameSound, Float>>, after: Double) {
        if (after > 0.005) main.postDelayed({ cues.forEach { (sound, volume) -> play(sound, 0.0, volume) } }, (after * 1000).toLong())
        else cues.forEach { (sound, volume) -> play(sound, 0.0, volume) }
    }

    /**
     * `audition` plays a sound from the Sound Lab even when its category is off. `endingWithin`: start late enough that
     * the sound finishes this long after `after` (a creature's voice ends as its card lands); a longer one starts then.
     */
    fun play(sound: GameSound, after: Double = 0.0, volume: Float = 1f, audition: Boolean = false, endingWithin: Double? = null) {
        if (!(effectsEnabled || audition) || !(effectsVolume > 0 || audition) || !(isEnabled(sound.category) || audition)) return
        if (after > 0.005) { main.postDelayed({ play(sound, 0.0, volume, audition, endingWithin) }, (after * 1000).toLong()); return }
        val now = uptime()
        if (!audition) lastPlayed[sound]?.let { if (now - it < sound.cooldown) return }
        lastPlayed[sound] = now
        val pool = pool ?: return
        val file = if (sound.variants > 1) "${sound.fileBase}-${Random.nextInt(1, sound.variants + 1)}" else sound.fileBase
        val id = sample(file) ?: return
        val wait = endingWithin?.let { maxOf(0.0, it - duration(file)) } ?: 0.0
        if (wait > 0.005) { main.postDelayed({ if (loaded.contains(id)) start(pool, id, sound, volume, audition) }, (wait * 1000).toLong()); return }
        if (!loaded.contains(id)) {
            // First use: SoundPool decodes asynchronously. Play once it lands, if it lands soon.
            main.postDelayed({ if (loaded.contains(id)) start(pool, id, sound, volume, audition) }, 120)
            return
        }
        start(pool, id, sound, volume, audition)
    }

    private fun start(pool: SoundPool, id: Int, sound: GameSound, scale: Float, audition: Boolean) {
        val level = minOf(1f, sound.volume * maxOf(effectsVolume, if (audition) 0.6f else 0f) * scale)
        val rate = if (sound.pitchVariation > 0) 1f + Random.nextFloat() * 2 * sound.pitchVariation - sound.pitchVariation else 1f
        val voices = streams.getOrPut(sound) { ArrayDeque() }
        // Steal the oldest voice when this cue already uses all of its copies.
        while (voices.size >= sound.voices) pool.stop(voices.removeFirst())
        val stream = pool.play(id, level, level, 1, 0, rate)
        if (stream != 0) voices.addLast(stream)
    }

    // Music

    /** The track this scene plays next: the player's pick, or a shuffle that never repeats the last track. */
    private fun nextTrack(scene: GameMusic): MusicTrack {
        val choice = AppPreferences.string(scene.choiceKey, "shuffle").value
        scene.tracks.firstOrNull { it.file == choice }?.let { return it }
        val others = scene.tracks.filter { it.file != lastTrack[scene] }
        return others.randomOrNull() ?: scene.tracks[0]
    }

    /** Crossfades to the playlist for `scene` (null fades music out). Safe to call repeatedly. */
    fun playMusic(scene: GameMusic?) {
        if (!musicEnabled || scene == null) { stopMusic(); currentTrack = null; return }
        if (currentTrack == scene && musicPlayer?.isPlaying == true && !previewing) return
        currentTrack = scene
        startTrack(nextTrack(scene), scene, 2.0)
    }

    private fun startTrack(track: MusicTrack, scene: GameMusic, fadeIn: Double) {
        stopMusic(1.2)
        val context = context ?: return
        val path = assetPath(track.file) ?: return
        val player = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                context.assets.openFd(path).use { setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                setVolume(0f, 0f)
                prepare()
            }
        }.getOrNull() ?: return
        player.setOnCompletionListener { finished -> trackFinished(finished) }
        player.start()
        musicPlayer = player
        nowPlaying = track
        lastTrack[scene] = track.file
        fade(player, 0f, targetMusicVolume(scene), fadeIn)
    }

    private fun trackFinished(player: MediaPlayer) {
        if (player !== musicPlayer) return
        val scene = currentTrack ?: return
        if (!musicEnabled) return
        previewing = false
        startTrack(nextTrack(scene), scene, 1.0)
    }

    /** Sound Lab: hear one track now. The scene's playlist returns with `endPreview`. */
    fun preview(track: MusicTrack, scene: GameMusic) {
        previewing = true
        val playing = currentTrack ?: scene
        currentTrack = playing
        startTrack(track, playing, 0.6)
    }

    fun endPreview() {
        if (!previewing) return
        previewing = false
        val scene = currentTrack
        if (scene == null || !musicEnabled) { stopMusic(); return }
        startTrack(nextTrack(scene), scene, 1.5)
    }

    private fun targetMusicVolume(scene: GameMusic): Float {
        val ducked = uptime() < duckedUntil
        return scene.level * maxOf(musicVolume, if (previewing) 0.5f else 0f) * (if (ducked) 0.25f else 1f)
    }

    private fun stopMusic(fade: Double = 0.8) {
        val player = musicPlayer ?: return
        musicPlayer = null
        nowPlaying = null
        player.setOnCompletionListener(null)
        fade(player, musicTarget, 0f, fade) { runCatching { player.stop() }; player.release() }
    }

    /** Linear volume ramp in 40 ms steps (AVAudioPlayer.setVolume(_:fadeDuration:)). */
    private fun fade(player: MediaPlayer, from: Float, to: Float, seconds: Double, done: (() -> Unit)? = null) {
        if (player === musicPlayer) musicTarget = to
        val steps = maxOf(1, (seconds * 25).toInt())
        for (step in 1..steps) {
            main.postDelayed({
                val level = from + (to - from) * step / steps
                runCatching { player.setVolume(level, level) }
                if (step == steps) done?.invoke()
            }, step * 40L)
        }
    }

    /** Lowers the music under a fanfare or stinger, then restores it. */
    fun duckMusic(seconds: Double) {
        val player = musicPlayer ?: return
        val scene = currentTrack ?: return
        duckedUntil = uptime() + seconds
        fade(player, musicTarget, targetMusicVolume(scene), 0.4)
        main.postDelayed({ if (musicPlayer === player) fade(player, musicTarget, targetMusicVolume(scene), 1.5) }, (seconds * 1000).toLong())
    }

    /** Apply changed settings (toggles, sliders or a new track pick) immediately. */
    fun settingsChanged(trackPickChanged: Boolean = false) {
        if (!musicEnabled && !previewing) { stopMusic(0.4); return }
        val scene = currentTrack ?: return
        val player = musicPlayer
        if (player != null && !trackPickChanged) fade(player, musicTarget, targetMusicVolume(scene), 0.3)
        else if (!previewing) startTrack(nextTrack(scene), scene, 1.2)
    }

    /** Remembers which playlist belongs on screen even while music is switched off. */
    fun setScene(scene: GameMusic) {
        previewing = false
        if (musicEnabled) playMusic(scene) else currentTrack = scene
    }

    /** Android pauses nothing for us; the activity calls these on stop/start. */
    fun suspend() { musicPlayer?.let { if (it.isPlaying) it.pause() } }

    /**
     * ON_STOP: stop the music and free every decoded sample, so a backgrounded game is less likely
     * to be ended by the system. `resume()` brings them back; samples reload as they are played.
     */
    fun releaseForBackground() {
        stopMusic(0.0)
        pool?.release(); pool = null
        samples.clear(); loaded.clear(); streams.clear()
    }

    fun resume() {
        context?.let { if (pool == null) init(it) }
        val scene = currentTrack ?: return
        if (!musicEnabled) return
        val player = musicPlayer
        if (player != null) { if (!player.isPlaying) player.start(); return }
        startTrack(nextTrack(scene), scene, 2.0)
    }
}

/** Your draws, read from consecutive snapshots (Swift GameSoundSignature). */
data class GameSoundSignature(val gameID: String, val handCount: Int) {
    constructor(snapshot: io.magicmobile.android.game.GameSnapshot) : this(snapshot.id,
        snapshot.players.firstOrNull { snapshot.isViewer(it.playerId) }?.zones?.visibleHandCount ?: 0)

    companion object {
        /** At most two draw sounds for a big draw, so an opening hand is a flourish, not a burst. */
        fun cues(old: GameSoundSignature, new: GameSoundSignature): List<GameSound> {
            if (old.gameID != new.gameID || new.handCount <= old.handCount) return emptyList()
            return List(minOf(2, new.handCount - old.handCount)) { GameSound.CARD_DRAW }
        }
    }
}
