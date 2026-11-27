import 'dart:math' as math;

enum CasioAngleUnit { deg, rad }

enum CasioResultFormat { dec, frac, sci }

enum MathNodeType {
  textChar,
  frac,
  sqrt,
  cbrt,
  pow,
  pow10,
  fn,
}

class MathRow {
  final String id;
  final List<MathNode> items = [];
  final String? parentNodeId;
  final String? slotName;

  MathRow({
    required this.id,
    this.parentNodeId,
    this.slotName,
  });
}

class MathNode {
  final String id;
  final MathNodeType type;
  final String text;
  final String evalText;
  final MathRow? num;
  final MathRow? den;
  final MathRow? body;
  final MathRow? exp;
  final String fnName;

  const MathNode({
    required this.id,
    required this.type,
    this.text = '',
    this.evalText = '',
    this.num,
    this.den,
    this.body,
    this.exp,
    this.fnName = '',
  });
}

class MathCursor {
  final String rowId;
  final int index;

  const MathCursor({
    required this.rowId,
    required this.index,
  });
}

/// Editable Natural Textbook Display (MathIO) tree with 4-way navigation & direct tap cursoring.
class MathDocument {
  int _uid = 1;
  final Map<String, MathRow> _rowsById = {};
  final Map<String, MathNode> _nodesById = {};

  late final MathRow rootRow;
  late MathCursor cursor;

  MathDocument() {
    rootRow = _createRow();
    cursor = MathCursor(rowId: rootRow.id, index: 0);
  }

  MathRow? rowById(String id) => _rowsById[id];

  MathRow _createRow({String? parentNodeId, String? slotName}) {
    final id = 'r${_uid++}';
    final row = MathRow(
      id: id,
      parentNodeId: parentNodeId,
      slotName: slotName,
    );
    _rowsById[id] = row;
    return row;
  }

  MathNode makeChar(String text, {String? evalText}) {
    final id = 'n${_uid++}';
    final node = MathNode(
      id: id,
      type: MathNodeType.textChar,
      text: text,
      evalText: evalText ?? text,
    );
    _nodesById[id] = node;
    return node;
  }

  MathNode makeFrac({List<MathNode>? numItems, List<MathNode>? denItems}) {
    final id = 'n${_uid++}';
    final num = _createRow(parentNodeId: id, slotName: 'num');
    final den = _createRow(parentNodeId: id, slotName: 'den');
    if (numItems != null) num.items.addAll(numItems);
    if (denItems != null) den.items.addAll(denItems);
    final node = MathNode(
      id: id,
      type: MathNodeType.frac,
      num: num,
      den: den,
    );
    _nodesById[id] = node;
    return node;
  }

  MathNode makeSqrt({List<MathNode>? bodyItems, bool isCbrt = false}) {
    final id = 'n${_uid++}';
    final body = _createRow(parentNodeId: id, slotName: 'body');
    if (bodyItems != null) body.items.addAll(bodyItems);
    final node = MathNode(
      id: id,
      type: isCbrt ? MathNodeType.cbrt : MathNodeType.sqrt,
      body: body,
    );
    _nodesById[id] = node;
    return node;
  }

  MathNode makePow({List<MathNode>? expItems}) {
    final id = 'n${_uid++}';
    final exp = _createRow(parentNodeId: id, slotName: 'exp');
    if (expItems != null) exp.items.addAll(expItems);
    final node = MathNode(
      id: id,
      type: MathNodeType.pow,
      exp: exp,
    );
    _nodesById[id] = node;
    return node;
  }

  MathNode makePow10({List<MathNode>? expItems}) {
    final id = 'n${_uid++}';
    final exp = _createRow(parentNodeId: id, slotName: 'exp');
    if (expItems != null) exp.items.addAll(expItems);
    final node = MathNode(
      id: id,
      type: MathNodeType.pow10,
      exp: exp,
    );
    _nodesById[id] = node;
    return node;
  }

  MathNode makeFn(String fnName, {List<MathNode>? bodyItems}) {
    final id = 'n${_uid++}';
    final body = _createRow(parentNodeId: id, slotName: 'body');
    if (bodyItems != null) body.items.addAll(bodyItems);
    final node = MathNode(
      id: id,
      type: MathNodeType.fn,
      fnName: fnName,
      body: body,
    );
    _nodesById[id] = node;
    return node;
  }

  void setCursor(String rowId, int index) {
    final row = _rowsById[rowId];
    if (row == null) return;
    cursor = MathCursor(
      rowId: rowId,
      index: index.clamp(0, row.items.length),
    );
  }

  ({MathRow row, int idx})? _findRowContainingNode(String nodeId) {
    for (final row in _rowsById.values) {
      final idx = row.items.indexWhere((n) => n.id == nodeId);
      if (idx != -1) return (row: row, idx: idx);
    }
    return null;
  }

