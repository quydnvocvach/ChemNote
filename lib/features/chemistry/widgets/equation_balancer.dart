import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'molar_mass_calculator.dart';

/// Ngoại lệ khi không thể phân tích hoặc cân bằng phương trình hóa học.
class EquationBalanceException implements Exception {
  final String message;
  const EquationBalanceException(this.message);

  @override
  String toString() => 'EquationBalanceException: $message';
}

/// Một chất (hoặc ion) sau khi đã tìm được hệ số cân bằng.
class BalancedSpecies {
  final String formula;
  final int coefficient;
  final int charge;
  final String formatted;

  const BalancedSpecies({
    required this.formula,
    required this.coefficient,
    this.charge = 0,
    required this.formatted,
  });
}

/// Kết quả cân bằng phương trình hóa học (hỗ trợ cả phương trình phân tử và ion).
class BalancedEquationResult {
  /// Chuỗi phương trình đẹp có chỉ số dưới & điện tích mũ Unicode
  /// (VD: `MnO₄⁻ + 5Fe²⁺ + 8H⁺ → Mn²⁺ + 5Fe³⁺ + 4H₂O`).
  final String balanced;

  /// Chuỗi phương trình ASCII (VD: `MnO4- + 5Fe2+ + 8H+ -> Mn2+ + 5Fe3+ + 4H2O`).
  final String plain;

  /// Mũi tên hiển thị (`→` hoặc `⇌`).
  final String arrow;

  /// Danh sách tất cả hệ số nguyên dương tối giản (vế trái nối tiếp vế phải).
  final List<int> coefficients;
  final List<BalancedSpecies> reactants;
  final List<BalancedSpecies> products;

  const BalancedEquationResult({
    required this.balanced,
    required this.plain,
    required this.arrow,
    required this.coefficients,
    required this.reactants,
    required this.products,
  });
}

class _ParsedSpecies {
  final String rawToken;
  final String baseFormula;
  final Map<String, int> elements;
  final int charge;
  final bool isElectron;

  const _ParsedSpecies({
    required this.rawToken,
    required this.baseFormula,
    required this.elements,
    required this.charge,
    this.isElectron = false,
  });
}

/// Bộ cân bằng phương trình hóa học thuần Dart dùng khử Gauss-Jordan
/// trên phân số hữu tỉ chính xác (`BigInt`) — hỗ trợ cả phương trình phân tử
/// và phương trình ion có điện tích (`MnO4-`, `Fe2+`, `Cr2O7^2-`, `e-`).
class ChemicalEquationBalancer {
  const ChemicalEquationBalancer._();

  static const List<String> _subscriptDigits = [
    '₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉',
  ];

  static const List<String> _superscriptDigits = [
    '⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹',
  ];

  /// Chuyển các chỉ số nguyên tử thành chỉ số dưới Unicode, giữ nguyên hệ số hydrat.
  /// Ví dụ: `CuSO4.5H2O` -> `CuSO₄·5H₂O`, `Fe3O4` -> `Fe₃O₄`.
  static String formatFormulaSubscripts(String formula) {
    final segments = formula.trim().split(RegExp(r'[.·•*]'));
    return segments.map((seg) {
      int i = 0;
      while (i < seg.length && _isDigit(seg.codeUnitAt(i))) {
        i++;
      }
      final lead = seg.substring(0, i);
      final rest = seg.substring(i).replaceAllMapped(
            RegExp(r'[0-9]'),
            (m) => _subscriptDigits[m.group(0)!.codeUnitAt(0) - 48],
          );
      return '$lead$rest';
    }).join('·');
  }

  /// Định dạng điện tích thành chỉ số trên Unicode (VD: `+2` -> `²⁺`, `-1` -> `⁻`).
  static String formatChargeSuperscript(int charge) {
    if (charge == 0) return '';
    final sign = charge > 0 ? '⁺' : '⁻';
    final mag = charge.abs();
    if (mag == 1) return sign;
    final digits = mag.toString().replaceAllMapped(
          RegExp(r'[0-9]'),
          (m) => _superscriptDigits[m.group(0)!.codeUnitAt(0) - 48],
        );
    return '$digits$sign';
  }

  /// Cân bằng phương trình hóa học phân tử & ion.
  /// Hỗ trợ `->`, `=`, `→`, `⇌`, `<=>`, ngoặc, hydrat và điện tích (`+`, `-`, `2+`, `^2-`, `e-`).
  static BalancedEquationResult balance(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      throw const EquationBalanceException(
        'Vui lòng nhập phương trình hóa học (VD: Fe + O2 -> Fe3O4 hoặc MnO4- + Fe2+ + H+ -> Mn2+ + Fe3+ + H2O).',
      );
    }

