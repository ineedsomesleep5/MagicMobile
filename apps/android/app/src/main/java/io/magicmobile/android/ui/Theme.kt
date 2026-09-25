package io.magicmobile.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import io.magicmobile.android.R

/**
 * Port of GameBoardTheme.swift, MagicPalette (ContentView.swift), BrandTheme (BrandUI.swift)
 * and GameBoardDesignTokens.swift. Colours are the exact iOS values.
 */
fun rgb(red: Double, green: Double, blue: Double, alpha: Double = 1.0) =
    Color(red.toFloat(), green.toFloat(), blue.toFloat(), alpha.toFloat())

object GameBoardTheme {
    val backgroundDeepMoss = rgb(0.02, 0.10, 0.07)
    val backgroundShadow = rgb(0.04, 0.03, 0.02)
    val charredOak = rgb(0.08, 0.045, 0.025)
    val oak = rgb(0.18, 0.10, 0.05)
    val oakHighlight = rgb(0.28, 0.16, 0.08)
    val leatherDark = rgb(0.045, 0.055, 0.075)
    val leatherMid = rgb(0.13, 0.15, 0.18)
    val carvedWood = rgb(0.29, 0.17, 0.09)
    val agedParchment = rgb(0.72, 0.58, 0.37)
    val parchmentLight = rgb(0.91, 0.84, 0.68)
    val parchmentInk = rgb(0.14, 0.09, 0.055)
    val antiqueGold = rgb(0.84, 0.65, 0.25)
    val brass = rgb(0.66, 0.47, 0.17)
    val brassShadow = rgb(0.31, 0.20, 0.07)
    val iron = rgb(0.055, 0.065, 0.085)
    val ironRaised = rgb(0.14, 0.16, 0.19)
    val mossMid = rgb(0.16, 0.25, 0.14)
    val parchmentShadow = rgb(0.46, 0.34, 0.20)
    val borderIron = rgb(0.20, 0.18, 0.15)
    val emeraldPriority = rgb(0.18, 0.78, 0.47)
    val arcaneBlue = rgb(0.27, 0.65, 0.85)
    val warningAmber = rgb(0.85, 0.54, 0.17)
    val dangerOxblood = rgb(0.54, 0.17, 0.15)
    val whiteReadable = rgb(0.97, 0.95, 0.90)
    val mutedText = rgb(0.79, 0.74, 0.65)
    val subduedText = rgb(0.61, 0.56, 0.48)

    val appBackground get() = backgroundShadow
    val panelBackground get() = leatherDark
    val raisedPanelBackground get() = ironRaised
    val panelBorder get() = brass.copy(alpha = 0.42f)
    val quietBorder get() = agedParchment.copy(alpha = 0.18f)
    val primaryText get() = whiteReadable
    val secondaryText get() = mutedText
    val tertiaryText get() = subduedText
}

object MagicPalette {
    val antiqueGold = GameBoardTheme.antiqueGold
    val brass = GameBoardTheme.brass
    val warningAmber = GameBoardTheme.warningAmber
    val moss = GameBoardTheme.mossMid
    val deepMoss = GameBoardTheme.backgroundDeepMoss
    val iron = GameBoardTheme.iron
    val parchment = GameBoardTheme.whiteReadable
    val parchmentShadow = GameBoardTheme.parchmentShadow
    val oxblood = GameBoardTheme.dangerOxblood
    val leather = GameBoardTheme.leatherMid
    val carvedWood = GameBoardTheme.carvedWood
    val emerald = GameBoardTheme.emeraldPriority
    val arcaneBlue = GameBoardTheme.arcaneBlue
    val legalEmerald = emerald
    val priorityArcane = arcaneBlue
    val panelParchment = GameBoardTheme.agedParchment
    val borderBronze = GameBoardTheme.brass
    val borderIron = GameBoardTheme.borderIron
    val laneWood = GameBoardTheme.oak
    val boardBackdrop = rgb(0.055, 0.085, 0.10)
}

object BrandTheme {
    val canvas = Color(0xFF141518)
    val surface = Color(0xFF25262A)
    val surfaceRaised = Color(46, 47, 52)
    val border = Color(0xFF45464A)
    val ink = Color(0xFFF3F1EC)
    val inkSecondary = Color(177, 178, 182)
    val ember = Color(0xFFFF8058)
    val emberLight = Color(0xFFFF9D7E)
    val rust = Color(0xFFA74429)
    val emberInk = Color(0xFF221713)
    val markCoral = Color(253, 102, 72)
    val markCream = Color(248, 246, 241)
    val markTile = Color(26, 27, 32)
    val emberGradient = Brush.linearGradient(listOf(emberLight, ember, rgb(0.93, 0.42, 0.27)))
    fun emberVertical() = Brush.verticalGradient(listOf(emberLight, ember, rgb(0.93, 0.42, 0.27)))
}

