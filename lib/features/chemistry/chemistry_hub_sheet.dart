import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/formulas_data.dart';
import 'widgets/equation_balancer.dart';
import 'widgets/formulas_reference_sheet.dart';
import 'widgets/molar_mass_calculator.dart';
import 'widgets/periodic_table_sheet.dart';
import 'widgets/stencil_picker_sheet.dart';

/// Trung tâm Bộ công cụ Hóa học hợp nhất cho ChemNote.
///
/// Bao gồm dải **Ký hiệu Hóa học nhanh** thu gọn được ở phía trên
/// và 5 thẻ chức năng:
/// 0. Bảng tuần hoàn (118 nguyên tố)
/// 1. Tính M (Khối lượng mol phân tử)
/// 2. Công thức Hóa (& Hằng số hóa lý)
/// 3. Khuôn & Sticker (21 khuôn vector hóa học & dụng cụ thí nghiệm)
/// 4. Cân bằng PT (Cân bằng phương trình hóa học chính xác)
class ChemistryHubSheet extends StatefulWidget {
  final ValueChanged<String> onInsertStencil;
  final ValueChanged<String> onInsertText;

  /// Callback tùy chọn khi người dùng chạm vào ký hiệu hóa học nhanh.
  /// Nếu bỏ trống, mặc định sẽ gọi [onInsertText].
  final ValueChanged<String>? onInsertSymbol;
  final int initialTabIndex;

  const ChemistryHubSheet({
    super.key,
    required this.onInsertStencil,
    required this.onInsertText,
    this.onInsertSymbol,
    this.initialTabIndex = 0,
  });

  /// Mở [ChemistryHubSheet] dưới dạng Modal Bottom Sheet thích ứng cả điện thoại & tablet.
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onInsertStencil,
    required ValueChanged<String> onInsertText,
    ValueChanged<String>? onInsertSymbol,
    int initialTabIndex = 0,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: isDark ? const Color(0xFF16181D) : null,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: ChemistryHubSheet(
            initialTabIndex: initialTabIndex,
            onInsertStencil: (stencilId) {
              Navigator.of(sheetContext).pop();
              onInsertStencil(stencilId);
            },
            onInsertText: (text) {
              Navigator.of(sheetContext).pop();
              onInsertText(text);
            },
            onInsertSymbol: (symbol) {
              if (onInsertSymbol != null) {
                onInsertSymbol(symbol);
              } else {
                Navigator.of(sheetContext).pop();
                onInsertText(symbol);
              }
            },
          ),
        );
      },
    );
  }

  @override
  State<ChemistryHubSheet> createState() => _ChemistryHubSheetState();
}

class _ChemistryHubSheetState extends State<ChemistryHubSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _symbolsExpanded = true;

  @override
  void initState() {
    super.initState();
    final clampedIndex = widget.initialTabIndex.clamp(0, 4);
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: clampedIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleSymbolTap(String symbol) {
    final handler = widget.onInsertSymbol ?? widget.onInsertText;
    handler(symbol);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final sheetBg = isDark ? const Color(0xFF16181D) : colors.surface;
    final pillBg = isDark ? const Color(0xFF22252E) : colors.surfaceContainerHigh;
    const accentBlue = Color(0xFF3B82F6);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : colors.outlineVariant;

    return ColoredBox(
      color: sheetBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  color: isDark ? accentBlue : colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Công cụ Hóa học',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _symbolsExpanded = !_symbolsExpanded),
                  icon: Icon(
                    _symbolsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                  ),
                  label: const Text('Ký hiệu nhanh'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Đóng',
                ),
              ],
            ),
          ),

          // Dải Ký hiệu Hóa học nhanh (thu gọn được)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _symbolsExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Container(
              margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kChemSymbols.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final sym = kChemSymbols[index];
                    return Material(
                      color: isDark
                          ? const Color(0xFF16181D)
                          : colors.surface,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => _handleSymbolTap(sym),
                        onLongPress: () {
                          Clipboard.setData(ClipboardData(text: sym));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Đã sao chép ký hiệu "$sym"'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 34),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: Text(
                            sym,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),

          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: isDark ? accentBlue : colors.primary,
            labelColor: isDark ? accentBlue : colors.primary,
            tabs: const [
              Tab(icon: Icon(Icons.grid_on, size: 18), text: 'Bảng tuần hoàn'),
              Tab(icon: Icon(Icons.calculate_outlined, size: 18), text: 'Tính M'),
              Tab(icon: Icon(Icons.menu_book_outlined, size: 18), text: 'Công thức Hóa'),
              Tab(icon: Icon(Icons.hexagon_outlined, size: 18), text: 'Khuôn & Sticker'),
              Tab(icon: Icon(Icons.balance_outlined, size: 18), text: 'Cân bằng PT'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                PeriodicTableSheet(onInsertText: widget.onInsertText),
                MolarMassCalculatorWidget(onInsertText: widget.onInsertText),
                FormulasReferenceSheet(onInsertText: widget.onInsertText),
                StencilPickerSheet(onSelectStencil: widget.onInsertStencil),
                EquationBalancerWidget(onInsertText: widget.onInsertText),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
