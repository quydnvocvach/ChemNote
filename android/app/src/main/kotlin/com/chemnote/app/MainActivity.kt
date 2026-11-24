package com.chemnote.app

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.PlaybackParams
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.MediaStore
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val HARDWARE_CHANNEL = "com.chemnote.app/hardware"
        private const val STYLUS_BUTTON_DEBOUNCE_MS = 450L
        private const val REQ_RECORD_AUDIO = 4012
        private const val REQ_READ_IMAGES = 4013
        private const val REQ_PICK_GALLERY = 4014
    }

    private var hardwareChannel: MethodChannel? = null
    private var lastStylusDoubleTapMs: Long = 0L
    private var lastStylusTriggerEventTime: Long = -1L
    private var stylusPrimaryButtonDown: Boolean = false
    private var keyEventHandlesStylusButton: Boolean = false

    private var mediaRecorder: MediaRecorder? = null
    private var recordingStartMs: Long = 0L
    private var pendingRecordPath: String? = null
    private var pendingRecordResult: MethodChannel.Result? = null

    private var pendingImagesLimit: Int = 12
    private var pendingImagesResult: MethodChannel.Result? = null
    private var pendingGalleryResult: MethodChannel.Result? = null

    private var mediaPlayer: MediaPlayer? = null
    private var currentPlaybackSpeed: Float = 1.0f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighestRefreshRate()
        enableUnbufferedStylusInput()
    }

    override fun onResume() {
        super.onResume()
        enableHighestRefreshRate()
        enableUnbufferedStylusInput()
    }

    override fun onDestroy() {
        releaseRecorder()
        releasePlayer()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hardwareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HARDWARE_CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    "getRefreshRate" -> {
                        result.success(getCurrentRefreshRate().toDouble())
                    }
                    "startAudioRecording" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            handleStartAudioRecording(path, result)
                        }
                    }
                    "stopAudioRecording" -> {
                        result.success(handleStopAudioRecording())
                    }
                    "playAudio" -> {
                        val path = call.argument<String>("path")
                        result.success(!path.isNullOrBlank() && handlePlayAudio(path))
                    }
                    "pauseAudio" -> {
                        try {
                            mediaPlayer?.let { if (it.isPlaying) it.pause() }
                        } catch (_: Exception) {}
                        result.success(null)
                    }
                    "stopAudio" -> {
                        releasePlayer()
                        result.success(null)
                    }
                    "seekAudio" -> {
                        val ms = call.argument<Int>("ms") ?: 0
                        try {
                            mediaPlayer?.seekTo(ms.coerceAtLeast(0))
                        } catch (_: Exception) {}
                        result.success(null)
                    }
                    "setAudioSpeed" -> {
                        val speed = (call.argument<Double>("speed") ?: 1.0).toFloat().coerceIn(0.5f, 2.5f)
                        currentPlaybackSpeed = speed
                        applyPlaybackSpeed(speed)
                        result.success(null)
                    }
                    "getAudioPositionMs" -> {
                        val pos = try {
                            mediaPlayer?.currentPosition ?: 0
                        } catch (_: Exception) {
                            0
                        }
                        result.success(pos)
                    }
                    "getDeviceRecentImages" -> {
                        val limit = (call.argument<Int>("limit") ?: 12).coerceIn(1, 30)
                        handleGetDeviceRecentImages(limit, result)
                    }
                    "copyUriToFile" -> {
                        val uriStr = call.argument<String>("uri")
                        val destPath = call.argument<String>("destPath")
                        if (uriStr.isNullOrBlank() || destPath.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            Thread {
                                val copied = copyContentUriToFile(uriStr, destPath)
                                runOnUiThread { result.success(copied) }
                            }.start()
                        }
                    }
                    "pickImageFromSystemGallery" -> {
                        handlePickImageFromSystemGallery(result)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun handlePickImageFromSystemGallery(result: MethodChannel.Result) {
        try {
            pendingGalleryResult?.success(null)
            pendingGalleryResult = result
            val intent = Intent(
                Intent.ACTION_PICK,
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            ).apply {
                type = "image/*"
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_PICK_GALLERY)
        } catch (_: Exception) {
            pendingGalleryResult = null
            result.success(null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_PICK_GALLERY) {
            val cb = pendingGalleryResult
            pendingGalleryResult = null
            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri != null && cb != null) {
                val destPath = File(
                    cacheDir,
                    "picked_gallery_${System.currentTimeMillis()}.jpg"
                ).absolutePath
                Thread {
                    val copied = copyContentUriToFile(uri.toString(), destPath)
                    runOnUiThread { cb.success(copied) }
                }.start()
            } else {
                cb?.success(null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun requiredImagesPermission(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    private fun handleGetDeviceRecentImages(limit: Int, result: MethodChannel.Result) {
        val perm = requiredImagesPermission()
        val granted = ContextCompat.checkSelfPermission(this, perm) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            pendingImagesLimit = limit
            pendingImagesResult = result
            ActivityCompat.requestPermissions(this, arrayOf(perm), REQ_READ_IMAGES)
            return
        }
        Thread {
            val items = queryRecentImages(limit)
            runOnUiThread { result.success(items) }
        }.start()
    }

    private fun queryRecentImages(limit: Int): List<Map<String, String>> {
        val output = mutableListOf<Map<String, String>>()
        val thumbDir = File(cacheDir, "recent_thumbs").apply { mkdirs() }
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATE_ADDED
        )
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"

        try {
            contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                sortOrder
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                while (cursor.moveToNext() && output.size < limit) {
                    val id = cursor.getLong(idCol)
                    val contentUri = ContentUris.withAppendedId(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        id
                    )
                    val thumbFile = File(thumbDir, "thumb_$id.jpg")
                    if (!thumbFile.exists() || thumbFile.length() == 0L) {
                        generateThumbnail(contentUri, thumbFile, 240)
                    }
                    if (thumbFile.exists() && thumbFile.length() > 0L) {
                        output.add(
                            mapOf(
                                "uri" to contentUri.toString(),
                                "thumbPath" to thumbFile.absolutePath,
                                "filePath" to ""
                            )
                        )
                    }
                }
            }
        } catch (_: Exception) {
            // Trả về danh sách hiện có nếu thiết bị giới hạn quyền truy cập.
        }
        return output
    }

    private fun generateThumbnail(uri: Uri, outFile: File, targetSize: Int) {
        try {
            val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, boundsOpts)
            }
            val srcW = boundsOpts.outWidth
            val srcH = boundsOpts.outHeight
            if (srcW <= 0 || srcH <= 0) return

            var sampleSize = 1
            while ((srcW / sampleSize) > targetSize * 2 && (srcH / sampleSize) > targetSize * 2) {
                sampleSize *= 2
            }

            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            val bitmap = contentResolver.openInputStream(uri)?.use { stream ->
                BitmapFactory.decodeStream(stream, null, decodeOpts)
            } ?: return

            FileOutputStream(outFile).use { fos ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 82, fos)
            }
            bitmap.recycle()
        } catch (_: Exception) {}
    }

    private fun copyContentUriToFile(uriStr: String, destPath: String): String? {
        return try {
            val uri = Uri.parse(uriStr)
            val destFile = File(destPath)
            destFile.parentFile?.mkdirs()
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            } ?: return null
            destFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun handleStartAudioRecording(path: String, result: MethodChannel.Result) {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        if (!granted) {
            pendingRecordPath = path
            pendingRecordResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                REQ_RECORD_AUDIO
            )
            return
        }
        result.success(startMediaRecorderInternal(path))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_RECORD_AUDIO) {
            val path = pendingRecordPath
            val cb = pendingRecordResult
            pendingRecordPath = null
            pendingRecordResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted && !path.isNullOrBlank()) {
                cb?.success(startMediaRecorderInternal(path))
            } else {
                cb?.success(false)
            }
        } else if (requestCode == REQ_READ_IMAGES) {
            val limit = pendingImagesLimit
            val cb = pendingImagesResult
            pendingImagesResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted && cb != null) {
                Thread {
                    val items = queryRecentImages(limit)
                    runOnUiThread { cb.success(items) }
                }.start()
            } else {
                cb?.success(emptyList<Map<String, String>>())
            }
        }
    }

    private fun startMediaRecorderInternal(path: String): Boolean {
        return try {
            releaseRecorder()
            val outFile = File(path)
            outFile.parentFile?.mkdirs()
            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(96000)
            recorder.setAudioSamplingRate(44100)
            recorder.setOutputFile(outFile.absolutePath)
            recorder.prepare()
            recorder.start()
            mediaRecorder = recorder
            recordingStartMs = System.currentTimeMillis()
            true
        } catch (_: Exception) {
            releaseRecorder()
            false
        }
    }

    private fun handleStopAudioRecording(): Int {
        val recorder = mediaRecorder ?: return 0
        val duration = (System.currentTimeMillis() - recordingStartMs).toInt().coerceAtLeast(0)
        try {
            recorder.stop()
        } catch (_: Exception) {}
        releaseRecorder()
        return duration
    }

    private fun releaseRecorder() {
        try {
            mediaRecorder?.reset()
            mediaRecorder?.release()
        } catch (_: Exception) {}
        mediaRecorder = null
    }

    private fun handlePlayAudio(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            releasePlayer()
            val player = MediaPlayer()
            player.setDataSource(file.absolutePath)
            player.prepare()
            mediaPlayer = player
            applyPlaybackSpeed(currentPlaybackSpeed)
            player.start()
            true
        } catch (_: Exception) {
            releasePlayer()
            false
        }
    }

    private fun applyPlaybackSpeed(speed: Float) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                mediaPlayer?.let { player ->
                    val params: PlaybackParams = player.playbackParams
                    params.speed = speed
                    player.playbackParams = params
                }
            } catch (_: Exception) {}
        }
    }

    private fun releasePlayer() {
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {}
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {}
        mediaPlayer = null
    }

    /**
     * Quét tất cả display.supportedModes và chọn tần số quét cao nhất
     * (ví dụ: 144Hz trên Huawei MatePad 11.5"S PaperMatte).
     */
    private fun enableHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return

        val modes = currentDisplay.supportedModes
        if (modes.isEmpty()) return

        val currentMode = currentDisplay.mode
        val bestMode = modes
            .filter {
                it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight
            }
            .maxByOrNull { it.refreshRate }
            ?: modes.maxByOrNull { it.refreshRate }
            ?: return

        val params = window.attributes
        if (params.preferredDisplayModeId != bestMode.modeId) {
            params.preferredDisplayModeId = bestMode.modeId
            window.attributes = params
        }
    }

    /**
     * Yêu cầu hệ thống giao trực tiếp sự kiện bút cảm ứng không qua bộ đệm VSYNC
     * để tối ưu độ trễ siêu thấp cho Huawei M-Pencil 3 (NearLink).
     */
    private fun enableUnbufferedStylusInput() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.decorView.requestUnbufferedDispatch(InputDevice.SOURCE_STYLUS)
        }
    }

    private fun getCurrentRefreshRate(): Float {
        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }
        return currentDisplay?.refreshRate ?: 60f
    }

    private fun notifyStylusDoubleTap(eventTimeMs: Long = -1L) {
        if (eventTimeMs >= 0L && eventTimeMs == lastStylusTriggerEventTime) return
        val now = SystemClock.uptimeMillis()
        if (now - lastStylusDoubleTapMs < STYLUS_BUTTON_DEBOUNCE_MS) return
        lastStylusDoubleTapMs = now
        if (eventTimeMs >= 0L) {
            lastStylusTriggerEventTime = eventTimeMs
        }
        runOnUiThread {
            hardwareChannel?.invokeMethod("stylus_double_tap", null)
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val isStylusButton =
            event.keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_PRIMARY ||
                event.keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_SECONDARY
        if (isStylusButton) {
            keyEventHandlesStylusButton = true
            if (event.action == KeyEvent.ACTION_UP && event.repeatCount == 0) {
                notifyStylusDoubleTap(event.eventTime)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(ev: MotionEvent): Boolean {
        checkStylusMotionButton(ev)
        return super.dispatchGenericMotionEvent(ev)
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        checkStylusMotionButton(ev)
        return super.dispatchTouchEvent(ev)
    }

    private fun checkStylusMotionButton(ev: MotionEvent) {
        val isStylus = ev.isFromSource(InputDevice.SOURCE_STYLUS) ||
            (ev.pointerCount > 0 && ev.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS)
        if (!isStylus) return

        val stylusMask = MotionEvent.BUTTON_STYLUS_PRIMARY or MotionEvent.BUTTON_STYLUS_SECONDARY
        val pressed = (ev.buttonState and stylusMask) != 0
        if (pressed && !stylusPrimaryButtonDown) {
            stylusPrimaryButtonDown = true
            if (!keyEventHandlesStylusButton) {
                notifyStylusDoubleTap(ev.eventTime)
            }
        } else if (!pressed && stylusPrimaryButtonDown) {
            stylusPrimaryButtonDown = false
        }
    }
}
