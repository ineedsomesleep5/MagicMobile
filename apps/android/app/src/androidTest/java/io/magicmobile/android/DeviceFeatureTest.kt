package io.magicmobile.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.test.platform.app.InstrumentationRegistry
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.magicmobile.android.core.*
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID
import java.util.concurrent.TimeUnit

class DeviceFeatureTest {
    @Test fun savedDeckSurvivesReopeningAndRejectsAStaleSave() {
        // Isolated cache folder under the instrumentation process's own UID.
        val target=InstrumentationRegistry.getInstrumentation().targetContext
        val directory=java.io.File(target.cacheDir,"acceptance-${UUID.randomUUID()}").apply {mkdirs()}
        val context=object:android.content.ContextWrapper(target) {
            override fun getFilesDir()=java.io.File(directory,"files").apply {mkdirs()}
            override fun getNoBackupFilesDir()=java.io.File(directory,"no-backup").apply {mkdirs()}
        }
        val store=DeckStore(context)
        val deck=Deck("Acceptance ${UUID.randomUUID()}",listOf(CardEntry("Emmara, Soul of the Accord",1,"commanders"),CardEntry("Forest",99)))
        var saved=store.save(deck)
        try {
            saved=store.organize(saved,true,listOf("Acceptance"),"Private note")
            val reopened=DeckStore(context).all().single {it.id==saved.id}
            assertEquals(saved,reopened)
            val changed=deck.change(1,-1)
            // Saving over the reopened copy keeps its identity; that stale copy cannot overwrite the update.
            saved=store.save(changed,reopened)
            assertEquals(reopened.id,saved.id)
            assertEquals(reopened.revision+1,saved.revision)
            assertEquals(changed,DeckStore(context).all().single().deck)
            assertTrue(runCatching{store.save(deck,reopened)}.isFailure)
            assertEquals(changed,Deck.parse(changed.name,changed.export()))
        } finally {store.delete(saved)}
    }

    @Test fun bundledPhotoRecognitionReadsDeckText() {
        val bitmap=Bitmap.createBitmap(1200,500,Bitmap.Config.ARGB_8888)
        val canvas=Canvas(bitmap);canvas.drawColor(Color.WHITE)
        val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply {color=Color.BLACK;textSize=54f}
        listOf("Commanders","1 Emmara, Soul of the Accord","Deck","99 Forest").forEachIndexed {index,text->canvas.drawText(text,30f,80f+index*100f,paint)}
        val recognizer=TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            val result=Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap,0)),60,TimeUnit.SECONDS)
            assertTrue(result.text.contains("Emmara"))
            assertTrue(result.text.contains("Forest"))
            val parsed=DeckTextImport.preview("Recognized deck",result.text).deck
            assertEquals(100,parsed.entries.sumOf {it.quantity})
            assertEquals("commanders",parsed.entries.first().section)
        } finally {recognizer.close();bitmap.recycle()}
    }
}
