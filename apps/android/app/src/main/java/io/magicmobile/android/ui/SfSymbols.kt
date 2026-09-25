package io.magicmobile.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.NoteAdd
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.Archive
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.CropPortrait
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Eco
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.HourglassEmpty
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material.icons.outlined.NightsStay
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.RemoveRedEye
import androidx.compose.material.icons.outlined.SkipNext
import androidx.compose.material.icons.outlined.Style
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.graphics.vector.VectorGroup
import androidx.compose.ui.graphics.vector.VectorPath
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * SF Symbols cannot ship on Android. Each symbol the iOS app draws maps to the closest
 * Material icon; the few with no Material counterpart (crown, skull, sparkle) are drawn here.
 */
object SfSymbols {
    fun vector(name: String): ImageVector = when (name) {
        "plus" -> Icons.Filled.Add
        "square.and.arrow.up" -> Icons.Filled.IosShare
        "list.bullet.rectangle" -> Icons.AutoMirrored.Filled.ListAlt
        "chevron.right" -> Icons.Filled.ChevronRight
        "chevron.left" -> Icons.Filled.ChevronLeft
        "chevron.down" -> Icons.Filled.ExpandMore
        "chevron.up" -> Icons.Filled.ExpandLess
        "chevron.up.chevron.down" -> Icons.Filled.UnfoldMore
        "checkmark" -> Icons.Filled.Check
        "checkmark.circle" -> Icons.Outlined.CheckCircle
        "checkmark.circle.fill" -> Icons.Filled.CheckCircle
        "checkmark.shield" -> Icons.Outlined.VerifiedUser
        "checkmark.shield.fill" -> Icons.Filled.VerifiedUser
        "checkmark.seal.fill" -> Icons.Filled.Verified
        "xmark" -> Icons.Filled.Close
        "xmark.circle" -> Icons.Outlined.Cancel
        "xmark.circle.fill" -> Icons.Filled.Cancel
        "person.2.fill" -> Icons.Filled.People
        "person.crop.circle" -> Icons.Filled.AccountCircle
        "person.crop.square" -> Icons.Filled.AccountBox
        "person.crop.rectangle.stack" -> Icons.Filled.RecentActors
        "gearshape.fill" -> Icons.Filled.Settings
        "arrow.uturn.backward" -> Icons.AutoMirrored.Filled.Undo
        "arrow.uturn.forward" -> Icons.AutoMirrored.Filled.Redo
        "arrow.counterclockwise" -> Icons.Filled.Replay
        "arrow.clockwise" -> Icons.Filled.Refresh
        "arrow.triangle.2.circlepath" -> Icons.Filled.Sync
        "arrow.up" -> Icons.Filled.ArrowUpward
        "arrow.up.arrow.down" -> Icons.Filled.SwapVert
        "arrow.up.right.square" -> Icons.AutoMirrored.Filled.OpenInNew
        "arrow.turn.down.right" -> Icons.Filled.SubdirectoryArrowRight
        "arrow.triangle.branch" -> Icons.AutoMirrored.Filled.CallSplit
        "arrow.left.and.right.circle.fill" -> Icons.Filled.SwapHorizontalCircle
        "arrow.down.to.line.circle.fill" -> Icons.Filled.DownloadForOffline
        "trash" -> Icons.Outlined.Delete
        "square.and.arrow.down" -> Icons.Filled.SaveAlt
        "square.and.arrow.down.fill" -> Icons.Filled.Download
        "sparkles" -> Icons.Filled.AutoAwesome
        "sparkle" -> Sparkle
        "wand.and.stars" -> Icons.Filled.AutoFixHigh
        "rectangle.stack", "rectangle.stack.fill" -> Icons.Filled.Style
        "rectangle.stack.badge.plus", "plus.rectangle.on.rectangle" -> Icons.Filled.LibraryAdd
        "rectangle.portrait" -> Icons.Outlined.CropPortrait
        "rectangle.portrait.on.rectangle.portrait" -> Icons.Filled.FilterNone
        "rectangle.portrait.and.arrow.right" -> Icons.AutoMirrored.Filled.ExitToApp
        "square.stack.3d.up" -> Icons.Filled.Layers
        "square.grid.2x2" -> Icons.Outlined.GridView
        "square.grid.2x2.fill" -> Icons.Filled.GridView
        "plus.circle" -> Icons.Outlined.AddCircleOutline
        "plus.circle.fill" -> Icons.Filled.AddCircle
        "minus" -> Icons.Filled.Remove
        "minus.circle" -> Icons.Outlined.RemoveCircleOutline
        "minus.circle.fill" -> Icons.Filled.RemoveCircle
        "pencil" -> Icons.Filled.Edit
        "magnifyingglass" -> Icons.Filled.Search
        "exclamationmark.triangle" -> Icons.Outlined.WarningAmber
        "exclamationmark.triangle.fill" -> Icons.Filled.Warning
        "exclamationmark.bubble.fill" -> Icons.Filled.Feedback
        "exclamationmark.shield.fill" -> Icons.Filled.GppMaybe
        "crown", "crown.fill" -> Crown
        "skull.fill" -> Skull
        "slider.horizontal.3" -> Icons.Filled.Tune
        "number" -> Icons.Filled.Tag
        "info.circle" -> Icons.Outlined.Info
        "info.circle.fill" -> Icons.Filled.Info
        "doc", "doc.text" -> Icons.Outlined.Description
        "doc.plaintext" -> Icons.Filled.Article
        "doc.on.doc" -> Icons.Filled.ContentCopy
        "doc.text.magnifyingglass" -> Icons.Filled.FindInPage
        "doc.badge.plus" -> Icons.AutoMirrored.Filled.NoteAdd
        "doc.badge.arrow.up" -> Icons.Filled.UploadFile
        "shield.lefthalf.filled", "shield.fill", "bolt.shield.fill" -> Icons.Filled.Shield
        "scope" -> Icons.Filled.GpsFixed
        "play.fill" -> Icons.Filled.PlayArrow
        "photo" -> Icons.Outlined.Image
        "photo.on.rectangle" -> Icons.Outlined.Collections
        "photo.on.rectangle.angled" -> Icons.Filled.Collections
        "network" -> Icons.Filled.Hub
        "network.slash" -> Icons.Filled.CloudOff
        "line.3.horizontal.decrease" -> Icons.Filled.FilterList
        "hourglass" -> Icons.Outlined.HourglassEmpty
        "flag.fill" -> Icons.Filled.Flag
        "flag.checkered" -> Icons.Filled.SportsScore
        "eye" -> Icons.Outlined.Visibility
        "eye.fill" -> Icons.Filled.Visibility
        "eye.trianglebadge.exclamationmark" -> Icons.Outlined.RemoveRedEye
        "ellipsis", "ellipsis.circle" -> Icons.Filled.MoreHoriz
        "bolt" -> Icons.Outlined.Bolt
        "bolt.fill" -> Icons.Filled.Bolt
        "bolt.circle.fill" -> Icons.Filled.OfflineBolt
        "waveform" -> Icons.Filled.GraphicEq
        "tray.full" -> Icons.Filled.Inbox
        "text.viewfinder" -> Icons.Filled.DocumentScanner
        "text.book.closed" -> Icons.AutoMirrored.Filled.MenuBook
        "tag" -> Icons.Outlined.LocalOffer
        "scroll.fill" -> Icons.Filled.HistoryEdu
        "paintpalette.fill" -> Icons.Filled.Palette
        "moon.stars" -> Icons.Outlined.NightsStay
        "list.number" -> Icons.Filled.FormatListNumbered
        "link" -> Icons.Filled.Link
        "leaf" -> Icons.Outlined.Eco
        "leaf.fill" -> Icons.Filled.Eco
        "ladybug.fill" -> Icons.Filled.BugReport
        "heart.fill" -> Icons.Filled.Favorite
        "hand.thumbsup.fill" -> Icons.Filled.ThumbUp
        "hand.raised" -> Icons.Outlined.PanTool
        "hand.wave.fill" -> Icons.Filled.WavingHand
        "hands.clap.fill" -> Icons.Filled.Celebration
        "globe" -> Icons.Filled.Language
        "forward.end" -> Icons.Outlined.SkipNext
        "forward.end.fill" -> Icons.Filled.SkipNext
        "ellipsis.circle.fill" -> Icons.Filled.MoreHoriz
        "list.bullet.rectangle.portrait" -> Icons.AutoMirrored.Filled.ListAlt
        "speaker.wave.2.fill" -> Icons.Filled.VolumeUp
        "stop.fill" -> Icons.Filled.Stop
        "trophy.fill" -> Icons.Filled.EmojiEvents
        "forward.fill" -> Icons.Filled.FastForward
        "flame.fill" -> Icons.Filled.LocalFireDepartment
        "externaldrive" -> Icons.Filled.Storage
        "dice" -> Icons.Filled.Casino
        "books.vertical" -> Icons.AutoMirrored.Outlined.LibraryBooks
        "books.vertical.fill" -> Icons.AutoMirrored.Filled.LibraryBooks
        "bell" -> Icons.Outlined.Notifications
        "archivebox" -> Icons.Outlined.Archive
        "circle.fill" -> Icons.Filled.Circle
        "circle.hexagongrid.fill" -> Icons.Filled.Grain
        "hourglass.bottomhalf.filled" -> Icons.Filled.HourglassBottom
        "arrow.forward" -> Icons.Filled.ArrowForward
        else -> Icons.Filled.Circle
    }