  void _insertNodes(
    List<MathNode> nodes, {
    String? moveIntoRowId,
    int moveIndex = 0,
  }) {
    final row = _rowsById[cursor.rowId];
    if (row == null) return;
    row.items.insertAll(cursor.index, nodes);
    if (moveIntoRowId != null) {
      setCursor(moveIntoRowId, moveIndex);
    } else {
      setCursor(row.id, cursor.index + nodes.length);
    }
  }

  void insertChar(String text, {String? evalText}) {
    _insertNodes([makeChar(text, evalText: evalText)]);
  }

  /// Wraps contiguous preceding operand into numerator if present; otherwise creates blank fraction.
  void insertFraction() {
    final row = _rowsById[cursor.rowId];
    if (row == null) return;
    int start = cursor.index;
    while (start > 0) {
      final prev = row.items[start - 1];
      if (prev.type == MathNodeType.textChar &&
          const ['+', '−', '-', '×', '÷', '*', '/', '=', '(']
              .contains(prev.text)) {
        break;
      }
      start--;
    }
    final numItems = row.items.sublist(start, cursor.index);
    row.items.removeRange(start, cursor.index);
    final frac = makeFrac(numItems: numItems);
    row.items.insert(start, frac);
    if (numItems.isNotEmpty) {
      setCursor(frac.den!.id, 0);
    } else {
      setCursor(frac.num!.id, 0);
    }
  }

  void insertSqrt() {
    final sq = makeSqrt();
    _insertNodes([sq], moveIntoRowId: sq.body!.id, moveIndex: 0);
  }

  void insertCbrt() {
    final cb = makeSqrt(isCbrt: true);
    _insertNodes([cb], moveIntoRowId: cb.body!.id, moveIndex: 0);
  }

  void insertPowerWith(String value) {
    final chars = value
        .split('')
        .map((c) => makeChar(c == '-' ? '−' : c, evalText: c))
        .toList();
    final p = makePow(expItems: chars);
    _insertNodes([p]);
  }

  void insertPowerEmpty() {
    final p = makePow();
    _insertNodes([p], moveIntoRowId: p.exp!.id, moveIndex: 0);
  }

  void insertPow10() {
    final p = makePow10();
    _insertNodes([p], moveIntoRowId: p.exp!.id, moveIndex: 0);
  }

  void insertTenPow() {
    final p = makePow();
    _insertNodes(
      [makeChar('1'), makeChar('0'), p],
      moveIntoRowId: p.exp!.id,
      moveIndex: 0,
    );
  }

  void insertEExp() {
    final p = makePow();
    _insertNodes(
      [makeChar('e', evalText: 'e'), p],
      moveIntoRowId: p.exp!.id,
      moveIndex: 0,
    );
  }

  void insertFn(String fnName) {
    final fn = makeFn(fnName);
    _insertNodes([fn], moveIntoRowId: fn.body!.id, moveIndex: 0);
  }

  void moveLeft() {
    final row = _rowsById[cursor.rowId];
    if (row == null) return;
    if (cursor.index > 0) {
      final prev = row.items[cursor.index - 1];
      switch (prev.type) {
        case MathNodeType.frac:
          setCursor(prev.den!.id, prev.den!.items.length);
        case MathNodeType.pow:
        case MathNodeType.pow10:
          setCursor(prev.exp!.id, prev.exp!.items.length);
        case MathNodeType.sqrt:
        case MathNodeType.cbrt:
        case MathNodeType.fn:
          setCursor(prev.body!.id, prev.body!.items.length);
        case MathNodeType.textChar:
          setCursor(row.id, cursor.index - 1);
      }
      return;
    }
    if (row.parentNodeId != null) {
      final parentNode = _nodesById[row.parentNodeId!];
      if (parentNode != null &&
          parentNode.type == MathNodeType.frac &&
          row.slotName == 'den') {
        setCursor(parentNode.num!.id, parentNode.num!.items.length);
        return;
      }
      final loc = _findRowContainingNode(row.parentNodeId!);
      if (loc != null) {
        setCursor(loc.row.id, loc.idx);
      }
    }
  }

