import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ảnh gần đây lấy trực tiếp từ bộ nhớ máy (`MediaStore.Images`) trên Android / HarmonyOS.
class DeviceRecentImage {
  final String uri;
  final String thumbPath;
  final String filePath;

  const DeviceRecentImage({
    required this.uri,
    required this.thumbPath,
    this.filePath = '',
  });
}

/// Kết quả chọn tài liệu từ trình quản lý tệp gốc của thiết bị (ưu tiên Huawei Tệp tin).
class PickedDeviceFile {
  final String path;
  final String name;
  final int size;

  const PickedDeviceFile({
    required this.path,
    required this.name,
    this.size = 0,
  });
}

/// Kết quả kết xuất một trang PDF thành ảnh PNG trực tiếp bằng Android `PdfRenderer`.
class NativePdfPageRender {
  final int pageNumber;
  final String path;
  final int width;
  final int height;
  final bool isLandscape;

  const NativePdfPageRender({
    required this.pageNumber,
    required this.path,
    required this.width,
    required this.height,
    required this.isLandscape,
  });
}

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
  final StreamController<({int currentPage, int? totalPages, String stage})>
      _pdfImportProgressController = StreamController<
          ({int currentPage, int? totalPages, String stage})>.broadcast();

  /// Luồng sự kiện khi người dùng gõ đúp thân bút Huawei M-Pencil 3 / S-Pen.
  Stream<void> get onStylusDoubleTap => _stylusDoubleTapController.stream;

  /// Luồng tiến độ kết xuất PDF gốc theo từng trang từ Android `PdfRenderer`.
  Stream<({int currentPage, int? totalPages, String stage})>
      get onPdfImportProgress => _pdfImportProgressController.stream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'stylus_double_tap') {
      _stylusDoubleTapController.add(null);
    } else if (call.method == 'pdf_import_progress') {
      final args = call.arguments;
      if (args is Map) {
        final rawPage = args['currentPage'];
        final rawTotal = args['totalPages'];
        final currentPage = rawPage is num ? rawPage.toInt() : 0;
        final totalPages = rawTotal is num ? rawTotal.toInt() : null;
        final stage = args['stage']?.toString() ?? '';
        _pdfImportProgressController.add((
          currentPage: currentPage,
          totalPages: totalPages,
          stage: stage,
        ));
      }
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

  /// Lấy danh sách ảnh & ảnh chụp màn hình gần đây nhất trên máy tính bảng (`MediaStore.Images`).
  Future<List<DeviceRecentImage>> getDeviceRecentImages({int limit = 12}) async {
    if (kIsWeb) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getDeviceRecentImages',
        {'limit': limit},
      );
      if (raw == null) return const [];
      final results = <DeviceRecentImage>[];
      for (final item in raw) {
        if (item is Map) {
          final uri = item['uri']?.toString() ?? '';
          final thumbPath = item['thumbPath']?.toString() ?? '';
          final filePath = item['filePath']?.toString() ?? '';
          if (uri.isNotEmpty && thumbPath.isNotEmpty) {
            results.add(
              DeviceRecentImage(
                uri: uri,
                thumbPath: thumbPath,
                filePath: filePath,
              ),
            );
          }
        }
      }
      return results;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Sao chép ảnh độ phân giải gốc từ `content://` URI sang `destPath` cục bộ của ứng dụng.
  Future<String?> copyUriToFile(String uri, String destPath) async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('copyUriToFile', {
        'uri': uri,
        'destPath': destPath,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Mở trực tiếp ứng dụng Bộ sưu tập (Gallery) gốc của Huawei/Android (sắp xếp ảnh mới nhất trước).
  Future<String?> pickImageFromSystemGallery() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('pickImageFromSystemGallery');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Mở trình quản lý tệp mặc định (ưu tiên Tệp tin Huawei ở thư mục Download).
  /// Trả về `handled: true` trên Android để nếu người dùng hủy thì không mở đè picker khác.
  Future<({bool handled, PickedDeviceFile? file})> pickDocumentFile({
    List<String> allowedExtensions = const [],
  }) async {
    if (kIsWeb) return (handled: false, file: null);
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'pickDocumentFile',
        {'allowedExtensions': allowedExtensions},
      );
      if (raw == null) {
        return (handled: true, file: null);
      }
      if (raw is Map) {
        final path = raw['path']?.toString() ?? '';
        final name = raw['name']?.toString() ?? 'document';
        final rawSize = raw['size'];
        final int size = rawSize is num ? rawSize.toInt() : 0;
        if (path.isNotEmpty) {
          return (
            handled: true,
            file: PickedDeviceFile(path: path, name: name, size: size),
          );
        }
      }
      return (handled: true, file: null);
    } on MissingPluginException {
      return (handled: false, file: null);
    } on PlatformException {
      return (handled: false, file: null);
    }
  }

  /// Kết xuất từng trang tệp PDF trực tiếp trên Android bằng `PdfRenderer` theo kiểu stream 1 trang/lần,
  /// không nạp toàn bộ tệp PDF vào heap Dart và giải phóng Bitmap ngay sau khi ghi PNG.
  /// Trả về `null` trên nền tảng không hỗ trợ (`MissingPluginException`, Web, Desktop) để dùng fallback Dart.
  Future<List<NativePdfPageRender>?> renderPdfToPngs({
    required String pdfPath,
    required String outputDir,
    required String batchId,
    int maxLongEdge = 2200,
  }) async {
    if (kIsWeb) return null;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'renderPdfToPngs',
        {
          'pdfPath': pdfPath,
          'outputDir': outputDir,
          'batchId': batchId,
          'maxLongEdge': maxLongEdge,
        },
      );
      if (raw == null) return null;
      final pages = <NativePdfPageRender>[];
      for (final item in raw) {
        if (item is Map) {
          final rawPage = item['pageNumber'];
          final rawW = item['width'];
          final rawH = item['height'];
          final path = item['path']?.toString() ?? '';
          final pageNumber = rawPage is num ? rawPage.toInt() : pages.length + 1;
          final width = rawW is num ? rawW.toInt() : 0;
          final height = rawH is num ? rawH.toInt() : 0;
          final isLandscape = item['isLandscape'] == true || width > height;
          if (path.isNotEmpty) {
            pages.add(
              NativePdfPageRender(
                pageNumber: pageNumber,
                path: path,
                width: width,
                height: height,
                isLandscape: isLandscape,
              ),
            );
          }
        }
      }
      return pages;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      rethrow;
    }
  }

  /// Kích hoạt sự kiện gõ đúp bút giả lập phục vụ kiểm thử đơn vị.
  @visibleForTesting
  void emitStylusDoubleTapForTesting() {
    _stylusDoubleTapController.add(null);
  }
}