    /** A crown: three points above a band. */
    val Crown: ImageVector by lazy {
        ImageVector.Builder("crown", 24.dp, 24.dp, 24f, 24f).path(fill = SolidColor(Color.White)) {
            moveTo(3f, 7f); lineTo(7.5f, 11f); lineTo(12f, 4f); lineTo(16.5f, 11f); lineTo(21f, 7f)
            lineTo(19.5f, 17f); lineTo(4.5f, 17f); close()
            moveTo(4.5f, 18.5f); lineTo(19.5f, 18.5f); lineTo(19.5f, 20.5f); lineTo(4.5f, 20.5f); close()
        }.build()
    }

    /** A skull with eye sockets and teeth. */
    val Skull: ImageVector by lazy {
        ImageVector.Builder("skull", 24.dp, 24.dp, 24f, 24f).path(fill = SolidColor(Color.White), pathFillType = androidx.compose.ui.graphics.PathFillType.EvenOdd) {
            moveTo(12f, 2f)
            curveTo(6.8f, 2f, 3f, 5.6f, 3f, 10.4f); curveTo(3f, 13.2f, 4.4f, 15.3f, 6.5f, 16.5f)
            lineTo(6.5f, 20f); curveTo(6.5f, 21.1f, 7.4f, 22f, 8.5f, 22f); lineTo(15.5f, 22f)
            curveTo(16.6f, 22f, 17.5f, 21.1f, 17.5f, 20f); lineTo(17.5f, 16.5f)
            curveTo(19.6f, 15.3f, 21f, 13.2f, 21f, 10.4f); curveTo(21f, 5.6f, 17.2f, 2f, 12f, 2f); close()
            moveTo(8.5f, 9f); curveTo(9.9f, 9f, 11f, 10.1f, 11f, 11.5f); curveTo(11f, 12.9f, 9.9f, 14f, 8.5f, 14f)
            curveTo(7.1f, 14f, 6f, 12.9f, 6f, 11.5f); curveTo(6f, 10.1f, 7.1f, 9f, 8.5f, 9f); close()
            moveTo(15.5f, 9f); curveTo(16.9f, 9f, 18f, 10.1f, 18f, 11.5f); curveTo(18f, 12.9f, 16.9f, 14f, 15.5f, 14f)
            curveTo(14.1f, 14f, 13f, 12.9f, 13f, 11.5f); curveTo(13f, 10.1f, 14.1f, 9f, 15.5f, 9f); close()
            moveTo(12f, 14.5f); lineTo(13.2f, 16.8f); lineTo(10.8f, 16.8f); close()
            moveTo(9f, 18.5f); lineTo(10.2f, 18.5f); lineTo(10.2f, 20.5f); lineTo(9f, 20.5f); close()
            moveTo(11.4f, 18.5f); lineTo(12.6f, 18.5f); lineTo(12.6f, 20.5f); lineTo(11.4f, 20.5f); close()
            moveTo(13.8f, 18.5f); lineTo(15f, 18.5f); lineTo(15f, 20.5f); lineTo(13.8f, 20.5f); close()
        }.build()
    }