    // Chuẩn hóa chỉ số dưới Unicode về ASCII, giữ phân biệt chỉ số trên bằng dấu `^`
    final normalizedInput = _normalizeUnicodeScripts(raw);

    final arrowMatch =
        RegExp(r'<=>|<->|⇌|↔|->|=>|→|=').firstMatch(normalizedInput);
    if (arrowMatch == null) {
      throw const EquationBalanceException(
        'Thiếu dấu mũi tên phản ứng (dùng ->, =, → hoặc ⇌).',
      );
    }

    final rawArrow = arrowMatch.group(0)!;
    final displayArrow =
        (rawArrow == '<=>' || rawArrow == '<->' || rawArrow == '⇌') ? '⇌' : '→';

    final sides = normalizedInput.split(rawArrow);
    if (sides.length != 2 || sides[0].trim().isEmpty || sides[1].trim().isEmpty) {
      throw const EquationBalanceException(
        'Phương trình phải có đúng 2 vế (chất tham gia và sản phẩm).',
      );
    }

    final reactantTokens = _splitSpecies(sides[0])
        .map(_stripLeadingCoeff)
        .where((s) => s.isNotEmpty)
        .toList();
    final productTokens = _splitSpecies(sides[1])
        .map(_stripLeadingCoeff)
        .where((s) => s.isNotEmpty)
        .toList();

    if (reactantTokens.isEmpty || productTokens.isEmpty) {
      throw const EquationBalanceException(
        'Thiếu công thức chất ở vế trái hoặc vế phải.',
      );
    }

    final allTokens = [...reactantTokens, ...productTokens];
    final parsedList = allTokens.map(_parseSpecies).toList();
    final hasCharges = parsedList.any((s) => s.charge != 0);

    final elems = <String>[];
    final elemSet = <String>{};
    for (final sp in parsedList) {
      for (final sym in sp.elements.keys) {
        if (elemSet.add(sym)) elems.add(sym);
      }
    }

    final numCols = allTokens.length;
    final mat = <List<_BigFrac>>[
      for (final sym in elems)
        List<_BigFrac>.generate(numCols, (c) {
          final cnt = parsedList[c].elements[sym] ?? 0;
          final sign = c < reactantTokens.length ? 1 : -1;
          return _BigFrac.fromInt(sign * cnt);
        }),
      if (hasCharges)
        List<_BigFrac>.generate(numCols, (c) {
          final sign = c < reactantTokens.length ? 1 : -1;
          return _BigFrac.fromInt(sign * parsedList[c].charge);
        }),
    ];

    final numRows = mat.length;

    // Khử Gauss-Jordan về dạng bậc thang rút gọn (RREF) trên trường hữu tỉ chính xác
    final pivotCols = <int>[];
    int pivotRow = 0;
    for (int col = 0; col < numCols && pivotRow < numRows; col++) {
      int found = -1;
      for (int r = pivotRow; r < numRows; r++) {
        if (mat[r][col].n != BigInt.zero) {
          found = r;
          break;
        }
      }
      if (found == -1) continue;

      if (found != pivotRow) {
        final tmp = mat[pivotRow];
        mat[pivotRow] = mat[found];
        mat[found] = tmp;
      }

      final pivVal = mat[pivotRow][col];
      for (int c = col; c < numCols; c++) {
        mat[pivotRow][c] = mat[pivotRow][c] / pivVal;
      }

      for (int r = 0; r < numRows; r++) {
        if (r == pivotRow || mat[r][col].n == BigInt.zero) continue;
        final factor = mat[r][col];
        for (int c = col; c < numCols; c++) {
          mat[r][c] = mat[r][c] - (factor * mat[pivotRow][c]);
        }
      }

      pivotCols.add(col);
      pivotRow++;
    }

    final pivotSet = pivotCols.toSet();
    final freeCols = <int>[
      for (int c = 0; c < numCols; c++)
        if (!pivotSet.contains(c)) c,
    ];

    if (freeCols.isEmpty) {
      throw const EquationBalanceException(
        'Không thể cân bằng phương trình — kiểm tra lại nguyên tố và điện tích hai vế.',
      );
    }

    final sol = List<_BigFrac>.filled(numCols, _BigFrac.zero);
    for (final fCol in freeCols) {
      sol[fCol] = _BigFrac.one;
    }

