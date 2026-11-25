import 'package:flutter/material.dart';

/// Thanh tiến trình nổi ở cạnh dưới màn hình hiển thị `%` hoàn thành khi nhập PDF / DOCX.
class PdfImportBottomProgressOverlay {
  OverlayEntry? _entry;
  ValueNotifier<({String title, int current, int? total, String stage})>?
      _notifier;

  void show(
    BuildContext context, {
    required String title,
  }) {
    if (_entry != null) {
      final cur = _notifier?.value;
      if (cur != null && cur.title != title) {
        _notifier!.value = (
          title: title,
          current: cur.current,
          total: cur.total,
          stage: cur.stage,
        );
      }
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    final notifier = ValueNotifier<
        ({String title, int current, int? total, String stage})>((
      title: title,
      current: 0,
      total: null,
      stage: 'Đang mở tệp tài liệu...',
    ));
    _notifier = notifier;

    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 16,
        right: 16,
        bottom: 18,
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: IgnorePointer(
                ignoring: false,
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(16),
                  color: const Color(0xF2181B22),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withAlpha(32),
                      ),
                    ),
                    child: ValueListenableBuilder<
                        ({String title, int current, int? total, String stage})>(
                      valueListenable: notifier,
                      builder: (_, state, __) {
                        final double? ratio =
                            (state.total != null && state.total! > 0)
                                ? (state.current / state.total!).clamp(0.0, 1.0)
                                : null;
                        final String rightBadge = ratio != null
                            ? '${(ratio * 100).round()}%'
                            : (state.current > 0
                                ? 'Trang ${state.current}'
                                : '...');

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: Color(0xFF3B82F6),
                                  size: 20,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    state.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  rightBadge,
                                  style: const TextStyle(
                                    color: Color(0xFF60A5FA),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 7,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF3B82F6),
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              state.stage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _entry = entry;
    overlay.insert(entry);
  }

  void update(int current, int? total, String stage) {
    final notifier = _notifier;
    if (notifier == null) return;
    notifier.value = (
      title: notifier.value.title,
      current: current,
      total: total,
      stage: stage,
    );
  }

  void hide() {
    try {
      _entry?.remove();
    } catch (_) {}
    _entry = null;
    try {
      _notifier?.dispose();
    } catch (_) {}
    _notifier = null;
  }
}