  void moveRight() {
    final row = _rowsById[cursor.rowId];
    if (row == null) return;
    if (cursor.index < row.items.length) {
      final next = row.items[cursor.index];
      switch (next.type) {
        case MathNodeType.frac:
          setCursor(next.num!.id, 0);
        case MathNodeType.pow:
        case MathNodeType.pow10:
          setCursor(next.exp!.id, 0);
        case MathNodeType.sqrt:
        case MathNodeType.cbrt:
        case MathNodeType.fn:
          setCursor(next.body!.id, 0);
        case MathNodeType.textChar:
          setCursor(row.id, cursor.index + 1);
      }
      return;
    }
    if (row.parentNodeId != null) {
      final parentNode = _nodesById[row.parentNodeId!];
      if (parentNode != null &&
          parentNode.type == MathNodeType.frac &&
          row.slotName == 'num') {
        setCursor(parentNode.den!.id, 0);
        return;
      }
      final loc = _findRowContainingNode(row.parentNodeId!);
      if (loc != null) {
        setCursor(loc.row.id, loc.idx + 1);
      }
    }
  }

  bool moveUp() {
    MathRow? walk = _rowsById[cursor.rowId];
    while (walk != null && walk.parentNodeId != null) {
      final pn = _nodesById[walk.parentNodeId!];
      if (pn != null &&
          pn.type == MathNodeType.frac &&
          walk.slotName == 'den') {
        setCursor(pn.num!.id, cursor.index);
        return true;
      }
      final loc = _findRowContainingNode(walk.parentNodeId!);
      walk = loc?.row;
    }
    return false;
  }

  bool moveDown() {
    MathRow? walk = _rowsById[cursor.rowId];
    while (walk != null && walk.parentNodeId != null) {
      final pn = _nodesById[walk.parentNodeId!];
      if (pn != null &&
          pn.type == MathNodeType.frac &&
          walk.slotName == 'num') {
        setCursor(pn.den!.id, cursor.index);
        return true;
      }
      if (pn != null &&
          (pn.type == MathNodeType.pow || pn.type == MathNodeType.pow10)) {
        final loc = _findRowContainingNode(pn.id);
        if (loc != null) {
          setCursor(loc.row.id, loc.idx + 1);
          return true;
        }
      }
      final loc = _findRowContainingNode(walk.parentNodeId!);
      walk = loc?.row;
    }
    return false;
  }

  void backspace() {
    final row = _rowsById[cursor.rowId];
    if (row == null) return;
    if (cursor.index > 0) {
      row.items.removeAt(cursor.index - 1);
      setCursor(row.id, cursor.index - 1);
      return;
    }
    if (row.parentNodeId != null) {
      final pn = _nodesById[row.parentNodeId!];
      final loc = _findRowContainingNode(row.parentNodeId!);
      if (pn != null && loc != null) {
        List<MathNode> keep = const [];
        if (pn.type == MathNodeType.frac) {
          keep = row.slotName == 'den' ? pn.num!.items : pn.den!.items;
        }
        loc.row.items.removeAt(loc.idx);
        loc.row.items.insertAll(loc.idx, keep);
        setCursor(loc.row.id, loc.idx + keep.length);
      }
    }
  }

  void clear() {
    rootRow.items.clear();
    setCursor(rootRow.id, 0);
  }

  bool get hasEquals => _rowHasEquals(rootRow);

  bool _rowHasEquals(MathRow row) {
    for (final n in row.items) {
      if (n.type == MathNodeType.textChar && n.text == '=') return true;
      if (n.type == MathNodeType.frac &&
          (_rowHasEquals(n.num!) || _rowHasEquals(n.den!))) {
        return true;
      }
      if ((n.type == MathNodeType.sqrt ||
              n.type == MathNodeType.cbrt ||
              n.type == MathNodeType.fn) &&
          _rowHasEquals(n.body!)) {
        return true;
      }
      if ((n.type == MathNodeType.pow || n.type == MathNodeType.pow10) &&
          _rowHasEquals(n.exp!)) {
        return true;
      }
    }
    return false;
  }

  String toEvalString() => _rowToEvalString(rootRow);

  String _rowToEvalString(MathRow row) {
    final buf = StringBuffer();
    for (final n in row.items) {
      switch (n.type) {
        case MathNodeType.textChar:
          buf.write(n.evalText);
        case MathNodeType.frac:
          buf.write(
              '((${_rowToEvalString(n.num!)})/(${_rowToEvalString(n.den!)}))');
        case MathNodeType.sqrt:
          buf.write('sqrt(${_rowToEvalString(n.body!)})');
        case MathNodeType.cbrt:
          buf.write('cbrt(${_rowToEvalString(n.body!)})');
        case MathNodeType.pow:
          buf.write('^(${_rowToEvalString(n.exp!)})');
        case MathNodeType.pow10:
          buf.write('*(10^(${_rowToEvalString(n.exp!)}))');
        case MathNodeType.fn:
          buf.write('${n.fnName}(${_rowToEvalString(n.body!)})');
      }
    }
    return buf.toString();
  }

  List<Map<String, dynamic>> cloneSnapshot() => _snapshotRow(rootRow);

