import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/elements_data.dart';

/// Ngoại lệ khi phân tích công thức hóa học không hợp lệ.
class MolarMassException implements Exception {
  final String message;
  const MolarMassException(this.message);

  @override
  String toString() => 'MolarMassException: $message';
}

/// Chi tiết đóng góp khối lượng của từng nguyên tố trong phân tử.
class ElementBreakdown {
  final String symbol;
  final String nameVi;
  final double atomicMass;
  final int count;
  final double subtotalMass;
  final double percentage;

  const ElementBreakdown({
    required this.symbol,
    required this.nameVi,
    required this.atomicMass,
    required this.count,
    required this.subtotalMass,
    required this.percentage,
  });
}

/// Kết quả tính khối lượng mol phân tử M (g/mol).
class MolarMassResult {
  final String formula;
  final double totalMass;
  final List<ElementBreakdown> breakdown;

  const MolarMassResult({
    required this.formula,
    required this.totalMass,
    required this.breakdown,
  });

  /// Chuỗi định dạng đẹp để chèn nhanh vào trang ghi chú.
  String get formattedSummary {
    final parts = breakdown
        .map((e) => '${e.symbol}: ${e.count} (${e.percentage.toStringAsFixed(1)}%)')
        .join(', ');
    return 'M($formula) = ${totalMass.toStringAsFixed(2)} g/mol  [$parts]';
  }
}

/// Bộ phân tích & tính khối lượng mol phân tử thuần Dart (dễ kiểm thử đơn vị).
///
/// Hỗ trợ:
/// - Công thức đơn giản: `H2SO4`, `C6H12O6`, `KMnO4`
/// - Dấu ngoặc đơn, ngoặc vuông, ngoặc nhọn lồng nhau: `Ca(OH)2`, `K4[Fe(CN)6]`
/// - Muối ngậm nước (hydrat) phân tách bằng `.`, `·`, `•`, `*`: `CuSO4.5H2O`, `Na2CO3·10H2O`
class MolarMassCalculator {
  const MolarMassCalculator._();

  /// Phân tích công thức hóa học thành bản đồ `{ký_hiệu: số_nguyên_tử}`.
  static Map<String, int> parseFormula(String rawFormula) {
    final trimmed = rawFormula.trim();
    if (trimmed.isEmpty) {
      throw const MolarMassException('Vui lòng nhập công thức hóa học.');
    }

    // Chuẩn hóa các ký tự dấu chấm hydrat và loại bỏ khoảng trắng
    final normalized = trimmed.replaceAll(RegExp(r'\s+'), '');
    final segments = normalized.split(RegExp(r'[.·•*]'));
    final totalCounts = <String, int>{};

    for (final segment in segments) {
      if (segment.isEmpty) {
        throw const MolarMassException(
          'Cú pháp hydrat không hợp lệ (có dấu chấm thừa hoặc thiếu chất).',
        );
      }

      int idx = 0;
      int coefficient = 1;

      // Đọc hệ số đứng đầu mỗi phần (ví dụ: 5 trong 5H2O)
      if (_isDigit(segment.codeUnitAt(idx))) {
        final start = idx;
        while (idx < segment.length && _isDigit(segment.codeUnitAt(idx))) {
          idx++;
        }
        coefficient = int.parse(segment.substring(start, idx));
        if (coefficient <= 0) {
          throw const MolarMassException('Hệ số phải lớn hơn 0.');
        }
        if (idx >= segment.length) {
          throw const MolarMassException(
            'Thiếu công thức chất sau hệ số.',
          );
        }
      }

      final parser = _SegmentParser(segment, idx);
      final segmentCounts = parser.parse();
      if (segmentCounts.isEmpty) {
        throw const MolarMassException('Công thức không chứa nguyên tố nào.');
      }

      for (final entry in segmentCounts.entries) {
        totalCounts[entry.key] =
            (totalCounts[entry.key] ?? 0) + entry.value * coefficient;
      }
    }

    return totalCounts;
  }

