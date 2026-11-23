package com.chemnote.app

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.PlaybackParams
import android.os.Build
import android.os.Bundle
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

class MainActivity : FlutterActivity() {
    companion object {
        private const val HARDWARE_CHANNEL = "com.chemnote.app/hardware"
        private const val STYLUS_BUTTON_DEBOUNCE_MS = 250L
        private const val REQ_RECORD_AUDIO = 4012
    }

    private var hardwareChannel: MethodChannel? = null
    private var lastStylusDoubleTapMs: Long = 0L
    private var stylusPrimaryButtonDown: Boolean = false

    private var mediaRecorder: MediaRecorder? = null
    private var recordingStartMs: Long = 0L
    private var pendingRecordPath: String? = null
    private var pendingRecordResult: MethodChannel.Result? = null

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
                    else -> result.notImplemented()
                }
            }
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

    private fun notifyStylusDoubleTap() {
        val now = System.currentTimeMillis()
        if (now - lastStylusDoubleTapMs < STYLUS_BUTTON_DEBOUNCE_MS) return
        lastStylusDoubleTapMs = now
        runOnUiThread {
            hardwareChannel?.invokeMethod("stylus_double_tap", null)
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_UP) {
            val isStylusButton =
                event.keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_PRIMARY ||
                    event.keyCode == KeyEvent.KEYCODE_STYLUS_BUTTON_SECONDARY
            if (isStylusButton) {
                notifyStylusDoubleTap()
                return true
            }
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

        val pressed = (ev.buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY) != 0
        if (pressed && !stylusPrimaryButtonDown) {
            stylusPrimaryButtonDown = true
            notifyStylusDoubleTap()
        } else if (!pressed && stylusPrimaryButtonDown) {
            stylusPrimaryButtonDown = false
        }
    }
}
