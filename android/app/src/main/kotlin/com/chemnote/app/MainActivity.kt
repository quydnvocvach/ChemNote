package com.chemnote.app

import android.os.Build
import android.os.Bundle
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val HARDWARE_CHANNEL = "com.chemnote.app/hardware"
        private const val STYLUS_BUTTON_DEBOUNCE_MS = 250L
    }

    private var hardwareChannel: MethodChannel? = null
    private var lastStylusDoubleTapMs: Long = 0L
    private var stylusPrimaryButtonDown: Boolean = false

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
                    else -> result.notImplemented()
                }
            }
        }
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
        // Ưu tiên chế độ cùng độ phân giải hiện tại nhưng có tần số quét cao nhất
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
