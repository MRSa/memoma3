import 'package:flutter/material.dart';

import 'object_list_ui.dart';

/// ソート可能なカラムヘッダ（ラベル + ソートアイコン）。
///
/// [sortCol] が null の場合はソート不可（アイコンなし）。
/// 現在ソートに使用しているカラムはアイコンを主色で強調する。
class SortHeader extends StatelessWidget {
  final String label;
  final SortColumn? sortCol;
  final bool isSorted;
  final IconData icon;
  final VoidCallback? onTap;

  const SortHeader({
    super.key,
    required this.label,
    this.sortCol,
    required this.isSorted,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kCellGap / 2),
        child: Row(
          // 固定幅の親に収まり、ラベルがはみ出た場合は省略記号で切る。
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            if (sortCol != null) ...[
              const SizedBox(width: 4),
              Icon(
                icon,
                size: 14,
                color: isSorted ? theme.colorScheme.primary : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