object GameBoardDesignTokens {
    object Spacing {
        val hairline = 2.dp; val laneGap = 4.dp; val extraSmall = 6.dp; val panelPadding = 8.dp; val small = 10.dp
        val medium = 12.dp; val large = 16.dp; val extraLarge = 24.dp; val sectionGap = 32.dp; val handCardGap = 8.dp
        val buttonGap = 6.dp; val sheetPadding = 12.dp
    }
    object Radius {
        val boardRoot = 28.dp; val heroPanel = 20.dp; val sheet = 18.dp; val largePanel = 12.dp; val panel = 8.dp
        val button = 7.dp; val card = 6.dp
    }
    object Motion { const val immediate = 120; const val fast = 180; const val standard = 260 }
    object Opacity { const val disabled = 0.42f; const val secondary = 0.72f; const val quietBorder = 0.18f; const val standardBorder = 0.42f; const val scrim = 0.66f }
    object Control { val minimumTouchTarget = 44.dp; val standardHeight = 48.dp; val prominentHeight = 54.dp; val compactGameHeight = 44.dp }
}

/** SwiftUI font designs. Apple's fonts cannot ship on Android: Inter, Source Serif 4 and Nunito stand in. */
enum class SfDesign { DEFAULT, SERIF, ROUNDED, MONOSPACED }

@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
object AppFonts {
    private fun family(resource: Int): FontFamily = FontFamily((100..900 step 100).map { weight ->
        Font(resource, FontWeight(weight), variationSettings = FontVariation.Settings(FontVariation.weight(weight)))
    })
    val sans: FontFamily by lazy { family(R.font.inter) }
    val serif: FontFamily by lazy { family(R.font.source_serif) }
    val rounded: FontFamily by lazy { family(R.font.nunito) }

    fun family(design: SfDesign): FontFamily = when (design) {
        SfDesign.DEFAULT -> sans
        SfDesign.SERIF -> serif
        SfDesign.ROUNDED -> rounded
        SfDesign.MONOSPACED -> FontFamily.Monospace
    }
}

/** SwiftUI weights: ultraLight…black. */
object SfWeight {
    val ultraLight = FontWeight.W100; val thin = FontWeight.W200; val light = FontWeight.W300; val regular = FontWeight.W400
    val medium = FontWeight.W500; val semibold = FontWeight.W600; val bold = FontWeight.W700; val heavy = FontWeight.W800
    val black = FontWeight.W900
}

/**
 * Width and line-height corrections that make the stand-in fonts set text like Apple's.
 * Measured by comparing advance widths (plus SF/New York's own size-specific tracking)
 * over board and menu strings: em to add per character, by weight and point size.
 */