    /** SF "sparkle": a four-pointed star. */
    val Sparkle: ImageVector by lazy {
        ImageVector.Builder("sparkle", 24.dp, 24.dp, 24f, 24f).path(fill = SolidColor(Color.White)) {
            moveTo(12f, 1f); curveTo(12.8f, 7.6f, 16.4f, 11.2f, 23f, 12f)
            curveTo(16.4f, 12.8f, 12.8f, 16.4f, 12f, 23f); curveTo(11.2f, 16.4f, 7.6f, 12.8f, 1f, 12f)
            curveTo(7.6f, 11.2f, 11.2f, 7.6f, 12f, 1f); close()
        }.build()
    }
}

private val glyphExtents = HashMap<ImageVector, Float>()

/** The share of its viewport a Material glyph covers (its larger side, from the path bounds). */
private fun glyphExtent(vector: ImageVector): Float = synchronized(glyphExtents) {
    glyphExtents.getOrPut(vector) {
        var bounds: androidx.compose.ui.geometry.Rect? = null
        fun visit(group: VectorGroup) {
            for (node in group) when (node) {
                is VectorGroup -> visit(node)
                is VectorPath -> {
                    val b = PathParser().addPathNodes(node.pathData).toPath().getBounds()
                    if (!b.isEmpty) bounds = bounds?.let { androidx.compose.ui.geometry.Rect(minOf(it.left, b.left), minOf(it.top, b.top),
                        maxOf(it.right, b.right), maxOf(it.bottom, b.bottom)) } ?: b
                }
            }
        }
        visit(vector.root)
        bounds?.let { maxOf(it.width / vector.viewportWidth, it.height / vector.viewportHeight) }?.takeIf { it > 0f } ?: (20f / 24f)
    }
}

/**
 * `Image(systemName:)` with a tint and a point size. An SF symbol draws about 1–1.15× its point
 * size, while a Material glyph covers 50–83% of its box: the box is scaled so a full glyph matches,
 * and small glyphs (skip, stop, chevrons) are raised to about the point size. The layout frame is
 * 1.1× the point size, like SwiftUI's symbol frame; the glyph may draw past it.
 */
@Composable
fun SfImage(name: String, tint: Color, size: Dp, modifier: Modifier = Modifier, contentDescription: String? = null) {
    val vector = SfSymbols.vector(name)
    val boost = if (name == "xmark") 1f else (0.75f / glyphExtent(vector)).coerceIn(1f, 1.7f)
    Box(modifier.size(size * 1.1f), contentAlignment = Alignment.Center) {
        Icon(vector, contentDescription, Modifier.requiredSize(size * 1.32f * boost), tint = tint)
    }
}
