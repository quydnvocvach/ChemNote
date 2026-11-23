import 'package:flutter/material.dart';
import '../data/stencils_data.dart';
import 'stencil_painter.dart';

/// Lưới chọn khuôn vẽ & sticker hóa học có xem trước vector trực tiếp.
class StencilPickerSheet extends StatefulWidget {
  final ValueChanged<String> onSelectStencil;
  final Color? previewColor;

  const StencilPickerSheet({
    super.key,
    required this.onSelectStencil,
    this.previewColor,
  });

  @override
  State<StencilPickerSheet> createState() => _StencilPickerSheetState();
}

class _StencilPickerSheetState extends State<StencilPickerSheet> {
  String _selectedCategory = kStencilCategories.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strokeColor = widget.previewColor ?? colors.onSurface;

    final filtered = _selectedCategory == 'Tất cả'
        ? kChemStencils
        : kChemStencils
            .where((s) => s.category == _selectedCategory)
            .toList();

    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: kStencilCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = kStencilCategories[index];
              final selected = cat == _selectedCategory;
              return ChoiceChip(
                label: Text(cat),
                selected: selected,
                onSelected: (_) => setState(() => _selectedCategory = cat),
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final stencil = filtered[index];
              return _StencilTile(
                stencil: stencil,
                strokeColor: strokeColor,
                onTap: () => widget.onSelectStencil(stencil.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StencilTile extends StatelessWidget {
  final ChemStencilDef stencil;
  final Color strokeColor;
  final VoidCallback onTap;

  const _StencilTile({
    required this.stencil,
    required this.strokeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: stencil.defaultAspectRatio.clamp(0.45, 2.2),
                    child: CustomPaint(
                      painter: StencilPainter(
                        stencilId: stencil.id,
                        color: strokeColor,
                        strokeWidth: 2.0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                stencil.nameVi,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