    for (int r = 0; r < pivotCols.length; r++) {
      final pCol = pivotCols[r];
      var sum = _BigFrac.zero;
      for (final fCol in freeCols) {
        sum = sum + mat[r][fCol];
      }
      sol[pCol] = -sum;
    }

    var commonDen = BigInt.one;
    for (final v in sol) {
      commonDen = _blcm(commonDen, v.d);
    }

    final intCoeffs = sol.map((v) => (v.n * commonDen) ~/ v.d).toList();
    if (intCoeffs.every((v) => v < BigInt.zero)) {
      for (int i = 0; i < intCoeffs.length; i++) {
        intCoeffs[i] = -intCoeffs[i];
      }
    }

    if (intCoeffs.any((v) => v <= BigInt.zero)) {
      throw const EquationBalanceException(
        'Không tìm được bộ hệ số nguyên dương — vui lòng kiểm tra lại các chất và điện tích.',
      );
    }

    var commonGcd = intCoeffs.first;
    for (int i = 1; i < intCoeffs.length; i++) {
      commonGcd = _bgcd(commonGcd, intCoeffs[i]);
    }
    final coeffs = intCoeffs.map((v) => (v ~/ commonGcd).toInt()).toList();

    BalancedSpecies buildSpecies(int index) {
      final sp = parsedList[index];
      final c = coeffs[index];
      final coeffStr = c > 1 ? '$c' : '';
      final bodyFmt = sp.isElectron
          ? 'e⁻'
          : '${formatFormulaSubscripts(sp.baseFormula)}${formatChargeSuperscript(sp.charge)}';
      return BalancedSpecies(
        formula: sp.rawToken,
        coefficient: c,
        charge: sp.charge,
        formatted: '$coeffStr$bodyFmt',
      );
    }

    final reactants = List<BalancedSpecies>.generate(
      reactantTokens.length,
      (i) => buildSpecies(i),
    );

    final products = List<BalancedSpecies>.generate(
      productTokens.length,
      (i) => buildSpecies(reactantTokens.length + i),
    );

    final balanced =
        '${reactants.map((r) => r.formatted).join(' + ')} $displayArrow ${products.map((p) => p.formatted).join(' + ')}';
    final plain =
        '${reactants.map((r) => '${r.coefficient > 1 ? r.coefficient : ''}${r.formula}').join(' + ')} -> ${products.map((p) => '${p.coefficient > 1 ? p.coefficient : ''}${p.formula}').join(' + ')}';

