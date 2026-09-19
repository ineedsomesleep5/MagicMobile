package io.magicmobile.android

import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

internal data class BattlefieldTheme(val id:String,val label:String)
internal val BattlefieldThemes=listOf(
    BattlefieldTheme("arena","Stone Arena"),
    BattlefieldTheme("midnight","Midnight"),
    BattlefieldTheme("wood","Classic Wood"),
    BattlefieldTheme("moss","Moss Sanctuary"),
    BattlefieldTheme("ember","Obsidian Ember"),
    BattlefieldTheme("tide","Tidal Slate"),
)

internal object BattlefieldPreference {
    private const val PREFS="magicmobile.appearance"
    private const val KEY="battlefield"
    fun get(context:Context)=context.getSharedPreferences(PREFS,Context.MODE_PRIVATE).getString(KEY,"arena")?.takeIf{value->BattlefieldThemes.any{it.id==value}} ?: "arena"
    fun set(context:Context,value:String){if(BattlefieldThemes.any{it.id==value})context.getSharedPreferences(PREFS,Context.MODE_PRIVATE).edit().putString(KEY,value).apply()}
}

@Composable internal fun BattlefieldBackground(content:@Composable BoxScope.()->Unit) {
    val context=LocalContext.current
    val theme=BattlefieldPreference.get(context)
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF0E1619),Color(0xFF1A2929))))) {
        if(theme!="midnight") {
            val resource=context.resources.getIdentifier("battlefield_$theme","drawable",context.packageName)
            if(resource!=0)Image(painterResource(resource),null,Modifier.fillMaxSize(),contentScale=ContentScale.Crop)
        }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha=.20f)))
        content()
    }
}

@Composable internal fun BattlefieldThemeSelector() {
    val context=LocalContext.current
    var selected by remember{mutableStateOf(BattlefieldPreference.get(context))}
    Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {
        Text("Battlefield",style=MaterialTheme.typography.titleLarge)
        Text("Choose the table used during local games.",style=MaterialTheme.typography.bodySmall)
        LazyRow(horizontalArrangement=Arrangement.spacedBy(8.dp),contentPadding=PaddingValues(vertical=4.dp)) {
            items(BattlefieldThemes,key={it.id}){theme->FilterChip(selected=selected==theme.id,onClick={selected=theme.id;BattlefieldPreference.set(context,theme.id)},label={Text(theme.label)})}
        }
    }
}