  List<Map<String, dynamic>> _snapshotRow(MathRow row) {
    return row.items.map<Map<String, dynamic>>((n) {
      switch (n.type) {
        case MathNodeType.textChar:
          return {
            'type': 'char',
            'text': n.text,
            'evalText': n.evalText,
          };
        case MathNodeType.frac:
          return {
            'type': 'frac',
            'num': _snapshotRow(n.num!),
            'den': _snapshotRow(n.den!),
          };
        case MathNodeType.sqrt:
          return {
            'type': 'sqrt',
            'body': _snapshotRow(n.body!),
          };
        case MathNodeType.cbrt:
          return {
            'type': 'cbrt',
            'body': _snapshotRow(n.body!),
          };
        case MathNodeType.pow:
          return {
            'type': 'pow',
            'exp': _snapshotRow(n.exp!),
          };
        case MathNodeType.pow10:
          return {
            'type': 'pow10',
            'exp': _snapshotRow(n.exp!),
          };
        case MathNodeType.fn:
          return {
            'type': 'fn',
            'fnName': n.fnName,
            'body': _snapshotRow(n.body!),
          };
      }
    }).toList();
  }

  void restoreSnapshot(List<Map<String, dynamic>> snapshot) {
    rootRow.items.clear();
    _hydrateIntoRow(snapshot, rootRow);
    setCursor(rootRow.id, rootRow.items.length);
  }

  void _hydrateIntoRow(List<Map<String, dynamic>> snap, MathRow target) {
    for (final s in snap) {
      switch (s['type']) {
        case 'char':
          target.items.add(
            makeChar(s['text'] as String, evalText: s['evalText'] as String?),
          );
        case 'frac':
          final f = makeFrac();
          _hydrateIntoRow(
              (s['num'] as List).cast<Map<String, dynamic>>(), f.num!);
          _hydrateIntoRow(
              (s['den'] as List).cast<Map<String, dynamic>>(), f.den!);
          target.items.add(f);
        case 'sqrt':
        case 'cbrt':
          final r = makeSqrt(isCbrt: s['type'] == 'cbrt');
          _hydrateIntoRow(
              (s['body'] as List).cast<Map<String, dynamic>>(), r.body!);
          target.items.add(r);
        case 'pow':
          final p = makePow();
          _hydrateIntoRow(
              (s['exp'] as List).cast<Map<String, dynamic>>(), p.exp!);
          target.items.add(p);
        case 'pow10':
          final p = makePow10();
          _hydrateIntoRow(
              (s['exp'] as List).cast<Map<String, dynamic>>(), p.exp!);
          target.items.add(p);
        case 'fn':
          final fn = makeFn(s['fnName'] as String);
          _hydrateIntoRow(
              (s['body'] as List).cast<Map<String, dynamic>>(), fn.body!);
          target.items.add(fn);
      }
    }
  }
}

enum _TokType { num, fn, constant, variable, op }

class _Tok {
  final _TokType type;
  final String text;
  final double numVal;

  const _Tok.num(this.numVal)
      : type = _TokType.num,
        text = '';

  const _Tok(this.type, this.text) : numVal = 0;
}

class CasioMathEvaluator {
  static const _functions = {
    'sin',
    'cos',
    'tan',
    'asin',
    'acos',
    'atan',
    'log',
    'ln',
    'sqrt',
    'cbrt',
    'abs',
  };

  static double _factorial(double n) {
    if (!n.isFinite || n < 0 || (n - n.roundToDouble()).abs() > 1e-9 || n > 170) {
      return double.nan;
    }
    double res = 1;
    final k = n.round();
    for (int i = 2; i <= k; i++) {
      res *= i;
    }
    return res;
  }