    return BalancedEquationResult(
      balanced: balanced,
      plain: plain,
      arrow: displayArrow,
      coefficients: coeffs,
      reactants: reactants,
      products: products,
    );
  }

  /// Chuẩn hóa chỉ số dưới Unicode về số ASCII và chuyển điện tích mũ Unicode
  /// (VD: `²⁺`, `⁻`) sang cú pháp `^2+`, `^-` không mơ hồ.
  static String _normalizeUnicodeScripts(String raw) {
    var s = raw.replaceAllMapped(
      RegExp(r'[₀₁₂₃₄₅₆₇₈₉]'),
      (m) => _subscriptDigits.indexOf(m.group(0)!).toString(),
    );
    s = s.replaceAllMapped(RegExp(r'[⁰¹²³⁴⁵⁶⁷⁸⁹]*[⁺⁻]'), (m) {
      final text = m.group(0)!;
      final buf = StringBuffer('^');
      for (int i = 0; i < text.length; i++) {
        final ch = text[i];
        if (ch == '⁺') {
          buf.write('+');
        } else if (ch == '⁻') {
          buf.write('-');
        } else {
          final idx = _superscriptDigits.indexOf(ch);
          if (idx >= 0) buf.write(idx);
        }
      }
      return buf.toString();
    });
    return s;
  }

  /// Tách các chất/ion theo dấu `+` mà KHÔNG cắt nhầm điện tích dương (`Fe2+ + H+`, `Fe2++H+`).
  static List<String> _splitSpecies(String side) {
    final s = side.trim();
    final parts = <String>[];
    final buf = StringBuffer();

    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == '+') {
        final prevIsSpace = i > 0 && s[i - 1].trim().isEmpty;
        final prevIsCaret = i > 0 && s[i - 1] == '^';
        final atEnd = i == s.length - 1;
        final nextChar = atEnd ? '' : s[i + 1];

        // Tìm ký tự không phải khoảng trắng kế tiếp
        int j = i + 1;
        while (j < s.length && s[j].trim().isEmpty) {
          j++;
        }
        final nextNonSpace = j < s.length ? s[j] : '';

        bool isSeparator;
        if (prevIsSpace) {
          isSeparator = true;
        } else if (prevIsCaret || atEnd) {
          isSeparator = false;
        } else if (nextChar == '+') {
          // Trường hợp viết dính `Fe2++H+`: dấu `+` đầu là điện tích, dấu sau là ngăn cách
          isSeparator = false;
        } else if (nextChar.trim().isEmpty && (nextNonSpace == '+' || nextNonSpace.isEmpty)) {
          // Trường hợp `Fe2+ + H+`: dấu `+` ngay sau `Fe2` là điện tích
          isSeparator = false;
        } else {
          // Trường hợp viết dính không khoảng trắng `Fe+O2`, `KMnO4+HCl`
          isSeparator = true;
        }

        if (isSeparator) {
          final token = buf.toString().trim();
          if (token.isNotEmpty) parts.add(token);
          buf.clear();
          continue;
        }
      }
      buf.write(ch);
    }

    final last = buf.toString().trim();
    if (last.isNotEmpty) parts.add(last);
    return parts;
  }

  /// Phân tích một chất hoặc ion thành `{elements, charge}`.
  static _ParsedSpecies _parseSpecies(String token) {
    final t = token.trim();
    if (t == 'e-' || t == 'e^-') {
      return _ParsedSpecies(
        rawToken: 'e-',
        baseFormula: 'e',
        elements: const {},
        charge: -1,
        isElectron: true,
      );
    }

    String baseFormula = t;
    int charge = 0;

    // 1. Điện tích tường minh có dấu `^` (VD: Cr2O7^2-, C2O4^2-, Fe^3+, MnO4^-, Fe^+2)
    final caretIdx = t.lastIndexOf('^');
    if (caretIdx > 0) {
      baseFormula = t.substring(0, caretIdx).trim();
      final chargeStr = t.substring(caretIdx + 1).trim();
      charge = _parseChargeString(chargeStr, t);
    } else if (t.endsWith('+') || t.endsWith('-')) {
      // 2. Điện tích đuôi trực tiếp (VD: MnO4-, Fe2+, Fe3+, H+, OH-, NH4+)
      final sign = t.endsWith('+') ? 1 : -1;
      final beforeSign = t.substring(0, t.length - 1);

      // Nếu là ion đơn nguyên tử có 1 chữ số ngay trước dấu (VD: Fe2+, Mn2+, Cr3+, S2-)
      final monoIonMatch = RegExp(r'^([A-Z][a-z]?)([1-9])$').firstMatch(beforeSign);
      if (monoIonMatch != null) {
        baseFormula = monoIonMatch.group(1)!;
        charge = sign * int.parse(monoIonMatch.group(2)!);
      } else {
        baseFormula = beforeSign;
        charge = sign;
      }
    }

    try {
      final elems = MolarMassCalculator.parseFormula(baseFormula);
      return _ParsedSpecies(
        rawToken: t,
        baseFormula: baseFormula,
        elements: elems,
        charge: charge,
      );
    } on MolarMassException catch (e) {
      throw EquationBalanceException('Lỗi chất "$t": ${e.message}');
    }
  }

  static int _parseChargeString(String chargeStr, String fullToken) {
    final m1 = RegExp(r'^(\d*)([+-])$').firstMatch(chargeStr);
    if (m1 != null) {
      final mag = m1.group(1)!.isEmpty ? 1 : int.parse(m1.group(1)!);
      return m1.group(2) == '+' ? mag : -mag;
    }
    final m2 = RegExp(r'^([+-])(\d+)$').firstMatch(chargeStr);
    if (m2 != null) {
      final mag = int.parse(m2.group(2)!);
      return m2.group(1) == '+' ? mag : -mag;
    }
    throw EquationBalanceException(
      'Điện tích không hợp lệ trong "$fullToken" (dùng VD: Fe2+, Cr2O7^2-, MnO4-).',
    );
  }

  static String _stripLeadingCoeff(String token) {
    final t = token.trim();
    int i = 0;
    while (i < t.length && _isDigit(t.codeUnitAt(i))) {
      i++;
    }
    return i < t.length ? t.substring(i).trim() : t;
  }

  static bool _isDigit(int code) => code >= 48 && code <= 57;

  static BigInt _bgcd(BigInt a, BigInt b) {
    var x = a.abs();
    var y = b.abs();
    while (y != BigInt.zero) {
      final t = x % y;
      x = y;
      y = t;
    }
    return x == BigInt.zero ? BigInt.one : x;
  }

  static BigInt _blcm(BigInt a, BigInt b) {
    if (a == BigInt.zero || b == BigInt.zero) return BigInt.zero;
    final x = a.abs();
    final y = b.abs();
    return (x ~/ _bgcd(x, y)) * y;
  }
}