object AppleFontMetrics {
    private val sizes = floatArrayOf(8f, 10f, 12f, 15f, 17f, 20f, 24f, 34f, 48f)
    private val weights = intArrayOf(400, 500, 600, 700, 800, 900)
    // Fitted on a device against CoreText widths of 40 UI strings (kerning included). SwiftUI weights resolve to
    // each Apple font's named instance (SF Black is wght 1000, New York Black 934).
    private val sans = arrayOf(
        floatArrayOf(0.0216f, 0.0117f, -0.0052f, -0.0240f, -0.0309f, -0.0447f, -0.0511f, -0.0534f, -0.0584f),
        floatArrayOf(0.0310f, 0.0119f, 0.0017f, -0.0116f, -0.0265f, -0.0333f, -0.0426f, -0.0453f, -0.0495f),
        floatArrayOf(0.0312f, 0.0167f, 0.0083f, -0.0114f, -0.0194f, -0.0310f, -0.0385f, -0.0400f, -0.0442f),
        floatArrayOf(0.0355f, 0.0269f, 0.0120f, -0.0020f, -0.0145f, -0.0228f, -0.0293f, -0.0312f, -0.0351f),
        floatArrayOf(0.0556f, 0.0325f, 0.0245f, 0.0059f, -0.0005f, -0.0099f, -0.0157f, -0.0151f, -0.0197f),
        floatArrayOf(0.0551f, 0.0476f, 0.0344f, 0.0189f, 0.0081f, -0.0029f, -0.0031f, -0.0036f, -0.0091f))
    private val serif = arrayOf(
        floatArrayOf(0.0528f, 0.0447f, 0.0336f, 0.0252f, 0.0181f, 0.0094f, 0.0068f, -0.0016f, -0.0118f),
        floatArrayOf(0.0637f, 0.0548f, 0.0445f, 0.0367f, 0.0324f, 0.0236f, 0.0196f, 0.0125f, 0.0021f),
        floatArrayOf(0.0767f, 0.0641f, 0.0527f, 0.0454f, 0.0415f, 0.0319f, 0.0284f, 0.0194f, 0.0116f),
        floatArrayOf(0.0756f, 0.0744f, 0.0633f, 0.0554f, 0.0498f, 0.0416f, 0.0385f, 0.0304f, 0.0218f),
        floatArrayOf(0.0978f, 0.0911f, 0.0811f, 0.0741f, 0.0682f, 0.0612f, 0.0579f, 0.0513f, 0.0442f),
        floatArrayOf(0.1138f, 0.1086f, 0.1025f, 0.0904f, 0.0829f, 0.0817f, 0.0751f, 0.0696f, 0.0614f))
    private val rounded = arrayOf(
        floatArrayOf(0.0321f, 0.0169f, 0.0092f, -0.0110f, -0.0174f, -0.0201f, -0.0252f, -0.0281f, -0.0323f),
        floatArrayOf(0.0421f, 0.0282f, 0.0193f, 0.0000f, -0.0058f, -0.0105f, -0.0133f, -0.0178f, -0.0231f),
        floatArrayOf(0.0498f, 0.0374f, 0.0261f, 0.0072f, 0.0021f, -0.0045f, -0.0090f, -0.0116f, -0.0151f),
        floatArrayOf(0.0536f, 0.0397f, 0.0246f, 0.0146f, 0.0017f, -0.0006f, -0.0025f, -0.0078f, -0.0104f),
        floatArrayOf(0.0656f, 0.0530f, 0.0376f, 0.0187f, 0.0161f, 0.0094f, 0.0074f, 0.0038f, -0.0012f),
        floatArrayOf(0.0720f, 0.0558f, 0.0468f, 0.0284f, 0.0195f, 0.0185f, 0.0127f, 0.0106f, 0.0068f))

    private fun interpolate(xs: FloatArray, ys: FloatArray, x: Float): Float {
        if (x <= xs.first()) return ys.first()
        if (x >= xs.last()) return ys.last()
        for (i in 0 until xs.size - 1) if (x <= xs[i + 1]) return ys[i] + (ys[i + 1] - ys[i]) * (x - xs[i]) / (xs[i + 1] - xs[i])
        return ys.last()
    }

    /** Em per character to add so the stand-in font matches Apple's width at this size and weight. */
    fun widthCorrection(design: SfDesign, weight: Int, size: Float): Float {
        val table = when (design) { SfDesign.DEFAULT -> sans; SfDesign.SERIF -> serif; SfDesign.ROUNDED -> rounded; SfDesign.MONOSPACED -> return 0f }
        val w = weight.coerceIn(400, 900)
        val row = weights.indexOfLast { it <= w }.coerceAtLeast(0)
        val next = (row + 1).coerceAtMost(weights.size - 1)
        val a = interpolate(sizes, table[row], size); val b = interpolate(sizes, table[next], size)
        return if (next == row) a else a + (b - a) * (w - weights[row]) / (weights[next] - weights[row]).toFloat()
    }

    /** Apple's line box (ascent + descent): SF Pro and SF Rounded 1.178 em, New York 1.193 em. */
    fun lineHeight(design: SfDesign): Float = when (design) { SfDesign.SERIF -> 1.193f; SfDesign.MONOSPACED -> 1.2f; else -> 1.178f }
}

/**
 * `.font(.system(size:weight:design:))` with the stand-in fonts corrected to Apple's widths
 * and line heights, so text wraps, truncates and stacks where it does on the iPhone.
 */
fun sf(size: Float, weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT, tracking: Float = 0f): TextStyle {
    val letterSpacing = AppleFontMetrics.widthCorrection(design, weight.weight, size) + if (size > 0f) tracking / size else 0f
    return TextStyle(fontFamily = AppFonts.family(design), fontWeight = weight, fontSize = size.sp, letterSpacing = letterSpacing.em,
        lineHeight = AppleFontMetrics.lineHeight(design).em,
        lineHeightStyle = androidx.compose.ui.text.style.LineHeightStyle(androidx.compose.ui.text.style.LineHeightStyle.Alignment.Proportional,
            androidx.compose.ui.text.style.LineHeightStyle.Trim.None))
}