  static List<_Tok> _tokenize(String raw) {
    final s = raw
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .replaceAll('π', 'pi')
        .replaceAll('Ans', 'ans')
        .trim();

    final tokens = <_Tok>[];
    int i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch.trim().isEmpty) {
        i++;
        continue;
      }
      if (_isDigitOrDot(ch)) {
        final buf = StringBuffer();
        while (i < s.length && _isDigitOrDot(s[i])) {
          buf.write(s[i++]);
        }
        if (i < s.length &&
            (s[i] == 'e' || s[i] == 'E') &&
            i + 1 < s.length &&
            _isSciNext(s[i + 1])) {
          buf.write(s[i++]);
          if (s[i] == '+' || s[i] == '-') buf.write(s[i++]);
          while (i < s.length && _isDigit(s[i])) {
            buf.write(s[i++]);
          }
        }
        final val = double.tryParse(buf.toString());
        if (val == null) throw const FormatException('Số không hợp lệ');
        tokens.add(_Tok.num(val));
        continue;
      }
      if (_isAlpha(ch)) {
        final buf = StringBuffer();
        while (i < s.length && (_isAlpha(s[i]) || _isDigit(s[i]))) {
          buf.write(s[i++]);
        }
        final low = buf.toString().toLowerCase();
        if (_functions.contains(low)) {
          tokens.add(_Tok(_TokType.fn, low));
        } else if (low == 'pi' || low == 'e' || low == 'ans') {
          tokens.add(_Tok(_TokType.constant, low));
        } else if (low == 'x') {
          tokens.add(const _Tok(_TokType.variable, 'x'));
        } else {
          for (int k = 0; k < low.length; k++) {
            final c = low[k];
            if (c == 'x') {
              tokens.add(const _Tok(_TokType.variable, 'x'));
            } else if (c == 'e') {
              tokens.add(const _Tok(_TokType.constant, 'e'));
            } else {
              throw FormatException('Không hỗ trợ: $low');
            }
          }
        }
        continue;
      }
      if ('+-*/^()!'.contains(ch)) {
        tokens.add(_Tok(_TokType.op, ch));
        i++;
        continue;
      }
      throw FormatException('Ký tự không hợp lệ: $ch');
    }

    // Insert implicit multiplication (2x, 2π, 3(4+1), (x)(y), etc.)
    final out = <_Tok>[];
    bool isEnd(_Tok t) =>
        t.type == _TokType.num ||
        t.type == _TokType.constant ||
        t.type == _TokType.variable ||
        (t.type == _TokType.op && (t.text == ')' || t.text == '!'));
    bool isStart(_Tok t) =>
        t.type == _TokType.num ||
        t.type == _TokType.constant ||
        t.type == _TokType.variable ||
        t.type == _TokType.fn ||
        (t.type == _TokType.op && t.text == '(');

    for (final cur in tokens) {
      if (out.isNotEmpty && isEnd(out.last) && isStart(cur)) {
        out.add(const _Tok(_TokType.op, '*'));
      }
      out.add(cur);
    }
    return out;
  }

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static bool _isDigitOrDot(String c) => _isDigit(c) || c == '.';

  static bool _isSciNext(String c) => _isDigit(c) || c == '+' || c == '-';

  static bool _isAlpha(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        code == 95;
  }

  static double Function(double x) compile(
    String raw, {
    CasioAngleUnit angleUnit = CasioAngleUnit.deg,
    double ansValue = 0,
  }) {
    final tokens = _tokenize(raw);
    return (double xVal) {
      if (tokens.isEmpty) return 0.0;
      int pos = 0;
      _Tok? peek() => pos < tokens.length ? tokens[pos] : null;
      _Tok next() => tokens[pos++];

      late double Function() parseExpr;
      late double Function() parseTerm;
      late double Function() parseUnary;
      late double Function() parsePower;
      late double Function() parsePostfix;
      late double Function() parsePrimary;

      parseExpr = () {
        double left = parseTerm();
        while (peek()?.type == _TokType.op &&
            (peek()!.text == '+' || peek()!.text == '-')) {
          final op = next().text;
          final right = parseTerm();
          left = op == '+' ? left + right : left - right;
        }
        return left;
      };

      parseTerm = () {
        double left = parseUnary();
        while (peek()?.type == _TokType.op &&
            (peek()!.text == '*' || peek()!.text == '/')) {
          final op = next().text;
          final right = parseUnary();
          left = op == '*' ? left * right : left / right;
        }
        return left;
      };

      parseUnary = () {
        if (peek()?.type == _TokType.op &&
            (peek()!.text == '+' || peek()!.text == '-')) {
          final op = next().text;
          final v = parseUnary();
          return op == '-' ? -v : v;
        }
        return parsePower();
      };

      parsePower = () {
        double base = parsePostfix();
        if (peek()?.type == _TokType.op && peek()!.text == '^') {
          next();
          final exp = parseUnary();
          base = math.pow(base, exp).toDouble();
        }
        return base;
      };

      parsePostfix = () {
        double v = parsePrimary();
        while (peek()?.type == _TokType.op && peek()!.text == '!') {
          next();
          v = _factorial(v);
        }
        return v;
      };

      parsePrimary = () {
        final t = peek();
        if (t == null) throw const FormatException('Thiếu toán hạng');
        if (t.type == _TokType.num) {
          next();
          return t.numVal;
        }
        if (t.type == _TokType.variable) {
          next();
          return xVal;
        }
        if (t.type == _TokType.constant) {
          next();
          if (t.text == 'pi') return math.pi;
          if (t.text == 'e') return math.e;
          return ansValue;
        }
        if (t.type == _TokType.fn) {
          final fn = next().text;
          double arg;
          if (peek()?.type == _TokType.op && peek()!.text == '(') {
            next();
            arg = parseExpr();
            if (peek()?.text != ')') throw const FormatException('Thiếu dấu )');
            next();
          } else {
            arg = parseUnary();
          }
          double toRad(double v) =>
              angleUnit == CasioAngleUnit.deg ? v * math.pi / 180.0 : v;
          double fromRad(double v) =>
              angleUnit == CasioAngleUnit.deg ? v * 180.0 / math.pi : v;
          switch (fn) {
            case 'sin':
              return math.sin(toRad(arg));
            case 'cos':
              return math.cos(toRad(arg));
            case 'tan':
              return math.tan(toRad(arg));
            case 'asin':
              return fromRad(math.asin(arg));
            case 'acos':
              return fromRad(math.acos(arg));
            case 'atan':
              return fromRad(math.atan(arg));
            case 'log':
              return arg <= 0 ? double.nan : math.log(arg) / math.ln10;
            case 'ln':
              return arg <= 0 ? double.nan : math.log(arg);
            case 'sqrt':
              return arg < 0 ? double.nan : math.sqrt(arg);
            case 'cbrt':
              if (arg < 0) return -math.pow(-arg, 1.0 / 3.0).toDouble();
              return math.pow(arg, 1.0 / 3.0).toDouble();
            case 'abs':
              return arg.abs();
          }
        }
        if (t.type == _TokType.op && t.text == '(') {
          next();
          final v = parseExpr();
          if (peek()?.text != ')') throw const FormatException('Thiếu dấu )');
          next();
          return v;
        }
        throw const FormatException('Cú pháp không hợp lệ');
      };

      final res = parseExpr();
      if (pos < tokens.length) throw const FormatException('Dư toán hạng');
      return res;
    };
  }

  static double evaluate(
    String raw, {
    double x = 0,
    CasioAngleUnit angleUnit = CasioAngleUnit.deg,
    double ansValue = 0,
  }) =>
      compile(raw, angleUnit: angleUnit, ansValue: ansValue)(x);
}