class _BigFrac {
  final BigInt n;
  final BigInt d;

  const _BigFrac._(this.n, this.d);

  static final _BigFrac zero = _BigFrac._(BigInt.zero, BigInt.one);
  static final _BigFrac one = _BigFrac._(BigInt.one, BigInt.one);

  factory _BigFrac(BigInt num, BigInt den) {
    if (den == BigInt.zero) {
      throw const EquationBalanceException('Chia cho 0 trong quá trình cân bằng.');
    }
    var a = num;
    var b = den;
    if (b < BigInt.zero) {
      a = -a;
      b = -b;
    }
    if (a == BigInt.zero) return zero;
    final g = ChemicalEquationBalancer._bgcd(a, b);
    return _BigFrac._(a ~/ g, b ~/ g);
  }

  factory _BigFrac.fromInt(int v) => _BigFrac._(BigInt.from(v), BigInt.one);

  _BigFrac operator +(_BigFrac o) => _BigFrac(n * o.d + o.n * d, d * o.d);
  _BigFrac operator -(_BigFrac o) => _BigFrac(n * o.d - o.n * d, d * o.d);
  _BigFrac operator *(_BigFrac o) => _BigFrac(n * o.n, d * o.d);
  _BigFrac operator /(_BigFrac o) => _BigFrac(n * o.d, d * o.n);
  _BigFrac operator -() => _BigFrac._(-n, d);
}

/// Giao diện Cân bằng Phương trình Hóa học (phân tử & ion) trực quan cho ChemNote.
class EquationBalancerWidget extends StatefulWidget {
  final ValueChanged<String>? onInsertText;

  const EquationBalancerWidget({
    super.key,
    this.onInsertText,
  });

  @override
  State<EquationBalancerWidget> createState() => _EquationBalancerWidgetState();
}

class _EquationBalancerWidgetState extends State<EquationBalancerWidget> {
  static const List<String> _presets = [
    'MnO4- + Fe2+ + H+ -> Mn2+ + Fe3+ + H2O',
    'Cr2O7^2- + H+ + Fe2+ -> Cr3+ + Fe3+ + H2O',
    'MnO4- + C2O4^2- + H+ -> Mn2+ + CO2 + H2O',
    'KMnO4 + HCl -> KCl + MnCl2 + Cl2 + H2O',
    'Cu + HNO3 -> Cu(NO3)2 + NO + H2O',
    'Fe + O2 -> Fe3O4',
    'FeS2 + O2 -> Fe2O3 + SO2',
  ];

  final TextEditingController _controller = TextEditingController(
    text: 'MnO4- + Fe2+ + H+ -> Mn2+ + Fe3+ + H2O',
  );
  BalancedEquationResult? _result;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _solve(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _solve(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _result = null;
        _errorText = null;
      });
      return;
    }
    try {
      final res = ChemicalEquationBalancer.balance(trimmed);
      setState(() {
        _result = res;
        _errorText = null;
      });
    } on EquationBalanceException catch (e) {
      setState(() {
        _result = null;
        _errorText = e.message;
      });
    }
  }

  void _applyPreset(String eq) {
    _controller.text = eq;
    _controller.selection = TextSelection.collapsed(offset: eq.length);
    _solve(eq);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? const Color(0xFF22252E)
        : colors.primaryContainer.withOpacity(0.45);
    const accentBlue = Color(0xFF3B82F6);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            onChanged: _solve,
            decoration: InputDecoration(
              labelText: 'Nhập phương trình phân tử hoặc ion',
              hintText: 'VD: MnO4- + Fe2+ + H+ -> Mn2+ + Fe3+ + H2O',
              prefixIcon: const Icon(Icons.balance_outlined),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        _solve('');
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
          Text(
            'Ví dụ mẫu (Phân tử & Ion)',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _presets.map((eq) {
              return ActionChip(
                label: Text(
                  eq,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                onPressed: () => _applyPreset(eq),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (_result != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? accentBlue.withOpacity(0.35)
                      : colors.primary.withOpacity(0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: isDark ? accentBlue : colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Phương trình đã cân bằng',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isDark ? accentBlue : colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _result!.balanced,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hệ số tối giản: ${_result!.coefficients.join(' : ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _result!.balanced),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã sao chép phương trình cân bằng'),
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
                              widget.onInsertText!(_result!.balanced),
                          icon: const Icon(Icons.add_comment_outlined, size: 18),
                          label: const Text('Chèn vào trang'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
