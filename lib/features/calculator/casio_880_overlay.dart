import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'casio_math_engine.dart';

enum _CasioMode { calc, home, system, poly }

enum _CalcStage { edit, calcPrompt, calcResult, solvePrompt, solveResult }

enum _CasioSizePreset {
  compact, // ~1/6 screen
  standard, // ~1/5 screen
  wide, // ~1/4 screen
}

/// Máy tính Casio fx-880BTG nổi trên trình ghi chú ChemNote (hỗ trợ MathIO tự nhiên,
/// chạm bút chọn vị trí trực tiếp trên LCD, D-Pad 4 hướng, SHIFT+SOLVE, Hệ PT 2-4 ẩn & Đa thức).
class Casio880Overlay extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<int>? onPointerAcquired;
  final ValueChanged<int>? onPointerReleased;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const Casio880Overlay({
    super.key,
    required this.onClose,
    this.onPointerAcquired,
    this.onPointerReleased,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<Casio880Overlay> createState() => _Casio880OverlayState();
}

class _Casio880OverlayState extends State<Casio880Overlay>
    with SingleTickerProviderStateMixin {
  static const Color _lcdInk = Color(0xFF121A12);
  static const Color _lcdBgTop = Color(0xFFE8F0E2);
  static const Color _lcdBgBottom = Color(0xFFD9E4D0);
  static const Color _shiftGold = Color(0xFFD4A756);
  static const Color _shiftLegend = Color(0xFFFBBF24);
  static const Color _accentBlue = Color(0xFF3B82F6);

  late final AnimationController _caretController;
  final MathDocument _doc = MathDocument();
  final List<List<Map<String, dynamic>>> _history = [];
  int _historyCursor = -1;

  _CasioMode _mode = _CasioMode.calc;
  _CalcStage _calcStage = _CalcStage.edit;
  _CasioSizePreset _sizePreset = _CasioSizePreset.standard;
  bool _minimized = false;

  Offset? _position; // Left, top relative to parent viewport
  int _homeSelection = 0;

  CasioAngleUnit _angleUnit = CasioAngleUnit.deg;
  CasioResultFormat _resultFormat = CasioResultFormat.dec;
  bool _shift = false;
  double _ansValue = 0;
  double _lastCalcNumber = 0;
  bool _calcHasError = false;

  String _promptBuffer = '0';
  List<double> _solveRoots = const [];
  int _activeSolveRootIdx = 0;

  // Simultaneous linear system (2, 3, 4 unknowns)
  int _sysOrder = 2;
  List<List<String>> _sysCells = [
    ['2', '1', '5'],
    ['1', '-1', '1'],
  ];
  int _sysFocusRow = 0;
  int _sysFocusCol = 0;
  LinearSystemResult? _sysResult;

  // Polynomial solver (degree 2, 3)
  int _polyDeg = 2;
  List<String> _polyCells = ['1', '-5', '6'];
  int _polyFocus = 0;
  PolySolveResult? _polyResult;

  @override
  void initState() {
    super.initState();
    _caretController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..repeat(reverse: true);
    _solveSystem();
    _solvePoly();
  }

  @override
  void dispose() {
    _caretController.dispose();
    super.dispose();
  }

  Size _computeBoxSize(Size viewport) {
    final bool isLandscape = viewport.width >= viewport.height;
    if (!isLandscape) {
      final w = (viewport.width * 0.55).clamp(225.0, 306.0);
      final h = (viewport.height * 0.52).clamp(420.0, viewport.height - 16.0);
      return Size(w, h);
    }
    final (double wf, double hf) = switch (_sizePreset) {
      _CasioSizePreset.compact => (0.230, 0.760),
      _CasioSizePreset.standard => (0.250, 0.855),
      _CasioSizePreset.wide => (0.274, 0.920),
    };
    final double maxW = math.max(225.0, viewport.width - 16.0);
    final double maxH = math.max(410.0, viewport.height - 12.0);
    final double w = (viewport.width * wf).clamp(225.0, math.min(350.0, maxW));
    final double h = (viewport.height * hf).clamp(410.0, maxH);
    return Size(w, h);
  }

  Offset _clampPosition(Offset raw, Size boxSize, Size viewport) {
    final maxX = math.max(8.0, viewport.width - boxSize.width - 8.0);
    final maxY = math.max(8.0, viewport.height - boxSize.height - 8.0);
    return Offset(
      raw.dx.clamp(8.0, maxX),
      raw.dy.clamp(8.0, maxY),
    );
  }

  void _cycleSizePreset() {
    setState(() {
      _sizePreset = switch (_sizePreset) {
        _CasioSizePreset.compact => _CasioSizePreset.standard,
        _CasioSizePreset.standard => _CasioSizePreset.wide,
        _CasioSizePreset.wide => _CasioSizePreset.compact,
      };
    });
  }

  String get _sizeLabel => switch (_sizePreset) {
        _CasioSizePreset.compact => '1/6',
        _CasioSizePreset.standard => '1/5',
        _CasioSizePreset.wide => '1/4',
      };

  // ===========================================================================
  // CALCULATOR ACTIONS & STATE MACHINE
  // ===========================================================================

  void _toggleShift() => setState(() => _shift = !_shift);

  void _pressShiftAware(VoidCallback normalFn, VoidCallback shiftFn) {
    final useShift = _shift;
    if (useShift) {
      setState(() => _shift = false);
      shiftFn();
    } else {
      normalFn();
    }
  }

  void _toggleAngleUnit() {
    setState(() {
      _angleUnit = _angleUnit == CasioAngleUnit.deg
          ? CasioAngleUnit.rad
          : CasioAngleUnit.deg;
      _evaluateLiveIfNoEquals();
    });
  }

  void _toggleFormat() {
    setState(() {
      _resultFormat = switch (_resultFormat) {
        CasioResultFormat.dec => CasioResultFormat.frac,
        CasioResultFormat.frac => CasioResultFormat.sci,
        CasioResultFormat.sci => CasioResultFormat.dec,
      };
    });
  }

  void _pressHome() {
    setState(() {
      if (_mode == _CasioMode.home) {
        _mode = _CasioMode.calc;
      } else {
        _homeSelection = switch (_mode) {
          _CasioMode.calc => 0,
          _CasioMode.system => 1,
          _CasioMode.poly => 2,
          _CasioMode.home => 0,
        };
        _mode = _CasioMode.home;
      }
    });
  }

  void _selectHomeItem(int idx) {
    setState(() {
      _homeSelection = idx;
      _mode = switch (idx) {
        1 => _CasioMode.system,
        2 => _CasioMode.poly,
        _ => _CasioMode.calc,
      };
    });
  }

  void _insertChar(String raw) {
    setState(() {
      if (_mode == _CasioMode.system) {
        _editSystemCellChar(raw);
        return;
      }
      if (_mode == _CasioMode.poly) {
        _editPolyCellChar(raw);
        return;
      }
      if (_mode != _CasioMode.calc) return;

      if (_calcStage == _CalcStage.solvePrompt ||
          _calcStage == _CalcStage.calcPrompt) {
        if ('0123456789.-'.contains(raw)) {
          if (raw == '-' && _promptBuffer == '0') {
            _promptBuffer = '-';
          } else if (_promptBuffer == '0' && raw != '.') {
            _promptBuffer = raw;
          } else {
            _promptBuffer += raw;
          }
        }
        return;
      }

      if (_calcStage != _CalcStage.edit) {
        _calcStage = _CalcStage.edit;
      }
      final disp = switch (raw) {
        '*' => '×',
        '/' => '÷',
        '-' => '−',
        _ => raw,
      };
      _doc.insertChar(disp, evalText: raw);
      _evaluateLiveIfNoEquals();
    });
  }

  void _insertConst(String label, String evalToken) {
    setState(() {
      if (_mode != _CasioMode.calc) return;
      if (_calcStage == _CalcStage.solvePrompt ||
          _calcStage == _CalcStage.calcPrompt) {
        if (label == 'Ans') {
          _promptBuffer = CasioFormatter.formatDecimal(_ansValue);
        }
        return;
      }
      if (_calcStage != _CalcStage.edit) _calcStage = _CalcStage.edit;
      _doc.insertChar(label, evalText: evalToken);
      _evaluateLiveIfNoEquals();
    });
  }

  void _insertDocMutation(VoidCallback action) {
    setState(() {
      if (_mode != _CasioMode.calc) _mode = _CasioMode.calc;
      if (_calcStage != _CalcStage.edit) _calcStage = _CalcStage.edit;
      action();
      _evaluateLiveIfNoEquals();
    });
  }

  void _pressCalcOrSolve() {
    final isSolve = _shift;
    setState(() {
      _shift = false;
      if (_mode != _CasioMode.calc) _mode = _CasioMode.calc;
      _promptBuffer = '0';
      _calcStage = isSolve ? _CalcStage.solvePrompt : _CalcStage.calcPrompt;
    });
  }

  void _pressNav(String dir) {
    setState(() {
      if (_mode == _CasioMode.home) {
        if (dir == 'right' || dir == 'down') {
          _homeSelection = (_homeSelection + 1) % 3;
        } else {
          _homeSelection = (_homeSelection + 2) % 3;
        }
        return;
      }
      if (_mode == _CasioMode.system) {
        if (dir == 'left') {
          _sysFocusCol = (_sysFocusCol + _sysOrder) % (_sysOrder + 1);
        } else if (dir == 'right') {
          _sysFocusCol = (_sysFocusCol + 1) % (_sysOrder + 1);
        } else if (dir == 'up') {
          _sysFocusRow = (_sysFocusRow + _sysOrder - 1) % _sysOrder;
        } else if (dir == 'down') {
          _sysFocusRow = (_sysFocusRow + 1) % _sysOrder;
        }
        return;
      }
      if (_mode == _CasioMode.poly) {
        final count = _polyDeg + 1;
        if (dir == 'left' || dir == 'up') {
          _polyFocus = (_polyFocus + count - 1) % count;
        } else {
          _polyFocus = (_polyFocus + 1) % count;
        }
        return;
      }

      if (_calcStage == _CalcStage.solveResult &&
          _solveRoots.length > 1 &&
          (dir == 'up' || dir == 'down')) {
        _activeSolveRootIdx = dir == 'down'
            ? (_activeSolveRootIdx + 1) % _solveRoots.length
            : (_activeSolveRootIdx + _solveRoots.length - 1) %
                _solveRoots.length;
        return;
      }

      if (_calcStage != _CalcStage.edit) {
        _calcStage = _CalcStage.edit;
        return;
      }

      switch (dir) {
        case 'left':
          _doc.moveLeft();
        case 'right':
          _doc.moveRight();
        case 'up':
          if (!_doc.moveUp() && _history.isNotEmpty) {
            _historyCursor = _historyCursor < 0
                ? _history.length - 1
                : math.max(0, _historyCursor - 1);
            _doc.restoreSnapshot(_history[_historyCursor]);
            _evaluateLiveIfNoEquals();
          }
        case 'down':
          if (!_doc.moveDown() &&
              _history.isNotEmpty &&
              _historyCursor >= 0 &&
              _historyCursor < _history.length - 1) {
            _historyCursor++;
            _doc.restoreSnapshot(_history[_historyCursor]);
            _evaluateLiveIfNoEquals();
          }
      }
    });
  }

  void _pressOk() {
    if (_mode == _CasioMode.home) {
      _selectHomeItem(_homeSelection);
      return;
    }
    _pressExe();
  }

  void _pressBackspace() {
    setState(() {
      if (_mode == _CasioMode.system) {
        final cur = _sysCells[_sysFocusRow][_sysFocusCol];
        _sysCells[_sysFocusRow][_sysFocusCol] =
            cur.length > 1 ? cur.substring(0, cur.length - 1) : '0';
        return;
      }
      if (_mode == _CasioMode.poly) {
        final cur = _polyCells[_polyFocus];
        _polyCells[_polyFocus] =
            cur.length > 1 ? cur.substring(0, cur.length - 1) : '0';
        return;
      }
      if (_mode != _CasioMode.calc) return;

      if (_calcStage == _CalcStage.solvePrompt ||
          _calcStage == _CalcStage.calcPrompt) {
        _promptBuffer = _promptBuffer.length > 1
            ? _promptBuffer.substring(0, _promptBuffer.length - 1)
            : '0';
        return;
      }
      if (_calcStage != _CalcStage.edit) _calcStage = _CalcStage.edit;
      _doc.backspace();
      _evaluateLiveIfNoEquals();
    });
  }

  void _pressClear() {
    setState(() {
      if (_mode == _CasioMode.system) {
        _sysCells[_sysFocusRow][_sysFocusCol] = '0';
        _sysResult = null;
        return;
      }
      if (_mode == _CasioMode.poly) {
        _polyCells[_polyFocus] = '0';
        _polyResult = null;
        return;
      }
      if (_mode == _CasioMode.home) {
        _mode = _CasioMode.calc;
        return;
      }
      _doc.clear();
      _calcStage = _CalcStage.edit;
      _lastCalcNumber = 0;
      _calcHasError = false;
    });
  }

  void _pressExe() {
    setState(() {
      if (_mode == _CasioMode.home) {
        _selectHomeItem(_homeSelection);
        return;
      }
      if (_mode == _CasioMode.system) {
        if (_sysFocusCol < _sysOrder) {
          _sysFocusCol++;
        } else if (_sysFocusRow < _sysOrder - 1) {
          _sysFocusRow++;
          _sysFocusCol = 0;
        }
        _solveSystem();
        return;
      }
      if (_mode == _CasioMode.poly) {
        if (_polyFocus < _polyDeg) _polyFocus++;
        _solvePoly();
        return;
      }

      if (_calcStage == _CalcStage.solvePrompt) {
        _runShiftSolve();
        return;
      }
      if (_calcStage == _CalcStage.calcPrompt) {
        _runCalcAtX();
        return;
      }

      if (_doc.hasEquals) {
        _promptBuffer = '0';
        _calcStage = _CalcStage.solvePrompt;
        return;
      }

      _history.add(_doc.cloneSnapshot());
      if (_history.length > 20) _history.removeAt(0);
      _historyCursor = -1;
      _evaluateLiveIfNoEquals(recordAns: true);
    });
  }

  void _evaluateLiveIfNoEquals({bool recordAns = false}) {
    if (_doc.hasEquals) return;
    final expr = _doc.toEvalString().trim();
    if (expr.isEmpty) {
      _lastCalcNumber = 0;
      _calcHasError = false;
      return;
    }
    try {
      final val = CasioMathEvaluator.evaluate(
        expr,
        angleUnit: _angleUnit,
        ansValue: _ansValue,
      );
      if (!val.isFinite) throw const FormatException('Math Error');
      _lastCalcNumber = val;
      _calcHasError = false;
      if (recordAns) _ansValue = val;
    } catch (_) {
      _calcHasError = recordAns;
    }
  }

  void _runCalcAtX() {
    double xVal = 0;
    try {
      xVal = CasioMathEvaluator.evaluate(
        _promptBuffer,
        angleUnit: _angleUnit,
        ansValue: _ansValue,
      );
    } catch (_) {
      xVal = 0;
    }
    final expr = _doc.toEvalString().split('=').first;
    try {
      final val = CasioMathEvaluator.evaluate(
        expr,
        x: xVal,
        angleUnit: _angleUnit,
        ansValue: _ansValue,
      );
      if (!val.isFinite) throw const FormatException('Math');
      _lastCalcNumber = val;
      _ansValue = val;
      _calcHasError = false;
      _calcStage = _CalcStage.calcResult;
    } catch (_) {
      _calcHasError = true;
      _calcStage = _CalcStage.calcResult;
    }
  }

  void _runShiftSolve() {
    double x0 = 0;
    try {
      x0 = CasioMathEvaluator.evaluate(
        _promptBuffer,
        angleUnit: _angleUnit,
        ansValue: _ansValue,
      );
    } catch (_) {
      x0 = 0;
    }
    final res = CasioSolvers.solveArbitraryEquation(
      _doc.toEvalString(),
      initialGuess: x0,
      angleUnit: _angleUnit,
      ansValue: _ansValue,
    );
    _solveRoots = res.roots;
    _activeSolveRootIdx = 0;
    _calcHasError = !res.hasRoots;
    if (res.hasRoots) {
      _ansValue = res.roots.first;
    }
    _calcStage = _CalcStage.solveResult;
  }

  // ===========================================================================
  // SYSTEM & POLYNOMIAL CELL LOGIC
  // ===========================================================================

  static const _sysDefaults = <int, List<List<String>>>{
    2: [
      ['2', '1', '5'],
      ['1', '-1', '1'],
    ],
    3: [
      ['1', '1', '1', '6'],
      ['2', '-1', '1', '3'],
      ['1', '2', '-1', '2'],
    ],
    4: [
      ['1', '1', '1', '1', '10'],
      ['2', '-1', '1', '0', '3'],
      ['1', '2', '-1', '1', '6'],
      ['0', '1', '2', '-1', '4'],
    ],
  };

  void _setSystemOrder(int order) {
    setState(() {
      _sysOrder = order;
      _sysCells = [
        for (final row in _sysDefaults[order]!) List<String>.from(row),
      ];
      _sysFocusRow = 0;
      _sysFocusCol = 0;
      _solveSystem();
    });
  }

  void _editSystemCellChar(String raw) {
    var cur = _sysCells[_sysFocusRow][_sysFocusCol];
    if (raw == '-' && cur == '0') {
      cur = '-';
    } else if ('0123456789.'.contains(raw)) {
      cur = cur == '0' ? raw : '$cur$raw';
    }
    _sysCells[_sysFocusRow][_sysFocusCol] = cur;
  }

  void _solveSystem() {
    final mat = <List<double>>[];
    for (int r = 0; r < _sysOrder; r++) {
      final row = <double>[];
      for (int c = 0; c <= _sysOrder; c++) {
        final v = double.tryParse(_sysCells[r][c]);
        if (v == null || !v.isFinite) {
          _sysResult = null;
          return;
        }
        row.add(v);
      }
      mat.add(row);
    }
    final res = CasioSolvers.solveLinearSystem(mat);
    _sysResult = res;
    if (res.status == LinearSystemStatus.unique && res.values.isNotEmpty) {
      _ansValue = res.values.first;
    }
  }

  void _setPolyDegree(int deg) {
    setState(() {
      _polyDeg = deg;
      _polyCells = deg == 2 ? ['1', '-5', '6'] : ['1', '-6', '11', '-6'];
      _polyFocus = 0;
      _solvePoly();
    });
  }

  void _editPolyCellChar(String raw) {
    var cur = _polyCells[_polyFocus];
    if (raw == '-' && cur == '0') {
      cur = '-';
    } else if ('0123456789.'.contains(raw)) {
      cur = cur == '0' ? raw : '$cur$raw';
    }
    _polyCells[_polyFocus] = cur;
  }

  void _solvePoly() {
    final nums = <double>[];
    for (final s in _polyCells) {
      final v = double.tryParse(s);
      if (v == null || !v.isFinite) {
        _polyResult = null;
        return;
      }
      nums.add(v);
    }
    final res = _polyDeg == 2
        ? CasioSolvers.solveQuadratic(nums[0], nums[1], nums[2])
        : CasioSolvers.solveCubic(nums[0], nums[1], nums[2], nums[3]);
    _polyResult = res;
    if (res.realRoots.isNotEmpty) {
      _ansValue = res.realRoots.first;
    }
  }

  // ===========================================================================
  // UI BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          if (viewport.isEmpty) return const SizedBox.shrink();

          if (_minimized) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) =>
                        widget.onPointerAcquired?.call(e.pointer),
                    onPointerUp: (e) =>
                        widget.onPointerReleased?.call(e.pointer),
                    onPointerCancel: (e) =>
                        widget.onPointerReleased?.call(e.pointer),
                    child: Material(
                      color: const Color(0xFF1E2128),
                      elevation: 10,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => setState(() => _minimized = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _accentBlue.withAlpha(200),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calculate_outlined,
                                size: 16,
                                color: Color(0xFF93C5FD),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Casio fx-880BTG',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                CasioFormatter.formatDecimal(_ansValue),
                                style: const TextStyle(
                                  color: Color(0xFF93C5FD),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          final boxSize = _computeBoxSize(viewport);
          final pos = _clampPosition(
            _position ?? Offset(viewport.width - boxSize.width - 14.0, 10.0),
            boxSize,
            viewport,
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: pos.dx,
                top: pos.dy,
                width: boxSize.width,
                height: boxSize.height,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) =>
                      widget.onPointerAcquired?.call(e.pointer),
                  onPointerUp: (e) => widget.onPointerReleased?.call(e.pointer),
                  onPointerCancel: (e) =>
                      widget.onPointerReleased?.call(e.pointer),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF272B35),
                          Color(0xFF191C23),
                          Color(0xFF12141A),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withAlpha(36),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(140),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: Column(
                        children: [
                          _buildDragHeader(pos, boxSize, viewport),
                          _buildLcd(boxSize),
                          Expanded(child: _buildKeypad()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDragHeader(Offset pos, Size boxSize, Size viewport) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => widget.onDragStart?.call(),
      onPanUpdate: (details) {
        setState(() {
          _position = _clampPosition(
            (_position ?? pos) + details.delta,
            boxSize,
            viewport,
          );
        });
      },
      onPanEnd: (_) => widget.onDragEnd?.call(),
      onPanCancel: () => widget.onDragEnd?.call(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border(
            bottom: BorderSide(color: Colors.white.withAlpha(22)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.drag_indicator_rounded,
              size: 14,
              color: Colors.white.withAlpha(110),
            ),
            const SizedBox(width: 3),
            const Text(
              'CASIO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 4),
            const Flexible(
              child: Text(
                'fx-880BTG',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF60A5FA),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: _cycleSizePreset,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _sizeLabel,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () => setState(() => _minimized = true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.remove_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: widget.onClose,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withAlpha(42),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Color(0xFFFCA5A5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // CLASSWIZ NATURAL LCD & DIRECT TAP-TO-CURSOR MATHIO RENDERER
  // ===========================================================================

  Widget _buildLcd(Size boxSize) {
    final double lcdHeight = (boxSize.height * 0.255).clamp(106.0, 128.0);
    final String modeLabel = switch (_mode) {
      _CasioMode.calc => 'TÍNH TOÁN',
      _CasioMode.home => 'HOME',
      _CasioMode.system => 'HỆ PT',
      _CasioMode.poly => 'ĐA THỨC',
    };

    return Container(
      height: lcdHeight,
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_lcdBgTop, _lcdBgBottom],
        ),
        border: Border.all(color: Colors.black.withAlpha(55), width: 1),
      ),
      child: Column(
        children: [
          // Top LCD Status Bar (D/R, SHIFT, DEC/FRAC/SCI, MathI, Multi-root pager, Mode)
          Container(
            padding: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _lcdInk.withAlpha(35), width: 0.8),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _toggleAngleUnit,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _lcdInk,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _angleUnit == CasioAngleUnit.deg ? 'D' : 'R',
                      style: const TextStyle(
                        color: _lcdBgTop,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (_shift) ...[
                  const SizedBox(width: 3),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'S',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _toggleFormat,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _lcdInk.withAlpha(90),
                        width: 0.8,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _resultFormat.name.toUpperCase(),
                      style: const TextStyle(
                        color: _lcdInk,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'MathI',
                  style: TextStyle(
                    color: _lcdInk.withAlpha(175),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (_mode == _CasioMode.calc &&
                    _calcStage == _CalcStage.solveResult &&
                    _solveRoots.length > 1) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: _lcdInk.withAlpha(28),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${_activeSolveRootIdx + 1}/${_solveRoots.length} ▲▼',
                      style: const TextStyle(
                        color: _lcdInk,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                Text(
                  modeLabel,
                  style: TextStyle(
                    color: _lcdInk.withAlpha(210),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: switch (_mode) {
              _CasioMode.calc => _buildCalcLcdBody(),
              _CasioMode.home => _buildHomeLcdBody(),
              _CasioMode.system => _buildSystemLcdBody(),
              _CasioMode.poly => _buildPolyLcdBody(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalcLcdBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Upper editable MathIO expression (stylus/tap anywhere sets cursor)
        Expanded(
          child: Builder(
            builder: (vpCtx) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final box = vpCtx.findRenderObject() as RenderBox?;
                  final atStart =
                      box != null && details.localPosition.dx < 14.0;
                  setState(() {
                    if (_calcStage != _CalcStage.edit) {
                      _calcStage = _CalcStage.edit;
                    }
                    _doc.setCursor(
                      _doc.rootRow.id,
                      atStart ? 0 : _doc.rootRow.items.length,
                    );
                  });
                },
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 2, horizontal: 2),
                        child: _buildMathRowWidget(_doc.rootRow, 17.5),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Bottom full-width result / prompt row (no L-R=0 clutter)
        Container(
          height: 28,
          padding: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: _lcdInk.withAlpha(38), width: 0.8),
            ),
          ),
          child: _buildCalcBottomRow(),
        ),
      ],
    );
  }

  Widget _buildCalcBottomRow() {
    if (_calcStage == _CalcStage.solvePrompt ||
        _calcStage == _CalcStage.calcPrompt) {
      final isSolve = _calcStage == _CalcStage.solvePrompt;
      return Row(
        children: [
          Text(
            isSolve ? 'SOLVE x₀=' : 'CALC x=',
            style: TextStyle(
              color: isSolve ? const Color(0xFF92400E) : _lcdInk,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _lcdInk,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _promptBuffer,
              style: const TextStyle(
                color: _lcdBgTop,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '→ EXE',
            style: TextStyle(
              color: _lcdInk.withAlpha(180),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    if (_calcStage == _CalcStage.solveResult) {
      if (_solveRoots.isEmpty) {
        return const Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Không tìm thấy nghiệm',
            style: TextStyle(
              color: _lcdInk,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }
      final val = _solveRoots[_activeSolveRootIdx];
      return Align(
        alignment: Alignment.centerRight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _mathText('x', italic: true, fontSize: 16.5),
              _mathText(' = ', fontSize: 16.5),
              _buildFormattedValueWidget(val, fontSize: 16.5, stackedFrac: true),
            ],
          ),
        ),
      );
    }

    if (_doc.hasEquals) {
      return Align(
        alignment: Alignment.centerRight,
        child: Text(
          'SHIFT + SOLVE hoặc EXE',
          style: TextStyle(
            color: _lcdInk.withAlpha(185),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (_calcHasError) {
      return const Align(
        alignment: Alignment.centerRight,
        child: Text(
          'Syntax Error',
          style: TextStyle(
            color: _lcdInk,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: _buildFormattedValueWidget(
          _lastCalcNumber,
          fontSize: 16.5,
          stackedFrac: true,
        ),
      ),
    );
  }

  TextStyle _serifMathStyle(
    double fontSize, {
    bool italic = false,
    FontWeight weight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: 'serif',
      fontSize: fontSize,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontWeight: weight,
      color: _lcdInk,
      height: 1.18,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  Widget _mathText(
    String text, {
    double fontSize = 17.5,
    bool italic = false,
  }) {
    return Text(
      text,
      style: _serifMathStyle(fontSize, italic: italic),
    );
  }

  Widget _buildFormattedValueWidget(
    double value, {
    double fontSize = 16.0,
    bool stackedFrac = true,
  }) {
    if (!value.isFinite) return _mathText('Math Error', fontSize: fontSize);
    if (_resultFormat == CasioResultFormat.sci) {
      return _buildScientificWidget(value, fontSize: fontSize);
    }
    if (_resultFormat == CasioResultFormat.frac) {
      final frac = CasioFormatter.toFraction(value);
      if (frac != null && frac.den > 1) {
        if (!stackedFrac) {
          final nStr = frac.num < 0 ? '−${frac.num.abs()}' : '${frac.num}';
          return _mathText('$nStr/${frac.den}', fontSize: fontSize);
        }
        final nStr = frac.num < 0 ? '−${frac.num.abs()}' : '${frac.num}';
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(nStr, style: _serifMathStyle(fontSize * 0.68)),
            Container(
              height: 1.0,
              width: math.max(14.0, math.max(nStr.length, '${frac.den}'.length) * fontSize * 0.44),
              color: _lcdInk,
              margin: const EdgeInsets.symmetric(vertical: 1),
            ),
            Text('${frac.den}', style: _serifMathStyle(fontSize * 0.68)),
          ],
        );
      }
    }
    final dec = CasioFormatter.formatDecimal(value);
    if (dec.contains('×10^')) {
      return _buildScientificWidget(value, fontSize: fontSize);
    }
    return _mathText(dec.replaceFirst('-', '−'), fontSize: fontSize);
  }

  Widget _buildScientificWidget(double value, {double fontSize = 16.0}) {
    if (value.abs() < 1e-12) return _mathText('0', fontSize: fontSize);
    final parts = CasioFormatter.formatScientificParts(value);
    final mant = parts.mantissa.replaceFirst('-', '−');
    final expStr = parts.exponent < 0
        ? '−${parts.exponent.abs()}'
        : '${parts.exponent}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        _mathText('$mant × 10', fontSize: fontSize),
        Transform.translate(
          offset: Offset(0, -fontSize * 0.34),
          child: _mathText(expStr, fontSize: fontSize * 0.68),
        ),
      ],
    );
  }

  // ===========================================================================
  // MATHIO INLINE TREE BUILDER + DIRECT TAP-TO-CURSOR
  // ===========================================================================

  Widget _buildCaret(double fontSize) {
    return FadeTransition(
      opacity: _caretController,
      child: Container(
        width: 1.6,
        height: fontSize * 1.04,
        color: _lcdInk,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
      ),
    );
  }

  Widget _buildMathRowWidget(MathRow row, double fontSize) {
    final bool showCaret = _mode == _CasioMode.calc &&
        _calcStage == _CalcStage.edit &&
        _doc.cursor.rowId == row.id;

    if (row.items.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            if (_calcStage != _CalcStage.edit) _calcStage = _CalcStage.edit;
            _doc.setCursor(row.id, 0);
          });
        },
        child: Container(
          constraints: BoxConstraints(
            minWidth: fontSize * 0.62,
            minHeight: fontSize * 0.92,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: _lcdInk.withAlpha(110),
              width: 0.9,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: showCaret ? _buildCaret(fontSize * 0.85) : const SizedBox.shrink(),
        ),
      );
    }

    final spans = <InlineSpan>[];
    for (int i = 0; i <= row.items.length; i++) {
      if (showCaret && _doc.cursor.index == i) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _buildCaret(fontSize),
          ),
        );
      }
      if (i < row.items.length) {
        final node = row.items[i];
        spans.add(_buildNodeSpan(node, row.id, i, fontSize));
      }
    }

    return Text.rich(
      TextSpan(children: spans, style: _serifMathStyle(fontSize)),
    );
  }

  InlineSpan _buildNodeSpan(
    MathNode node,
    String rowId,
    int index,
    double fontSize,
  ) {
    Widget wrapTap(Widget child) {
      return Builder(
        builder: (nodeCtx) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final box = nodeCtx.findRenderObject() as RenderBox?;
            final bool after = box != null &&
                details.localPosition.dx >= box.size.width * 0.5;
            setState(() {
              if (_calcStage != _CalcStage.edit) _calcStage = _CalcStage.edit;
              _doc.setCursor(rowId, after ? index + 1 : index);
            });
          },
          child: child,
        ),
      );
    }

    switch (node.type) {
      case MathNodeType.textChar:
        Widget charWidget;
        if (node.text == 'x') {
          charWidget = Padding(
            padding: const EdgeInsets.only(left: 0.5, right: 1.5),
            child: _mathText('x', fontSize: fontSize, italic: true),
          );
        } else if (node.text == '=') {
          charWidget = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.5),
            child: _mathText('=', fontSize: fontSize),
          );
        } else if (node.text == '+' || node.text == '−') {
          charWidget = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3.5),
            child: _mathText(node.text, fontSize: fontSize),
          );
        } else if (node.text == '×' || node.text == '÷') {
          charWidget = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: _mathText(node.text, fontSize: fontSize),
          );
        } else {
          charWidget = _mathText(node.text, fontSize: fontSize);
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: wrapTap(charWidget),
        );

      case MathNodeType.frac:
        final subSize = math.max(10.5, fontSize * 0.80);
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: wrapTap(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(3, 0, 3, 1.5),
                      child: _buildMathRowWidget(node.num!, subSize),
                    ),
                    Container(
                      height: 1.2,
                      color: _lcdInk,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(3, 1.5, 3, 0),
                      child: _buildMathRowWidget(node.den!, subSize),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

      case MathNodeType.sqrt:
      case MathNodeType.cbrt:
        final subSize = math.max(11.0, fontSize * 0.88);
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: wrapTap(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (node.type == MathNodeType.cbrt)
                      Align(
                        alignment: Alignment.topLeft,
                        child: Transform.translate(
                          offset: const Offset(2, -1),
                          child: _mathText('3', fontSize: fontSize * 0.56),
                        ),
                      ),
                    CustomPaint(
                      size: Size(9.5, subSize * 1.15),
                      painter: const _RadicalPainter(color: _lcdInk),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: _lcdInk, width: 1.25),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(1.5, 1.5, 2.5, 0),
                      child: _buildMathRowWidget(node.body!, subSize),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

      case MathNodeType.pow:
        final supSize = math.max(9.5, fontSize * 0.68);
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Transform.translate(
            offset: Offset(0, -fontSize * 0.36),
            child: Padding(
              padding: const EdgeInsets.only(left: 0.5, right: 1.0),
              child: _buildMathRowWidget(node.exp!, supSize),
            ),
          ),
        );

      case MathNodeType.pow10:
        final supSize = math.max(9.5, fontSize * 0.68);
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              wrapTap(
                Padding(
                  padding: const EdgeInsets.only(left: 1.5),
                  child: _mathText('×10', fontSize: fontSize),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -fontSize * 0.36),
                child: Padding(
                  padding: const EdgeInsets.only(left: 0.5, right: 1.0),
                  child: _buildMathRowWidget(node.exp!, supSize),
                ),
              ),
            ],
          ),
        );

      case MathNodeType.fn:
        final subSize = math.max(11.0, fontSize * 0.92);
        final isAbs = node.fnName == 'abs';
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              wrapTap(_mathText(isAbs ? '|' : '${node.fnName}(',
                  fontSize: fontSize)),
              _buildMathRowWidget(node.body!, subSize),
              wrapTap(_mathText(isAbs ? '|' : ')', fontSize: fontSize)),
            ],
          ),
        );
    }
  }

  Widget _buildHomeLcdBody() {
    const items = <(String, String)>[
      ('＋－×÷', 'Tính toán'),
      ('ax+by', 'Hệ PT'),
      ('ax²+bx', 'Đa thức'),
    ];
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: () => _selectHomeItem(i),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _homeSelection == i
                      ? _lcdInk
                      : Colors.white.withAlpha(110),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _lcdInk.withAlpha(_homeSelection == i ? 255 : 80),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      items[i].$1,
                      style: TextStyle(
                        color: _homeSelection == i ? _lcdBgTop : _lcdInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      items[i].$2,
                      style: TextStyle(
                        color: _homeSelection == i ? _lcdBgTop : _lcdInk,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSystemLcdBody() {
    const vars = ['x', 'y', 'z', 't'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final n in const [2, 3, 4]) ...[
              GestureDetector(
                onTap: () => _setSystemOrder(n),
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: _sysOrder == n ? _lcdInk : _lcdInk.withAlpha(32),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '$n ẩn',
                    style: TextStyle(
                      color: _sysOrder == n ? _lcdBgTop : _lcdInk,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              '▲▼◀▶ · EXE',
              style: TextStyle(
                color: _lcdInk.withAlpha(170),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _sysOrder,
            itemBuilder: (_, r) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int c = 0; c <= _sysOrder; c++) ...[
                      GestureDetector(
                        onTap: () => setState(() {
                          _sysFocusRow = r;
                          _sysFocusCol = c;
                        }),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _sysFocusRow == r && _sysFocusCol == c
                                ? _lcdInk
                                : Colors.white.withAlpha(120),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: _lcdInk.withAlpha(70),
                              width: 0.7,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _sysCells[r][c],
                            style: TextStyle(
                              color: _sysFocusRow == r && _sysFocusCol == c
                                  ? _lcdBgTop
                                  : _lcdInk,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (c < _sysOrder - 1)
                        _mathText('${vars[c]}+', fontSize: 10.5)
                      else if (c == _sysOrder - 1)
                        _mathText('${vars[c]}=', fontSize: 10.5),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 20,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: _lcdInk.withAlpha(38), width: 0.8),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildSystemResultWidget(),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemResultWidget() {
    const vars = ['x', 'y', 'z', 't'];
    final res = _sysResult;
    if (res == null) {
      return const Text(
        'Nhập hệ số · EXE để giải',
        style: TextStyle(
          color: _lcdInk,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    if (res.status == LinearSystemStatus.noSolution) {
      return const Text(
        'Hệ VÔ NGHIỆM',
        style: TextStyle(
          color: _lcdInk,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    if (res.status == LinearSystemStatus.infiniteSolutions) {
      return const Text(
        'Hệ VÔ SỐ NGHIỆM',
        style: TextStyle(
          color: _lcdInk,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    if (res.status == LinearSystemStatus.invalidInput) {
      return const Text(
        'Lỗi hệ số',
        style: TextStyle(
          color: _lcdInk,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < res.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _mathText(vars[i], fontSize: 11.5, italic: true),
          _mathText('=', fontSize: 11.5),
          _buildFormattedValueWidget(
            res.values[i],
            fontSize: 11.5,
            stackedFrac: false,
          ),
        ],
      ],
    );
  }

  Widget _buildPolyLcdBody() {
    final labels = _polyDeg == 2 ? const ['a', 'b', 'c'] : const ['a', 'b', 'c', 'd'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final d in const [2, 3]) ...[
              GestureDetector(
                onTap: () => _setPolyDegree(d),
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: _polyDeg == d ? _lcdInk : _lcdInk.withAlpha(32),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    d == 2 ? 'ax²+bx+c=0' : 'Bậc 3',
                    style: TextStyle(
                      color: _polyDeg == d ? _lcdBgTop : _lcdInk,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              '◀▶ · EXE',
              style: TextStyle(
                color: _lcdInk.withAlpha(170),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < labels.length; i++) ...[
                    _mathText('${labels[i]}=', fontSize: 11.5, italic: true),
                    GestureDetector(
                      onTap: () => setState(() => _polyFocus = i),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 26),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: _polyFocus == i
                              ? _lcdInk
                              : Colors.white.withAlpha(120),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _lcdInk.withAlpha(80),
                            width: 0.7,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _polyCells[i],
                          style: TextStyle(
                            color: _polyFocus == i ? _lcdBgTop : _lcdInk,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Container(
          height: 22,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: _lcdInk.withAlpha(38), width: 0.8),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildPolyResultWidget(),
          ),
        ),
      ],
    );
  }

  Widget _buildPolyResultWidget() {
    final res = _polyResult;
    if (res == null) {
      return const Text(
        'Nhấn EXE để giải',
        style: TextStyle(
          color: _lcdInk,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    if (res.errorMessage != null) {
      return Text(
        res.errorMessage!,
        style: const TextStyle(
          color: _lcdInk,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < res.realRoots.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _mathText('x', fontSize: 11.5, italic: true),
          _mathText(
            res.realRoots.length == 1 && res.complexReal == null
                ? '₁=x₂='
                : '${i + 1}=',
            fontSize: 10,
          ),
          _buildFormattedValueWidget(
            res.realRoots[i],
            fontSize: 11.5,
            stackedFrac: false,
          ),
        ],
        if (res.complexReal != null && res.complexImag != null) ...[
          if (res.realRoots.isNotEmpty) const SizedBox(width: 8),
          _mathText(
            '${CasioFormatter.formatDecimal(res.complexReal!).replaceFirst('-', '−')}±${CasioFormatter.formatDecimal(res.complexImag!)}i',
            fontSize: 11.5,
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // AUTHENTIC CASIO fx-880BTG KEYPAD (NO tan / sin⁻¹ / cos⁻¹ / extra buttons)
  // ===========================================================================

  Widget _buildKeypad() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 2, 7, 7),
      child: Column(
        children: [
          // Top Cluster: HOME+SHIFT | Circular 4-Way D-Pad (▲▼◀▶+OK) | = + CALC(SOLVE)
          Expanded(
            flex: 19,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Expanded(
                        child: _casioTopPill(
                          legend: 'MENU',
                          label: 'HOME',
                          bg: const Color(0xFF3A3F4B),
                          fg: Colors.white,
                          onTap: _pressHome,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: _casioTopPill(
                          legend: 'SHIFT',
                          label: '⇧',
                          bg: _shiftGold,
                          fg: const Color(0xFF181A1F),
                          highlight: _shift,
                          onTap: _toggleShift,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 5,
                  child: _buildCircularDPad(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Expanded(
                        child: _casioTopPill(
                          legend: '≠',
                          label: '=',
                          labelFontSize: 14.0,
                          bg: const Color(0xFF2B303C),
                          fg: const Color(0xFF6EE7B7),
                          onTap: () => _insertChar('='),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Expanded(
                        child: _casioTopPill(
                          legend: 'SOLVE',
                          label: 'CALC',
                          bg: const Color(0xFF2B303C),
                          fg: Colors.white,
                          highlight: _shift,
                          onTap: _pressCalcOrSolve,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),

          // Sci Row 1: x | □/□ | √□ | x□ | x² | log (taller & no "a b/c")
          Expanded(
            flex: 12,
            child: Row(
              children: [
                _sciKey(
                  label: 'x',
                  italic: true,
                  fg: const Color(0xFF93C5FD),
                  onTap: () => _insertDocMutation(
                    () => _doc.insertChar('x', evalText: 'x'),
                  ),
                ),
                _sciKey(
                  label: '□/□',
                  onTap: () => _insertDocMutation(_doc.insertFraction),
                ),
                _sciKey(
                  legend: '³√',
                  label: '√□',
                  onTap: () => _pressShiftAware(
                    () => _insertDocMutation(_doc.insertSqrt),
                    () => _insertDocMutation(_doc.insertCbrt),
                  ),
                ),
                _sciKey(
                  legend: 'x⁻¹',
                  label: 'x□',
                  onTap: () => _pressShiftAware(
                    () => _insertDocMutation(_doc.insertPowerEmpty),
                    () => _insertDocMutation(() => _doc.insertPowerWith('-1')),
                  ),
                ),
                _sciKey(
                  legend: 'x³',
                  label: 'x²',
                  onTap: () => _pressShiftAware(
                    () => _insertDocMutation(() => _doc.insertPowerWith('2')),
                    () => _insertDocMutation(() => _doc.insertPowerWith('3')),
                  ),
                ),
                _sciKey(
                  legend: '10ˣ',
                  label: 'log',
                  onTap: () => _pressShiftAware(
                    () => _insertDocMutation(() => _doc.insertFn('log')),
                    () => _insertDocMutation(_doc.insertTenPow),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Sci Row 2: Ans | sin | cos | ( | ) | ln (NO tan, NO sin⁻¹, NO cos⁻¹)
          Expanded(
            flex: 12,
            child: Row(
              children: [
                _sciKey(
                  label: 'Ans',
                  fg: const Color(0xFF93C5FD),
                  onTap: () => _insertConst('Ans', 'ans'),
                ),
                _sciKey(
                  label: 'sin',
                  onTap: () => _insertDocMutation(() => _doc.insertFn('sin')),
                ),
                _sciKey(
                  label: 'cos',
                  onTap: () => _insertDocMutation(() => _doc.insertFn('cos')),
                ),
                _sciKey(
                  legend: '|x|',
                  label: '(',
                  onTap: () => _pressShiftAware(
                    () => _insertChar('('),
                    () => _insertDocMutation(() => _doc.insertFn('abs')),
                  ),
                ),
                _sciKey(
                  legend: 'x!',
                  label: ')',
                  onTap: () => _pressShiftAware(
                    () => _insertChar(')'),
                    () => _insertChar('!'),
                  ),
                ),
                _sciKey(
                  legend: 'eˣ',
                  label: 'ln',
                  onTap: () => _pressShiftAware(
                    () => _insertDocMutation(() => _doc.insertFn('ln')),
                    () => _insertDocMutation(_doc.insertEExp),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),

          // Numpad (5 cols × 4 rows) with large crisp characters
          Expanded(
            flex: 45,
            child: Column(
              children: [
                _numRow([
                  _numKey(
                    '7',
                    legend: 'π',
                    fontSize: 16.5,
                    onTap: () => _pressShiftAware(
                      () => _insertChar('7'),
                      () => _insertConst('π', 'pi'),
                    ),
                  ),
                  _numKey(
                    '8',
                    legend: 'e',
                    fontSize: 16.5,
                    onTap: () => _pressShiftAware(
                      () => _insertChar('8'),
                      () => _insertConst('e', 'e'),
                    ),
                  ),
                  _numKey('9', onTap: () => _insertChar('9')),
                  _numKey(
                    '⌫',
                    bg: const Color(0xFF475569),
                    fg: const Color(0xFFFDE68A),
                    fontSize: 17.5,
                    onTap: _pressBackspace,
                  ),
                  _numKey(
                    'AC',
                    bg: const Color(0xFF64748B),
                    fg: Colors.white,
                    fontSize: 14.5,
                    onTap: _pressClear,
                  ),
                ]),
                const SizedBox(height: 4),
                _numRow([
                  _numKey('4', onTap: () => _insertChar('4')),
                  _numKey('5', onTap: () => _insertChar('5')),
                  _numKey('6', onTap: () => _insertChar('6')),
                  _numKey(
                    '×',
                    bg: const Color(0xFF2E3440),
                    onTap: () => _insertChar('*'),
                  ),
                  _numKey(
                    '÷',
                    bg: const Color(0xFF2E3440),
                    onTap: () => _insertChar('/'),
                  ),
                ]),
                const SizedBox(height: 4),
                _numRow([
                  _numKey('1', onTap: () => _insertChar('1')),
                  _numKey('2', onTap: () => _insertChar('2')),
                  _numKey('3', onTap: () => _insertChar('3')),
                  _numKey(
                    '+',
                    bg: const Color(0xFF2E3440),
                    onTap: () => _insertChar('+'),
                  ),
                  _numKey(
                    '−',
                    bg: const Color(0xFF2E3440),
                    onTap: () => _insertChar('-'),
                  ),
                ]),
                const SizedBox(height: 4),
                _numRow([
                  _numKey('0', onTap: () => _insertChar('0')),
                  _numKey('.', onTap: () => _insertChar('.')),
                  _numKey(
                    '×10ˣ',
                    fontSize: 13.5,
                    onTap: () => _insertDocMutation(_doc.insertPow10),
                  ),
                  _numKey(
                    'S⇔D',
                    bg: const Color(0xFF2E3440),
                    fg: const Color(0xFF60A5FA),
                    fontSize: 13.5,
                    onTap: _toggleFormat,
                  ),
                  _numKey(
                    'EXE',
                    bg: const Color(0xFF2563EB),
                    fg: Colors.white,
                    fontSize: 14.5,
                    onTap: _pressExe,
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularDPad() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF232733),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withAlpha(32)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: InkWell(
                onTap: () => _pressNav('up'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: Text(
                    '▲',
                    style: TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: InkWell(
                onTap: () => _pressNav('down'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: Text(
                    '▼',
                    style: TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 2,
            top: 0,
            bottom: 0,
            child: Center(
              child: InkWell(
                onTap: () => _pressNav('left'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    '◀',
                    style: TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 0,
            bottom: 0,
            child: Center(
              child: InkWell(
                onTap: () => _pressNav('right'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    '▶',
                    style: TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: InkWell(
              onTap: _pressOk,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 34,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A4152),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withAlpha(50)),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _casioTopPill({
    required String legend,
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
    double labelFontSize = 11.0,
    bool highlight = false,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            legend,
            maxLines: 1,
            style: TextStyle(
              color: highlight ? Colors.amberAccent : _shiftLegend,
              fontSize: 9.0,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 1.5),
        Expanded(
          child: SizedBox(
            width: double.infinity,
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: highlight
                          ? Colors.amberAccent
                          : Colors.white.withAlpha(24),
                      width: highlight ? 1.2 : 0.8,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sciKey({
    String? legend,
    required String label,
    required VoidCallback onTap,
    Color fg = Colors.white,
    bool italic = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                legend ?? '',
                maxLines: 1,
                style: const TextStyle(
                  color: _shiftLegend,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 1.5),
            Expanded(
              child: Material(
                color: const Color(0xFF2D323E),
                borderRadius: BorderRadius.circular(7),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(7),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            color: fg,
                            fontFamily: italic ? 'serif' : null,
                            fontStyle:
                                italic ? FontStyle.italic : FontStyle.normal,
                            fontSize: italic ? 15.5 : 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numRow(List<Widget> children) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _numKey(
    String label, {
    String? legend,
    Color bg = const Color(0xFF3F4554),
    Color fg = Colors.white,
    double fontSize = 18.5,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: legend != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              legend,
                              style: const TextStyle(
                                color: _shiftLegend,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                height: 0.95,
                              ),
                            ),
                            Text(
                              label,
                              style: TextStyle(
                                color: fg,
                                fontSize: fontSize,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          label,
                          style: TextStyle(
                            color: fg,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadicalPainter extends CustomPainter {
  final Color color;

  const _RadicalPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(0.8, size.height * 0.56)
      ..lineTo(size.width * 0.28, size.height * 0.50)
      ..lineTo(size.width * 0.50, size.height * 0.92)
      ..lineTo(size.width, 0.6);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RadicalPainter oldDelegate) =>
      oldDelegate.color != color;
}
