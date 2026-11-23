import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/elements_data.dart';

/// Bảng tuần hoàn 18 cột tương tác đầy đủ 118 nguyên tố cho ChemNote.
class PeriodicTableSheet extends StatefulWidget {
  final ValueChanged<String>? onInsertText;

  const PeriodicTableSheet({
    super.key,
    this.onInsertText,
  });

  @override
  State<PeriodicTableSheet> createState() => _PeriodicTableSheetState();
}

class _PeriodicTableSheetState extends State<PeriodicTableSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  ElementCategory? _selectedCategory;
  ChemicalElement? _selectedElement;

  late final Map<String, ChemicalElement> _gridLookup;
  late final List<ChemicalElement> _lanthanides;
  late final List<ChemicalElement> _actinides;

  @override
  void initState() {
    super.initState();
    _gridLookup = {};
    _lanthanides = [];
    _actinides = [];

    for (final el in kChemicalElements) {
      if (el.atomicNumber >= 57 && el.atomicNumber <= 71) {
        _lanthanides.add(el);
      } else if (el.atomicNumber >= 89 && el.atomicNumber <= 103) {
        _actinides.add(el);
      } else {
        _gridLookup['${el.period}_${el.group}'] = el;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesQuery(ChemicalElement el) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return el.symbol.toLowerCase().contains(q) ||
        el.nameVi.toLowerCase().contains(q) ||
        el.nameEn.toLowerCase().contains(q) ||
        el.atomicNumber.toString() == q;
  }

  bool _isHighlighted(ChemicalElement el) {
    if (_selectedCategory != null && el.category != _selectedCategory) {
      return false;
    }
    if (_query.isNotEmpty && !_matchesQuery(el)) {
      return false;
    }
    return true;
  }

  String _formatElementForInsert(ChemicalElement el) {
    final enStr = el.electronegativity != null
        ? ' | ĐÂĐ: ${el.electronegativity}'
        : '';
    return '${el.symbol} (${el.nameVi}, Z=${el.atomicNumber}, M=${el.atomicMass} g/mol, ${el.electronConfig}$enStr)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final searchMatches = _query.isEmpty
        ? const <ChemicalElement>[]
        : kChemicalElements.where(_matchesQuery).take(12).toList();

    return Column(
      children: [
        // Thanh tìm kiếm
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Tìm ký hiệu, tên (VN/EN) hoặc số hiệu Z...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        // Kết quả tìm kiếm nhanh dạng chip
        if (searchMatches.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: searchMatches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final el = searchMatches[index];
                return ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: el.category.color,
                    child: Text(
                      el.symbol,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  label: Text('${el.atomicNumber} · ${el.nameVi}'),
                  onPressed: () => setState(() => _selectedElement = el),
                );
              },
            ),
          ),

        // Thanh lọc nhóm nguyên tố (chú giải màu)
        SizedBox(
          height: 44,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: const Text('Tất cả'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
              ),
              ...ElementCategory.values.map((cat) {
                final selected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: CircleAvatar(
                      backgroundColor: cat.color,
                      radius: 6,
                    ),
                    label: Text(cat.labelVi),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _selectedCategory = selected ? null : cat;
                      });
                    },
                  ),
                );
              }),
            ],
          ),
        ),

        // Lưới bảng tuần hoàn 18 cột cuộn ngang + dọc
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header nhóm 1..18
                  Row(
                    children: [
                      const SizedBox(width: 24),
                      for (int g = 1; g <= 18; g++)
                        SizedBox(
                          width: 56,
                          child: Center(
                            child: Text(
                              '$g',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // 7 chu kỳ chính
                  for (int p = 1; p <= 7; p++)
                    Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '$p',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (int g = 1; g <= 18; g++) _buildMainCell(p, g),
                      ],
                    ),

                  const SizedBox(height: 12),

                  // Hàng Họ Lantan (57–71)
                  Row(
                    children: [
                      const SizedBox(width: 24 + 56 * 2),
                      for (final el in _lanthanides) _buildElementCell(el),
                    ],
                  ),

                  // Hàng Họ Actini (89–103)
                  Row(
                    children: [
                      const SizedBox(width: 24 + 56 * 2),
                      for (final el in _actinides) _buildElementCell(el),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Thẻ chi tiết nguyên tố đang chọn
        if (_selectedElement != null)
          _ElementDetailCard(
            element: _selectedElement!,
            onClose: () => setState(() => _selectedElement = null),
            onCopy: () {
              Clipboard.setData(
                ClipboardData(text: _formatElementForInsert(_selectedElement!)),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Đã sao chép ${_selectedElement!.nameVi}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            onInsert: widget.onInsertText != null
                ? () => widget.onInsertText!(
                      _formatElementForInsert(_selectedElement!),
                    )
                : null,
          ),
      ],
    );
  }

  Widget _buildMainCell(int period, int group) {
    if (period == 6 && group == 3) {
      return _buildSeriesPlaceholder('57–71', 'La–Lu', ElementCategory.lanthanide);
    }
    if (period == 7 && group == 3) {
      return _buildSeriesPlaceholder('89–103', 'Ac–Lr', ElementCategory.actinide);
    }
    final el = _gridLookup['${period}_$group'];
    if (el == null) {
      return const SizedBox(width: 56, height: 60);
    }
    return _buildElementCell(el);
  }

  Widget _buildSeriesPlaceholder(
    String range,
    String label,
    ElementCategory category,
  ) {
    return Container(
      width: 52,
      height: 56,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: category.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: category.color.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            range,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildElementCell(ChemicalElement el) {
    final highlighted = _isHighlighted(el);
    final isSelected = _selectedElement?.atomicNumber == el.atomicNumber;
    final catColor = el.category.color;

    return GestureDetector(
      onTap: () => setState(() => _selectedElement = el),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: highlighted ? 1.0 : 0.22,
        child: Container(
          width: 52,
          height: 56,
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? catColor.withOpacity(0.35)
                : catColor.withOpacity(0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? catColor : catColor.withOpacity(0.55),
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${el.atomicNumber}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    el.symbol,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  el.atomicMass.toStringAsFixed(el.atomicMass >= 100 ? 1 : 2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ElementDetailCard extends StatelessWidget {
  final ChemicalElement element;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback? onInsert;

  const _ElementDetailCard({
    required this.element,
    required this.onClose,
    required this.onCopy,
    this.onInsert,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final catColor = element.category.color;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: catColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: catColor, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${element.atomicNumber}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      element.symbol,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${element.nameVi} (${element.nameEn})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${element.category.labelVi} · Chu kỳ ${element.period}, Nhóm ${element.group} · ${element.phaseAtStp}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Đóng',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _PropChip(
                label: 'Nguyên tử khối',
                value: '${element.atomicMass} g/mol',
              ),
              _PropChip(
                label: 'Cấu hình e',
                value: element.electronConfig,
              ),
              _PropChip(
                label: 'Độ âm điện',
                value: element.electronegativity?.toStringAsFixed(2) ?? '—',
              ),
              _PropChip(
                label: 'Số oxi hóa',
                value: element.oxidationStates,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Sao chép'),
              ),
              const SizedBox(width: 10),
              if (onInsert != null)
                FilledButton.icon(
                  onPressed: onInsert,
                  icon: const Icon(Icons.add_comment_outlined, size: 16),
                  label: const Text('Chèn vào ghi chú'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PropChip extends StatelessWidget {
  final String label;
  final String value;

  const _PropChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