class ArbitrarySolveResult {
  final List<double> roots;
  final double residual;
  final String? errorMessage;

  const ArbitrarySolveResult({
    this.roots = const [],
    this.residual = 0,
    this.errorMessage,
  });

  bool get hasRoots => roots.isNotEmpty && errorMessage == null;
}

enum LinearSystemStatus { unique, noSolution, infiniteSolutions, invalidInput }

class LinearSystemResult {
  final LinearSystemStatus status;
  final List<double> values;

  const LinearSystemResult({
    required this.status,
    this.values = const [],
  });
}

class PolySolveResult {
  final List<double> realRoots;
  final double? complexReal;
  final double? complexImag;
  final String? errorMessage;

  const PolySolveResult({
    this.realRoots = const [],
    this.complexReal,
    this.complexImag,
    this.errorMessage,
  });
}

class CasioSolvers {
  static ArbitrarySolveResult solveArbitraryEquation(
    String rawEquation, {
    double initialGuess = 0,
    CasioAngleUnit angleUnit = CasioAngleUnit.deg,
    double ansValue = 0,
  }) {
    final trimmed = rawEquation.trim();
    if (trimmed.isEmpty) {
      return const ArbitrarySolveResult(errorMessage: 'Phương trình trống');
    }
    final parts = trimmed.split('=');
    if (parts.length > 2) {
      return const ArbitrarySolveResult(errorMessage: 'Dư dấu =');
    }

    late double Function(double) f;
    try {
      final lhs = CasioMathEvaluator.compile(
        parts[0],
        angleUnit: angleUnit,
        ansValue: ansValue,
      );
      final rhs = parts.length == 2
          ? CasioMathEvaluator.compile(
              parts[1],
              angleUnit: angleUnit,
              ansValue: ansValue,
            )
          : (double _) => 0.0;
      f = (double x) => lhs(x) - rhs(x);
      f(initialGuess);
    } catch (e) {
      return const ArbitrarySolveResult(errorMessage: 'Lỗi cú pháp PT');
    }

    double? newtonFrom(double start) {
      double x = start;
      for (int iter = 0; iter < 85; iter++) {
        final y = f(x);
        if (!y.isFinite) return null;
        if (y.abs() < 1e-12) return x;
        final h = math.max(1e-7, x.abs() * 1e-7);
        final dy = (f(x + h) - f(x - h)) / (2.0 * h);
        if (!dy.isFinite || dy.abs() < 1e-14) break;
        final step = y / dy;
        double alpha = 1.0;
        bool accepted = false;
        while (alpha >= 0.0625) {
          final nx = x - alpha * step;
          final ny = f(nx);
          if (ny.isFinite &&
              (ny.abs() < y.abs() * 1.05 || ny.abs() < 1e-10)) {
            x = nx;
            accepted = true;
            break;
          }
          alpha *= 0.5;
        }
        if (!accepted) break;
        if ((alpha * step).abs() < 1e-12 * math.max(1.0, x.abs())) {
          return x;
        }
      }
      final finalY = f(x);
      return (finalY.isFinite && finalY.abs() < 1e-5) ? x : null;
    }

    double? bisect(double a, double b) {
      double fa = f(a);
      double fb = f(b);
      if (!fa.isFinite || !fb.isFinite || fa * fb > 0) return null;
      double lo = a;
      double hi = b;
      for (int i = 0; i < 70; i++) {
        final mid = 0.5 * (lo + hi);
        final fm = f(mid);
        if (!fm.isFinite) return null;
        if (fm.abs() < 1e-12 || (hi - lo).abs() < 1e-12) return mid;
        if (fa * fm <= 0) {
          hi = mid;
        } else {
          lo = mid;
          fa = fm;
        }
      }
      return 0.5 * (lo + hi);
    }

    final roots = <double>[];
    void addRoot(double? candidate) {
      if (candidate == null || !candidate.isFinite) return;
      final residual = f(candidate);
      if (!residual.isFinite || residual.abs() > 1e-5) return;
      if (!roots.any((old) => (old - candidate).abs() < 1e-5)) {
        roots.add(candidate);
      }
    }

    addRoot(newtonFrom(initialGuess));

    final scanSet = <double>{
      initialGuess,
      -100,
      -50,
      -20,
      -10,
      -5,
      -2,
      -1,
      -0.5,
      -0.1,
      -0.01,
      -0.001,
      0,
      0.001,
      0.01,
      0.05,
      0.1,
      0.2,
      0.5,
      1,
      2,
      3,
      5,
      10,
      20,
      50,
      100,
    };
    for (double t = -12.0; t <= 12.0; t += 0.37) {
      scanSet.add(t);
    }
    final pts = scanSet.toList()..sort();
    for (int i = 0; i < pts.length - 1; i++) {
      try {
        final a = pts[i];
        final b = pts[i + 1];
        final fa = f(a);
        final fb = f(b);
        if (fa.isFinite && fa.abs() < 1e-10) addRoot(a);
        if (fa.isFinite && fb.isFinite && fa * fb < 0) {
          addRoot(bisect(a, b));
        }
      } catch (_) {}
    }

    if (roots.isEmpty) {
      return const ArbitrarySolveResult(errorMessage: 'Không tìm thấy nghiệm');
    }

    roots.sort((a, b) =>
        (a - initialGuess).abs().compareTo((b - initialGuess).abs()));
    return ArbitrarySolveResult(
      roots: roots,
      residual: f(roots.first).abs(),
    );
  }