  /// Tính tổng khối lượng mol phân tử và thành phần phần trăm từng nguyên tố.
  static MolarMassResult calculate(String formula) {
    final trimmed = formula.trim();
    final counts = parseFormula(trimmed);

    double totalMass = 0;
    final rawEntries = <({ChemicalElement element, int count, double subtotal})>[];

    for (final entry in counts.entries) {
      final element = findElementBySymbol(entry.key);
      if (element == null) {
        throw MolarMassException('Không tìm thấy nguyên tố "${entry.key}".');
      }
      final subtotal = element.atomicMass * entry.value;
      totalMass += subtotal;
      rawEntries.add((element: element, count: entry.value, subtotal: subtotal));
    }

    final breakdown = rawEntries.map((item) {
      final pct = totalMass > 0 ? (item.subtotal / totalMass) * 100.0 : 0.0;
      return ElementBreakdown(
        symbol: item.element.symbol,
        nameVi: item.element.nameVi,
        atomicMass: item.element.atomicMass,
        count: item.count,
        subtotalMass: item.subtotal,
        percentage: pct,
      );
    }).toList();

    return MolarMassResult(
      formula: trimmed,
      totalMass: totalMass,
      breakdown: breakdown,
    );
  }

  static bool _isDigit(int code) => code >= 48 && code <= 57;
}

class _SegmentParser {
  final String input;
  int pos;

  _SegmentParser(this.input, this.pos);

  static const Map<String, String> _matchingClose = {
    '(': ')',
    '[': ']',
    '{': '}',
  };

  Map<String, int> parse() {
    final result = _parseGroup(null);
    if (pos < input.length) {
      throw MolarMassException(
        'Ký tự không hợp lệ "${input[pos]}" tại vị trí ${pos + 1}.',
      );
    }
    return result;
  }

  Map<String, int> _parseGroup(String? expectedClose) {
    final counts = <String, int>{};

    while (pos < input.length) {
      final ch = input[pos];

      if (ch == ')' || ch == ']' || ch == '}') {
        if (expectedClose == null) {
          throw MolarMassException('Dư dấu đóng ngoặc "$ch".');
        }
        if (ch != expectedClose) {
          throw MolarMassException(
            'Ngoặc không khớp: cần "$expectedClose" nhưng gặp "$ch".',
          );
        }
        pos++;
        return counts;
      }

      if (_matchingClose.containsKey(ch)) {
        final closeChar = _matchingClose[ch]!;
        pos++;
        final inner = _parseGroup(closeChar);
        if (inner.isEmpty) {
          throw MolarMassException('Nhóm ngoặc "$ch$closeChar" rỗng.');
        }
        final multiplier = _readOptionalNumber();
        for (final entry in inner.entries) {
          counts[entry.key] =
              (counts[entry.key] ?? 0) + entry.value * multiplier;
        }
        continue;
      }

      final code = ch.codeUnitAt(0);
      if (_isUpper(code)) {
        final start = pos;
        pos++;
        while (pos < input.length && _isLower(input.codeUnitAt(pos))) {
          pos++;
        }
        final symbol = input.substring(start, pos);
        if (findElementBySymbol(symbol) == null) {
          throw MolarMassException('Ký hiệu nguyên tố không hợp lệ: "$symbol".');
        }
        final multiplier = _readOptionalNumber();
        counts[symbol] = (counts[symbol] ?? 0) + multiplier;
        continue;
      }

      if (_isLower(code)) {
        throw MolarMassException(
          'Ký hiệu nguyên tố phải viết hoa chữ cái đầu (ví dụ: H2O, NaCl) — lỗi tại "$ch".',
        );
      }

      throw MolarMassException('Ký tự không hợp lệ "$ch" trong công thức.');
    }

    if (expectedClose != null) {
      throw MolarMassException('Thiếu dấu đóng ngoặc "$expectedClose".');
    }

    return counts;
  }

