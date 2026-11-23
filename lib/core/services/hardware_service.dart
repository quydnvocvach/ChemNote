import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cầu nối phần cứng cho Huawei MatePad 11.5"S (144Hz PaperMatte) & Huawei M-Pencil 3 (NearLink).
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

  /// Kích hoạt sự kiện gõ đúp bút giả lập phục vụ kiểm thử đơn vị.
  @visibleForTesting
  void emitStylusDoubleTapForTesting() {
    _stylusDoubleTapController.add(null);
  }
}
