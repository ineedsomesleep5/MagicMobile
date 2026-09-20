package io.magicmobile.android

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Switch
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Mana rendering that matches the iOS build: the same shipped artwork for the six basic
 * symbols, and the same lettered-circle fallback for everything else. The drawables are
 * generated from the iOS mana-*.svg files, so a pip looks identical on both platforms.
 */
object ManaSymbols {
    private val drawables = mapOf(
        "W" to R.drawable.mana_w,
        "U" to R.drawable.mana_u,
        "B" to R.drawable.mana_b,
        "R" to R.drawable.mana_r,
        "G" to R.drawable.mana_g,
        "C" to R.drawable.mana_c,
    )

    /** `{2}{G}{W}` -> ["2","G","W"]. Malformed costs yield nothing rather than raw braces. */
    fun tokens(cost: String?): List<String> {
        if (cost.isNullOrBlank()) return emptyList()
        return Regex("\\{([^{}]{1,12})\\}").findAll(cost).map { it.groupValues[1] }.toList()
    }

    fun drawable(symbol: String): Int? = drawables[symbol.trim().uppercase()]
}

@Composable
fun ManaCost(cost: String?, size: Int = 16, modifier: Modifier = Modifier) {
    if(cost?.contains("//") == true) {
        Row(modifier,horizontalArrangement=Arrangement.spacedBy(4.dp),verticalAlignment=Alignment.CenterVertically) {
            cost.split("//").forEachIndexed { index,half ->
                if(index>0)Text("//")
                ManaCost(half,size)
            }
        }
        return
    }
    val tokens = ManaSymbols.tokens(cost)
    if (tokens.isEmpty()) return
    Row(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) { tokens.forEach { ManaSymbol(it, size) } }
}

@Composable
fun ManaSymbol(symbol: String, size: Int = 16) {
    val resource = ManaSymbols.drawable(symbol)
    if (resource != null) {
        Image(
            painter = painterResource(resource),
            contentDescription = when(symbol.trim().uppercase()){"W"->"White mana";"U"->"Blue mana";"B"->"Black mana";"R"->"Red mana";"G"->"Green mana";"C"->"Colorless mana";else->symbol},
            modifier = Modifier.size(size.dp),
        )
    } else {
        // Generic costs, {X} and hybrids ship no artwork on either platform.
        Box(
            Modifier.size(size.dp)
                .clip(CircleShape)
                .background(Color(0xFFCAC5C0))
                .border(1.dp, Color.Black.copy(alpha = 0.45f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                symbol,
                fontSize = (size * 0.52).sp,
                fontWeight = FontWeight.Black,
                color = Color(0xFF0D0F0F),
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
        }
    }
}

/** Shown in place of artwork until the player opts in, matching the iOS wording. */
@Composable
fun ArtworkHint() {
    Text(
        "Card images are off. Enable them in the deck list to let Scryfall receive the card names shown here.",
        fontSize = 12.sp,
        color = Color(0xFF57534E),
        textAlign = TextAlign.Center,
        modifier = Modifier.padding(16.dp),
    )
}

/**
 * Opt-in for card images, worded and defaulted like the iOS toggle: off until asked for,
 * and explicit that turning it on sends card names to Scryfall.
 */
@Composable
fun ArtworkConsentRow() {
    val context = LocalContext.current
    var enabled by remember { mutableStateOf(Artwork.enabled(context)) }
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text("Scryfall live images", fontWeight = FontWeight.SemiBold)
            Text(
                if (enabled) "Downloaded art first, then high-quality online art. Shares displayed card names and your IP with Scryfall."
                else "Downloaded art stays available offline. Turn on for high-quality online images.",
                fontSize = 12.sp,
                color = Color(0xFF57534E),
            )
        }
        Switch(checked = enabled, onCheckedChange = { enabled = it; Artwork.setEnabled(context, it) })
    }
}
