package io.magicmobile.android

import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.magicmobile.android.core.Deck
import io.magicmobile.android.core.DeckTextImport
import io.magicmobile.android.core.readBounded
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@Composable internal fun DeckPhotoImportButton(imported:(Deck,ImportReceipt)->Unit) {
    val context=LocalContext.current;val scope=rememberCoroutineScope()
    var busy by remember {mutableStateOf(false)}
    var text by remember {mutableStateOf<String?>(null)}
    var name by remember {mutableStateOf("Scanned Commander deck")}
    var error by remember {mutableStateOf<String?>(null)}
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) {uri->
        if(uri!=null)scope.launch {
            busy=true;error=null
            try {
                text=withContext(Dispatchers.IO) {
                    val bytes=context.contentResolver.openInputStream(uri)?.use {readBounded(it,20*1024*1024)} ?: error("Unable to read image")
                    val bounds=BitmapFactory.Options().apply {inJustDecodeBounds=true}
                    BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
                    require(bounds.outWidth>0 && bounds.outHeight>0) {"Choose a readable image"}
                    var sample=1
                    while(bounds.outWidth.toLong()/sample*(bounds.outHeight/sample)>8_000_000L)sample*=2
                    val bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.size,BitmapFactory.Options().apply {inSampleSize=sample}) ?: error("Unable to decode image")
                    val exif=runCatching {ExifInterface(bytes.inputStream())}.getOrNull()
                    val transform=Matrix().apply {
                        if(exif?.isFlipped==true)postScale(-1f,1f)
                        postRotate((exif?.rotationDegrees ?: 0).toFloat())
                    }
                    val oriented=android.graphics.Bitmap.createBitmap(bitmap,0,0,bitmap.width,bitmap.height,transform,true)
                    if(oriented!==bitmap)bitmap.recycle()
                    val recognizer=TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                    // Cleanup follows task completion even if the picker leaves composition.
                    suspendCancellableCoroutine<String> {continuation->
                        recognizer.process(InputImage.fromBitmap(oriented,0))
                            .addOnSuccessListener {result->if(continuation.isActive)continuation.resume(result.text)}
                            .addOnFailureListener {failure->if(continuation.isActive)continuation.resumeWithException(failure)}
                            .addOnCompleteListener {recognizer.close();oriented.recycle()}
                    }
                }
                if(text.isNullOrBlank())error="No text found. Choose a clear photo or screenshot of a deck list."
            } catch(e:Exception){if(e is kotlinx.coroutines.CancellationException)throw e;error=e.message ?: "Unable to recognize image"}
            finally {busy=false}
        }
    }
    OutlinedButton(onClick={picker.launch("image/*")},enabled=!busy){Text(if(busy)"Reading photo…" else "Import photo")}
    if(text!=null)AlertDialog(onDismissRequest={text=null;error=null},title={Text("Review recognized deck list")},text={
        Column(Modifier.heightIn(max=480.dp).verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text("Text is recognized on this device. Correct names and quantities before importing. Use a Commanders heading for your commander; every other card needs a quantity, such as 1 Sol Ring.")
            OutlinedTextField(name,{name=it.take(300)},label={Text("Deck name")})
            OutlinedTextField(text.orEmpty(),{text=it},label={Text("Recognized text")},minLines=6)
            error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
        }
    },confirmButton={TextButton(onClick={runCatching {DeckTextImport.preview(name,text.orEmpty())}.onSuccess {
        val receipt=ImportReceipt("On-device photo text recognition",text.orEmpty(),it.annotations,it.deck)
        text=null;error=null;imported(it.deck,receipt)
    }.onFailure {error=it.message}}){Text("Review deck")}},dismissButton={TextButton(onClick={text=null;error=null}){Text("Cancel")}})
    else if(error!=null)AlertDialog(onDismissRequest={error=null},title={Text("Photo import")},text={Text(error!!)},confirmButton={TextButton(onClick={error=null}){Text("OK")}})
}
