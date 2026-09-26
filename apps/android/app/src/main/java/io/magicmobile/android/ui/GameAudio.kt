package io.magicmobile.android.ui

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.magicmobile.android.game.BoardFXTint
import kotlin.random.Random

/**
 * Port of apps/ios/MagicMobile/GameAudio.swift. The same recordings (staged from the iOS bundle
 * by prepare_audio.py), mix levels, voices, cooldowns and playlists. Effects mix with the
 * player's own audio: no audio focus is taken, like the iOS ambient session.
 */
enum class GameSoundCategory(val rawValue: String, val title: String, val detail: String) {
    INTERFACE("interface", "Menus & alerts", "Confirm buttons, sheets, “your decision” and emotes."),
    CARDS("cards", "Cards & board", "Drawing, playing, lands, creatures, tokens and counters."),
    SPELLS("spells", "Spells", "A cast sound for each color, big spells and your commander."),
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
    CARD_DRAW("card-draw", GameSoundCategory.CARDS, "Draw a card"), CARD_PICKUP("card-pickup", GameSoundCategory.CARDS, "Pick up a card"),
    CARD_PLAY("card-play", GameSoundCategory.CARDS, "Play a card"), SHUFFLE("shuffle", GameSoundCategory.CARDS, "Shuffle (mulligan)"),
    LAND_DROP("land-drop", GameSoundCategory.CARDS, "Land"), CREATURE_ENTER("creature-enter", GameSoundCategory.CARDS, "Creature arrives"),
    TOKEN_CREATE("token-create", GameSoundCategory.CARDS, "Token"), COUNTER("counter", GameSoundCategory.CARDS, "Counter"),
    ABILITY("ability", GameSoundCategory.CARDS, "Your ability"),
    CAST_WHITE("cast-white", GameSoundCategory.SPELLS, "White spell"), CAST_BLUE("cast-blue", GameSoundCategory.SPELLS, "Blue spell"),
    CAST_BLACK("cast-black", GameSoundCategory.SPELLS, "Black spell"), CAST_RED("cast-red", GameSoundCategory.SPELLS, "Red spell"),
    CAST_GREEN("cast-green", GameSoundCategory.SPELLS, "Green spell"), CAST_COLORLESS("cast-colorless", GameSoundCategory.SPELLS, "Colorless spell"),
    CAST_MULTI("cast-multi", GameSoundCategory.SPELLS, "Multicolor spell"), SPELL_BIG("spell-big", GameSoundCategory.SPELLS, "Big spell"),
    COMMANDER_CAST("commander-cast", GameSoundCategory.SPELLS, "Commander"),
    ATTACK("attack", GameSoundCategory.COMBAT, "Attack"), BLOCK("block", GameSoundCategory.COMBAT, "Block"),
    STRIKE("strike", GameSoundCategory.COMBAT, "Creature hit"), PLAYER_HIT("player-hit", GameSoundCategory.COMBAT, "You’re hit"),
    DEATH("death", GameSoundCategory.COMBAT, "Creature dies"), EXILE("exile", GameSoundCategory.COMBAT, "Exile"),
    LIFE_GAIN("life-gain", GameSoundCategory.COMBAT, "Life gain"), LIFE_LOSS("life-loss", GameSoundCategory.COMBAT, "Life loss"),
    TURN_YOU("turn-you", GameSoundCategory.MOMENTS, "Your turn"), VERSUS("versus", GameSoundCategory.MOMENTS, "Versus"),
    VICTORY("victory", GameSoundCategory.MOMENTS, "Victory"), DEFEAT("defeat", GameSoundCategory.MOMENTS, "Defeat"),
    DICE_ROLL("dice-roll", GameSoundCategory.MOMENTS, "Dice roll"), DICE_LAND("dice-land", GameSoundCategory.MOMENTS, "Die lands");

    /** Numbered files ("card-draw-1…3") give repeated sounds natural variety. */
    val variants: Int get() = if (this == CARD_DRAW || this == ATTACK) 3 else 1