  static LinearSystemResult solveLinearSystem(List<List<double>> augmented) {
    final n = augmented.length;
    if (n == 0) {
      return const LinearSystemResult(status: LinearSystemStatus.invalidInput);
    }
    final mat = [
      for (final row in augmented) List<double>.from(row),
    ];
    for (final row in mat) {
      if (row.length != n + 1 || row.any((v) => !v.isFinite)) {
        return const LinearSystemResult(
          status: LinearSystemStatus.invalidInput,
        );
      }
    }

    int rank = 0;
    for (int col = 0; col < n && rank < n; col++) {
      int pivot = rank;
      for (int r = rank + 1; r < n; r++) {
        if (mat[r][col].abs() > mat[pivot][col].abs()) pivot = r;
      }
      if (mat[pivot][col].abs() < 1e-11) continue;
      final tmp = mat[rank];
      mat[rank] = mat[pivot];
      mat[pivot] = tmp;

      final div = mat[rank][col];
      for (int c = col; c <= n; c++) {
        mat[rank][c] /= div;
      }
      for (int r = 0; r < n; r++) {
        if (r == rank) continue;
        final factor = mat[r][col];
        for (int c = col; c <= n; c++) {
          mat[r][c] -= factor * mat[rank][c];
        }
      }
      rank++;
    }

    for (int r = rank; r < n; r++) {
      if (mat[r][n].abs() > 1e-9) {
        return const LinearSystemResult(status: LinearSystemStatus.noSolution);
      }
    }
    if (rank < n) {
      return const LinearSystemResult(
        status: LinearSystemStatus.infiniteSolutions,
      );
    }
    return LinearSystemResult(
      status: LinearSystemStatus.unique,
      values: [for (int r = 0; r < n; r++) mat[r][n]],
    );
  }

