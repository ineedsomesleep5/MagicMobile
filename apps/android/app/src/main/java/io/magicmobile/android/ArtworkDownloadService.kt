package io.magicmobile.android

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.AtomicFile
import io.magicmobile.android.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import java.io.File

internal data class ArtworkDownloadState(val running:Boolean=false,
    val progress:DownloadProgress=DownloadProgress(0,0,"Choose what to keep offline."),
    val failures:List<String> = emptyList())

/** User-started foreground work. The atomic request and completed images survive process death. */
class ArtworkDownloadService:Service() {
    private val scope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
    private var job:Job?=null
    private var lastNotification=0L
    private var generation=0L
    override fun onBind(intent:Intent?):IBinder?=null
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL,"Artwork downloads",NotificationManager.IMPORTANCE_LOW))
    }
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        if(intent?.action==CANCEL){pause("Download paused. Completed files are kept.");return START_NOT_STICKY}
        if(!Artwork.enabled(this)){pause("Online artwork is off. Your downloaded images are kept.");return START_NOT_STICKY}
        try{startForeground(NOTIFICATION,notification("Preparing artwork…"))}
        catch(failure:RuntimeException){pause("Android could not start the download. Reopen Downloads to retry.");return START_NOT_STICKY}
        if(job?.isActive==true&&generation==generationCounter.get())return START_STICKY
        job?.cancel()
        generation=generationCounter.incrementAndGet()
        val runGeneration=generation
        fun ownsRun()=runGeneration==generationCounter.get()
        state.value=ArtworkDownloadState(true,DownloadProgress(0,0,"Preparing artwork…"))
        job=scope.launch {
            try {
                val request=AtomicFile(requestFile(this@ArtworkDownloadService)).openRead().use{input->
                    check(input.channel.size() in 1..Wire.LIMIT.toLong()){"Download request is too large."}
                    ArtworkDownloadRequest.decode(input.readBytes())
                }
                val failures=ArtworkDownloadClient(applicationContext).download(request.names,request.quality,request.tokens,request.catalogue){progress->
                    withContext(Dispatchers.Main.immediate){
                        if(ownsRun()){
                            state.value=state.value.copy(progress=progress)
                            if(System.currentTimeMillis()-lastNotification>1000){lastNotification=System.currentTimeMillis();getSystemService(NotificationManager::class.java).notify(NOTIFICATION,notification(progress.status))}
                        }
                    }
                }
                startLock.lock()
                try {
                    withContext(Dispatchers.Main.immediate){
                        if(ownsRun()){
                            if(failures.isEmpty())AtomicFile(requestFile(applicationContext)).delete()
                            state.value=state.value.copy(failures=failures,
                                progress=state.value.progress.copy(status=if(failures.isEmpty())"Artwork download complete." else "Some artwork needs attention. Retry missing artwork."))
                        }
                    }
                }finally{startLock.unlock()}
            }catch(cancelled:CancellationException){throw cancelled}
            catch(failure:Exception){withContext(Dispatchers.Main.immediate){if(ownsRun())state.value=state.value.copy(progress=state.value.progress.copy(status="Download paused: ${failure.message}"))}}
            finally {withContext(NonCancellable+Dispatchers.Main.immediate){if(ownsRun()){stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();state.value=state.value.copy(running=false)}}}
        }
        return START_STICKY
    }
    override fun onTimeout(startId:Int,fgsType:Int){pause("Android paused this download. Reopen Downloads to resume.")}
    private fun pause(message:String){if(generation==0L||generation==generationCounter.get()){generationCounter.incrementAndGet();state.value=state.value.copy(running=false,progress=state.value.progress.copy(status=message))};job?.cancel();stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()}
    override fun onDestroy(){scope.cancel();if(generation==generationCounter.get())state.value=state.value.copy(running=false);super.onDestroy()}
    private fun notification(message:String):Notification {
        val open=PendingIntent.getActivity(this,0,Intent(this,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val cancel=PendingIntent.getService(this,1,Intent(this,ArtworkDownloadService::class.java).setAction(CANCEL),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(this,CHANNEL).setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Downloading card artwork").setContentText(message).setContentIntent(open)
            .setOngoing(true).setOnlyAlertOnce(true).addAction(Notification.Action.Builder(null,"Pause",cancel).build()).build()
    }
    companion object {
        private const val CHANNEL="artwork-downloads"
        private const val NOTIFICATION=4201
        private const val CANCEL="io.magicmobile.android.PAUSE_ARTWORK"
        internal val state=MutableStateFlow(ArtworkDownloadState())
        private val startLock=kotlinx.coroutines.sync.Mutex()
        private val generationCounter=java.util.concurrent.atomic.AtomicLong()
        private fun requestFile(context:Context)=File(context.filesDir,"artwork-download-request.json")
        internal fun hasPending(context:Context)=requestFile(context).isFile
        internal fun resume(context:Context){check(Artwork.enabled(context)){"Online artwork is disabled."};context.startForegroundService(Intent(context,ArtworkDownloadService::class.java))}
        internal suspend fun start(context:Context,names:List<String>,quality:ArtworkQuality,tokens:Boolean,catalogue:Boolean) {
            startLock.lock()
            try {
            check(Artwork.enabled(context)){"Online artwork is disabled."}
            if(state.value.running)return
            state.value=ArtworkDownloadState(true,DownloadProgress(0,0,"Preparing artwork…"))
            withContext(Dispatchers.IO){
                val file=AtomicFile(requestFile(context));val output=file.startWrite()
                try{output.write(ArtworkDownloadRequest(names,quality,tokens,catalogue).encode());file.finishWrite(output)}
                catch(failure:Throwable){file.failWrite(output);throw failure}
            }
            check(Artwork.enabled(context)){"Online artwork is disabled."}
            context.startForegroundService(Intent(context,ArtworkDownloadService::class.java))
            }catch(failure:Throwable){state.value=state.value.copy(running=false);throw failure}
            finally{startLock.unlock()}
        }
        internal fun pause(context:Context){generationCounter.incrementAndGet();state.value=state.value.copy(running=false,progress=state.value.progress.copy(status="Download paused. Completed files are kept."));context.stopService(Intent(context,ArtworkDownloadService::class.java))}
    }
}
