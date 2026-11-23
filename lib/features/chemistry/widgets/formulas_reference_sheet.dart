import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/formulas_data.dart';

/// Sổ tay Công thức & Hằng số Hóa học có tìm kiếm, lọc chuyên đề và ghim yêu thích.
class FormulasReferenceSheet extends StatefulWidget {
  final ValueChanged<String>? onInsertText;

  const FormulasReferenceSheet({
    super.key,
    this.onInsertText,
  });

  @override
  State<FormulasReferenceSheet> createState() => _FormulasReferenceSheetState();
}

class _FormulasReferenceSheetState extends State<FormulasReferenceSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _selectedCategory = kFormulaCategories.first;
  bool _onlyPinned = false;
  bool _showConstants = false;
  final Set<String> _pinnedIds = {'gen_mol', 'gas_ideal', 'thermo_gibbs', 'elec_nernst'};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChemFormula> get _filteredFormulas {
    final q = _query.toLowerCase();
    return kChemFormulas.where((f) {
      if (_onlyPinned && !_pinnedIds.contains(f.id)) return false;
      if (_selectedCategory != 'Tất cả' && f.category != _selectedCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      return f.title.toLowerCase().contains(q) ||
          f.expression.toLowerCase().contains(q) ||
          f.category.toLowerCase().contains(q) ||
          f.notes.toLowerCase().contains(q) ||
          f.variables.any(
            (v) =>
                v.symbol.toLowerCase().contains(q) ||
                v.meaningVi.toLowerCase().contains(q),
          );
    }).toList();
  }

  void _togglePin(String id) {
    setState(() {
      if (_pinnedIds.contains(id)) {
        _pinnedIds.remove(id);
      } else {
        _pinnedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final formulas = _filteredFormulas;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Tìm công thức, định luật, đại lượng...',
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
              const SizedBox(width: 8),
              FilterChip(
                avatar: Icon(
                  _showConstants ? Icons.functions : Icons.straighten,
                  size: 16,
                ),
                label: const Text('Hằng số'),
                selected: _showConstants,
                onSelected: (v) => setState(() => _showConstants = v),
              ),
            ],
          ),
        ),

        if (!_showConstants)
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: Icon(
                      _onlyPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 16,
                    ),
                    label: Text('Đã ghim (${_pinnedIds.length})'),
                    selected: _onlyPinned,
                    onSelected: (v) => setState(() => _onlyPinned = v),
                  ),
                ),
                ...kFormulaCategories.map((cat) {
                  final selected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                    ),
                  );
                }),
              ],
            ),
          ),

        Expanded(
          child: _showConstants
              ? _buildConstantsList(theme, colors)
              : formulas.isEmpty
                  ? Center(
                      child: Text(
                        'Không tìm thấy công thức phù hợp.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: formulas.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final f = formulas[index];
                        return _FormulaCard(
                          formula: f,
                          isPinned: _pinnedIds.contains(f.id),
                          onTogglePin: () => _togglePin(f.id),
                          onInsert: widget.onInsertText != null
                              ? () => widget.onInsertText!(f.formattedInsertText)
                              : null,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildConstantsList(ThemeData theme, ColorScheme colors) {
    final q = _query.toLowerCase();
    final items = q.isEmpty
        ? kChemConstants
        : kChemConstants
            .where(
              (c) =>
                  c.symbol.toLowerCase().contains(q) ||
                  c.nameVi.toLowerCase().contains(q) ||
                  c.unit.toLowerCase().contains(q),
            )
            .toList();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final c = items[index];
        final insertText = '${c.symbol} = ${c.value} ${c.unit} (${c.nameVi})';
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: colors.primaryContainer,
              child: Text(
                c.symbol,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colors.onPrimaryContainer,
                  fontSize: 13,
                ),
              ),
            ),
            title: Text(
              c.nameVi,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${c.value} ${c.unit}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Sao chép',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: insertText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã sao chép ${c.nameVi}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                if (widget.onInsertText != null)
                  IconButton(
                    tooltip: 'Chèn vào ghi chú',
                    icon: const Icon(Icons.add_comment_outlined, size: 20),
                    onPressed: () => widget.onInsertText!(insertText),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FormulaCard extends StatelessWidget {
  final ChemFormula formula;
  final bool isPinned;
  final VoidCallback onTogglePin;
  final VoidCallback? onInsert;

  const _FormulaCard({
    required this.formula,
    required this.isPinned,
    required this.onTogglePin,
    this.onInsert,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formula.category,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formula.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onTogglePin,
                  tooltip: isPinned ? 'Bỏ ghim' : 'Ghim công thức',
                  icon: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 20,
                    color: isPinned ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withOpacity(0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                formula.expression,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...formula.variables.map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 66,
                      child: Text(
                        v.symbol,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${v.meaningVi} (${v.unit})',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (formula.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Lưu ý: ${formula.notes}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: formula.formattedInsertText),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã sao chép công thức'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Sao chép'),
                ),
                const SizedBox(width: 6),
                if (onInsert != null)
                  FilledButton.tonalIcon(
                    onPressed: onInsert,
                    icon: const Icon(Icons.add_comment_outlined, size: 16),
                    label: const Text('Chèn vào ghi chú'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