  static PolySolveResult solveQuadratic(double a, double b, double c) {
    if (!a.isFinite || !b.isFinite || !c.isFinite) {
      return const PolySolveResult(errorMessage: 'Hệ số không hợp lệ');
    }
    if (a.abs() < 1e-12) {
      return const PolySolveResult(errorMessage: 'Hệ số a phải ≠ 0');
    }
    final delta = b * b - 4 * a * c;
    if (delta >= 0) {
      final sq = math.sqrt(delta);
      final x1 = (-b + sq) / (2 * a);
      final x2 = (-b - sq) / (2 * a);
      return PolySolveResult(
        realRoots: delta.abs() < 1e-11 ? [x1] : [x1, x2],
      );
    }
    return PolySolveResult(
      complexReal: -b / (2 * a),
      complexImag: math.sqrt(-delta) / (2 * a),
    );
  }

  static PolySolveResult solveCubic(double a, double b, double c, double d) {
    if (!a.isFinite || !b.isFinite || !c.isFinite || !d.isFinite) {
      return const PolySolveResult(errorMessage: 'Hệ số không hợp lệ');
    }
    if (a.abs() < 1e-12) {
      return const PolySolveResult(errorMessage: 'Hệ số a phải ≠ 0');
    }
    final aa = b / a;
    final bb = c / a;
    final cc = d / a;
    final q = (aa * aa - 3 * bb) / 9.0;
    final r = (2 * aa * aa * aa - 9 * aa * bb + 27 * cc) / 54.0;
    final disc = r * r - q * q * q;
    if (disc <= 0 && q > 0) {
      final cosArg = (r / math.sqrt(q * q * q)).clamp(-1.0, 1.0);
      final theta = math.acos(cosArg);
      final s = -2 * math.sqrt(q);
      return PolySolveResult(
        realRoots: [
          s * math.cos(theta / 3.0) - aa / 3.0,
          s * math.cos((theta + 2 * math.pi) / 3.0) - aa / 3.0,
          s * math.cos((theta - 2 * math.pi) / 3.0) - aa / 3.0,
        ],
      );
    }
    double cbrt(double v) =>
        v < 0 ? -math.pow(-v, 1.0 / 3.0).toDouble() : math.pow(v, 1.0 / 3.0).toDouble();
    final sqrtD = math.sqrt(math.max(0.0, disc));
    final s = cbrt(-r + sqrtD);
    final t = cbrt(-r - sqrtD);
    final r1 = s + t - aa / 3.0;
    final re = -(s + t) / 2.0 - aa / 3.0;
    final im = (math.sqrt(3) / 2.0) * (s - t).abs();
    return PolySolveResult(
      realRoots: [r1],
      complexReal: im < 1e-9 ? null : re,
      complexImag: im < 1e-9 ? null : im,
    );
  }
}

class CasioFormatter {
  static String formatDecimal(double value) {
    if (!value.isFinite) return 'Math Error';
    if (value.abs() < 1e-12) return '0';
    if (value.abs() >= 1e9 || (value.abs() > 0 && value.abs() < 1e-4)) {
      final parts = formatScientificParts(value);
      return '${parts.mantissa}×10^${parts.exponent}';
    }
    final fixed = double.parse(value.toStringAsFixed(9));
    if (fixed == fixed.roundToDouble() && fixed.abs() < 1e12) {
      return fixed.round().toString();
    }
    var str = fixed.toString();
    if (str.contains('.')) {
      str = str.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return str;
  }

  static ({int num, int den})? toFraction(double value) {
    if (!value.isFinite) return null;
    if ((value - value.roundToDouble()).abs() < 1e-10) {
      return (num: value.round(), den: 1);
    }
    final sign = value < 0 ? -1 : 1;
    final x = value.abs();
    int h1 = 1, h2 = 0, k1 = 0, k2 = 1;
    double b = x;
    for (int i = 0; i < 16; i++) {
      final a = b.floor();
      final h = a * h1 + h2;
      final k = a * k1 + k2;
      if (k > 10000) break;
      h2 = h1;
      h1 = h;
      k2 = k1;
      k1 = k;
      if ((x - h1 / k1).abs() < 1e-10) break;
      final rem = b - a;
      if (rem < 1e-12) break;
      b = 1.0 / rem;
    }
    if (k1 > 1 && (x - h1 / k1).abs() < 1e-7) {
      return (num: sign * h1, den: k1);
    }
    return null;
  }

  static ({String mantissa, int exponent}) formatScientificParts(double value) {
    if (!value.isFinite) return (mantissa: 'Err', exponent: 0);
    if (value.abs() < 1e-12) return (mantissa: '0', exponent: 0);
    final raw = value.toStringAsExponential(4); // 5 significant digits max
    final split = raw.split('e');
    var mantissa = split[0];
    if (mantissa.contains('.')) {
      mantissa = mantissa.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    final expInt = int.parse(split[1]);
    return (mantissa: mantissa, exponent: expInt);
  }
}