    /** Mix level: interface quiet, the board clear, big moments on top. */
    val volume: Float get() = when (this) {
        UI_TAP, UI_TICK, UI_TOGGLE, UI_BACK, UI_OPEN, UI_CLOSE -> 0.5f
        UI_CONFIRM, UI_ERROR, PAGE_FLIP, EMOTE -> 0.65f
        RESPONSE_ALERT, MENU_PLAY -> 0.8f
        CARD_DRAW, CARD_PICKUP, COUNTER, ABILITY -> 0.7f
        CARD_PLAY, SHUFFLE, LAND_DROP, CREATURE_ENTER, TOKEN_CREATE -> 0.85f
        CAST_WHITE, CAST_BLUE, CAST_BLACK, CAST_RED, CAST_GREEN, CAST_COLORLESS, CAST_MULTI -> 0.85f
        SPELL_BIG, COMMANDER_CAST, ATTACK, BLOCK, STRIKE, PLAYER_HIT -> 0.9f
        DEATH, EXILE, LIFE_GAIN, LIFE_LOSS -> 0.75f
        TURN_YOU, VERSUS, VICTORY, DEFEAT -> 0.9f
        DICE_ROLL, DICE_LAND -> 0.85f
    }

    /** A little pitch variation keeps repeated foley from sounding mechanical; musical cues stay in tune. */
    val pitchVariation: Float get() = when (this) {
        CARD_DRAW, CARD_PICKUP, CARD_PLAY, LAND_DROP, CREATURE_ENTER, STRIKE, PLAYER_HIT, DEATH, ATTACK, BLOCK, COUNTER, TOKEN_CREATE, SHUFFLE, DICE_LAND -> 0.04f
        else -> 0f
    }

    /** Simultaneous copies allowed (a board wipe plays several deaths at once). */
    val voices: Int get() = when (this) {
        STRIKE, DEATH, CARD_DRAW, TOKEN_CREATE, CREATURE_ENTER -> 3
        VICTORY, DEFEAT, VERSUS, TURN_YOU, MENU_PLAY, RESPONSE_ALERT -> 1
        else -> 2
    }

    /** Minimum seconds between two plays of this cue. */
    val cooldown: Double get() = when (this) {
        UI_TICK -> 0.08
        CARD_DRAW, UI_TAP -> 0.1
        STRIKE, DEATH, TOKEN_CREATE, CREATURE_ENTER, LAND_DROP -> 0.12
        COUNTER, LIFE_GAIN -> 0.3
        CAST_WHITE, CAST_BLUE, CAST_BLACK, CAST_RED, CAST_GREEN, CAST_COLORLESS, CAST_MULTI -> 0.25
        ABILITY -> 0.8
        RESPONSE_ALERT -> 1.2
        TURN_YOU, VERSUS, VICTORY, DEFEAT -> 1.5
        else -> 0.12
    }

    companion object {
        fun cast(tint: BoardFXTint): GameSound = when (tint) {
            BoardFXTint.WHITE -> CAST_WHITE; BoardFXTint.BLUE -> CAST_BLUE; BoardFXTint.BLACK -> CAST_BLACK; BoardFXTint.RED -> CAST_RED
            BoardFXTint.GREEN -> CAST_GREEN; BoardFXTint.MULTICOLOR -> CAST_MULTI; BoardFXTint.COLORLESS -> CAST_COLORLESS
        }
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
            if (sound.variants > 1) (1..sound.variants).forEach { sample("${sound.rawValue}-$it") } else sample(sound.rawValue)
        }
    }

    /** `audition` plays a sound from the Sound Lab even when its category is off. */
    fun play(sound: GameSound, after: Double = 0.0, volume: Float = 1f, audition: Boolean = false) {
        if (!(effectsEnabled || audition) || !(effectsVolume > 0 || audition) || !(isEnabled(sound.category) || audition)) return
        if (after > 0.005) { main.postDelayed({ play(sound, 0.0, volume, audition) }, (after * 1000).toLong()); return }
        val now = uptime()
        if (!audition) lastPlayed[sound]?.let { if (now - it < sound.cooldown) return }
        lastPlayed[sound] = now
        val pool = pool ?: return
        val file = if (sound.variants > 1) "${sound.rawValue}-${Random.nextInt(1, sound.variants + 1)}" else sound.rawValue
        val id = sample(file) ?: return
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
    fun resume() {
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