  int _readOptionalNumber() {
    if (pos >= input.length || !_isDigit(input.codeUnitAt(pos))) {
      return 1;
    }
    final start = pos;
    while (pos < input.length && _isDigit(input.codeUnitAt(pos))) {
      pos++;
    }
    final val = int.parse(input.substring(start, pos));
    if (val <= 0) {
      throw const MolarMassException('Chỉ số nguyên tử phải lớn hơn 0.');
    }
    return val;
  }

  bool _isUpper(int c) => c >= 65 && c <= 90;
  bool _isLower(int c) => c >= 97 && c <= 122;
  bool _isDigit(int c) => c >= 48 && c <= 57;
}

/// Giao diện máy tính Khối lượng mol phân tử (M) trực quan cho sinh viên Hóa học.
class MolarMassCalculatorWidget extends StatefulWidget {
  final ValueChanged<String>? onInsertText;

  const MolarMassCalculatorWidget({
    super.key,
    this.onInsertText,
  });

  @override
  State<MolarMassCalculatorWidget> createState() =>
      _MolarMassCalculatorWidgetState();
}

class _MolarMassCalculatorWidgetState extends State<MolarMassCalculatorWidget> {
  static const List<String> _quickExamples = [
    'H2SO4',
    'NaOH',
    'Ca(OH)2',
    'CuSO4.5H2O',
    'K4[Fe(CN)6]',
    'C6H12O6',
    'KMnO4',
    'CH3COOH',
  ];

  final TextEditingController _controller = TextEditingController(text: 'H2SO4');
  MolarMassResult? _result;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _compute(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _compute(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _result = null;
        _errorText = null;
      });
      return;
    }
    try {
      final res = MolarMassCalculator.calculate(trimmed);
      setState(() {
        _result = res;
        _errorText = null;
      });
    } on MolarMassException catch (e) {
      setState(() {
        _result = null;
        _errorText = e.message;
      });
    }
  }

  void _applyExample(String formula) {
    _controller.text = formula;
    _controller.selection = TextSelection.collapsed(offset: formula.length);
    _compute(formula);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            onChanged: _compute,
            decoration: InputDecoration(
              labelText: 'Nhập công thức hóa học',
              hintText: 'VD: H2SO4, Ca(OH)2, CuSO4.5H2O, K4[Fe(CN)6]',
              prefixIcon: const Icon(Icons.science_outlined),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        _compute('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: _errorText,
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _quickExamples.map((ex) {
              return ActionChip(
                label: Text(ex, style: const TextStyle(fontFamily: 'monospace')),
                onPressed: () => _applyExample(ex),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (_result != null) ...[
            Card(
              elevation: 0,
              color: colors.primaryContainer.withOpacity(0.55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.primary.withOpacity(0.25)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Khối lượng mol phân tử',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _result!.totalMass.toStringAsFixed(3),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'g/mol',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _result!.formattedSummary),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Đã sao chép kết quả tính M'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Sao chép'),
                        ),
                        const SizedBox(width: 10),
                        if (widget.onInsertText != null)
                          FilledButton.icon(
                            onPressed: () =>
                                widget.onInsertText!(_result!.formattedSummary),
                            icon: const Icon(Icons.add_comment_outlined, size: 18),
                            label: const Text('Chèn vào ghi chú'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Thành phần nguyên tố (% khối lượng)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _result!.breakdown.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: colors.outlineVariant),
                    _BreakdownRow(item: _result!.breakdown[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final ElementBreakdown item;

  const _BreakdownRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final el = findElementBySymbol(item.symbol);
    final badgeColor = el?.category.color ?? colors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: badgeColor.withOpacity(0.6)),
            ),
            child: Text(
              item.symbol,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.nameVi} × ${item.count}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${item.atomicMass.toStringAsFixed(3)} × ${item.count} = ${item.subtotalMass.toStringAsFixed(3)} g/mol',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${item.percentage.toStringAsFixed(2)}%',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