/** Dynamic Type text styles at their default (Large) sizes. */
object SfText {
    fun largeTitle(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(34f, weight, design)
    fun title(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(28f, weight, design)
    fun title2(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(22f, weight, design)
    fun title3(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(20f, weight, design)
    fun headline(weight: FontWeight = SfWeight.semibold, design: SfDesign = SfDesign.DEFAULT) = sf(17f, weight, design)
    fun body(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(17f, weight, design)
    fun callout(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(16f, weight, design)
    fun subheadline(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(15f, weight, design)
    fun footnote(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(13f, weight, design)
    fun caption(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(12f, weight, design)
    fun caption2(weight: FontWeight = SfWeight.regular, design: SfDesign = SfDesign.DEFAULT) = sf(11f, weight, design)
}

object MagicTypography {
    val hero get() = SfText.largeTitle(SfWeight.bold, SfDesign.SERIF)
    val screenTitle get() = SfText.title(SfWeight.bold, SfDesign.SERIF)
    val sectionTitle get() = SfText.title3(SfWeight.semibold, SfDesign.SERIF)
    val body get() = SfText.body()
    val bodyEmphasis get() = SfText.body(SfWeight.semibold)
    val button get() = SfText.headline(SfWeight.bold)
    val label get() = SfText.caption(SfWeight.bold)
    val caption get() = SfText.caption()
    val gameLabel get() = SfText.caption2(SfWeight.bold)
    val gameValue get() = SfText.footnote(SfWeight.semibold)
}

enum class MagicPanelMaterial { OAK, LEATHER, IRON, PARCHMENT }
enum class MagicPanelProminence { QUIET, STANDARD, ELEVATED }
enum class MagicStatusTone { NEUTRAL, POSITIVE, WARNING, DANGER, ARCANE }

val MagicStatusTone.color: Color get() = when (this) {
    MagicStatusTone.NEUTRAL -> GameBoardTheme.mutedText
    MagicStatusTone.POSITIVE -> GameBoardTheme.emeraldPriority
    MagicStatusTone.WARNING -> GameBoardTheme.warningAmber
    MagicStatusTone.DANGER -> GameBoardTheme.dangerOxblood
    MagicStatusTone.ARCANE -> GameBoardTheme.arcaneBlue
}

val MagicPanelMaterial.fill: Brush get() = Brush.linearGradient(when (this) {
    MagicPanelMaterial.OAK -> listOf(GameBoardTheme.oakHighlight, GameBoardTheme.oak, GameBoardTheme.charredOak)
    MagicPanelMaterial.LEATHER -> listOf(GameBoardTheme.leatherMid, GameBoardTheme.leatherDark)
    MagicPanelMaterial.IRON -> listOf(GameBoardTheme.ironRaised, GameBoardTheme.iron)
    MagicPanelMaterial.PARCHMENT -> listOf(GameBoardTheme.parchmentLight, GameBoardTheme.agedParchment)
})

val MagicPanelMaterial.foreground: Color get() = if (this == MagicPanelMaterial.PARCHMENT) GameBoardTheme.parchmentInk else GameBoardTheme.primaryText

/** `.magicPanel(...)`: gradient fill, bronze hairline and a prominence-matched shadow. */
fun Modifier.magicPanel(material: MagicPanelMaterial = MagicPanelMaterial.LEATHER, prominence: MagicPanelProminence = MagicPanelProminence.STANDARD,
                        cornerRadius: Dp = GameBoardDesignTokens.Radius.largePanel, padding: Dp = GameBoardDesignTokens.Spacing.panelPadding): Modifier {
    val shape = RoundedCornerShape(cornerRadius)
    val borderOpacity = when (prominence) { MagicPanelProminence.QUIET -> 0.34f; MagicPanelProminence.STANDARD -> 0.58f; MagicPanelProminence.ELEVATED -> 0.82f }
    val shadowed = when (prominence) {
        MagicPanelProminence.QUIET -> this
        MagicPanelProminence.STANDARD -> this.shadow(10.dp, shape, ambientColor = Color.Black.copy(alpha = 0.34f), spotColor = Color.Black.copy(alpha = 0.34f))
        MagicPanelProminence.ELEVATED -> this.shadow(18.dp, shape, ambientColor = Color.Black.copy(alpha = 0.48f), spotColor = Color.Black.copy(alpha = 0.48f))
    }
    return shadowed.background(material.fill, shape).border(1.dp, GameBoardTheme.panelBorder.copy(alpha = GameBoardTheme.panelBorder.alpha * borderOpacity), shape)
        .padding(padding)
}

fun Modifier.magicBadge(tone: MagicStatusTone = MagicStatusTone.NEUTRAL): Modifier {
    val color = tone.color
    return this.background(color.copy(alpha = if (tone == MagicStatusTone.NEUTRAL) 0.12f else 0.15f), CircleShape)
        .border(1.dp, color.copy(alpha = 0.5f), CircleShape).padding(horizontal = 9.dp)
}
