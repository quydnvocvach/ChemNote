import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cầu nối phần cứng cho Huawei MatePad 11.5"S (144Hz PaperMatte), Huawei M-Pencil 3 (NearLink)
/// và Ghi âm / Phát lại bài giảng gốc Android (`MediaRecorder` / `MediaPlayer`).
/// Tự động bỏ qua an toàn trên nền tảng không hỗ trợ (Web, Desktop, Unit Tests).
class HardwareService {
  HardwareService._internal() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final HardwareService instance = HardwareService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.chemnote.app/hardware');

  final StreamController<void> _stylusDoubleTapController =
      StreamController<void>.broadcast();

  /// Luồng sự kiện khi người dùng gõ đúp thân bút Huawei M-Pencil 3 / S-Pen.
  Stream<void> get onStylusDoubleTap => _stylusDoubleTapController.stream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'stylus_double_tap') {
      _stylusDoubleTapController.add(null);
    }
    return null;
  }

  /// Bật/tắt chế độ giữ màn hình luôn sáng khi ghi chép bài giảng dài.
  Future<void> setKeepScreenOn(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Bỏ qua an toàn trên môi trường kiểm thử hoặc thiết bị không có native plugin.
    } on PlatformException {
      // Bỏ qua lỗi nền tảng không ảnh hưởng luồng ghi chú.
    }
  }

  /// Trả về tần số quét hiện tại của màn hình (ví dụ: 144.0 Hz trên MatePad 11.5"S).
  Future<double> getRefreshRate() async {
    if (kIsWeb) return 60.0;
    try {
      final hz = await _channel.invokeMethod<num>('getRefreshRate');
      return hz?.toDouble() ?? 60.0;
    } on MissingPluginException {
      return 60.0;
    } on PlatformException {
      return 60.0;
    }
  }

  /// Bắt đầu ghi âm bài giảng AAC (.m4a) tới `path`. Trả về `true` nếu bắt đầu thành công.
  Future<bool> startAudioRecording(String path) async {
    if (kIsWeb) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('startAudioRecording', {
        'path': path,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Dừng ghi âm bài giảng và trả về thời lượng (ms).
  Future<int> stopAudioRecording() async {
    if (kIsWeb) return 0;
    try {
      final ms = await _channel.invokeMethod<num>('stopAudioRecording');
      return ms?.toInt() ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Phát lại tệp ghi âm bài giảng từ `path`.
  Future<bool> playAudio(String path) async {
    if (kIsWeb) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('playAudio', {
        'path': path,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Tạm dừng phát ghi âm.
  Future<void> pauseAudio() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('pauseAudio');
    } on MissingPluginException {
      // No-op in tests
    } on PlatformException {
      // Ignore
    }
  }

  /// Dừng hoàn toàn phát ghi âm và giải phóng MediaPlayer.
  Future<void> stopAudio() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('stopAudio');
    } on MissingPluginException {
      // No-op in tests
    } on PlatformException {
      // Ignore
    }
  }

  /// Tua nhanh/lùi tới vị trí `ms` (milliseconds).
  Future<void> seekAudio(int ms) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('seekAudio', {'ms': ms});
    } on MissingPluginException {
      // No-op in tests
    } on PlatformException {
      // Ignore
    }
  }

  /// Đổi tốc độ phát lại (`1.0`, `1.5`, `2.0`).
  Future<void> setAudioSpeed(double speed) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setAudioSpeed', {'speed': speed});
    } on MissingPluginException {
      // No-op in tests
    } on PlatformException {
      // Ignore
    }
  }

  /// Lấy vị trí phát hiện tại (ms) để đồng bộ hiệu ứng tô sáng nét viết tay.
  Future<int> getAudioPositionMs() async {
    if (kIsWeb) return 0;
    try {
      final ms = await _channel.invokeMethod<num>('getAudioPositionMs');
      return ms?.toInt() ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  /// Kích hoạt sự kiện gõ đúp bút giả lập phục vụ kiểm thử đơn vị.
  @visibleForTesting
  void emitStylusDoubleTapForTesting() {
    _stylusDoubleTapController.add(null);
  }
}
