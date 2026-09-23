import 'package:flutter/material.dart';

/// 複数選択可能なドロップダウン（チェックボックス付き）。
///
/// - タップでメニューが開き、各オプションのチェックボックスで選択をトグルする。
/// - 選択中が 0 個なら「すべて」、1 個ならその名称、2 個以上なら「N 件選択」を表示。
class MultiSelectDropdown<T> extends StatelessWidget {
  final String label;
  final List<T> options;
  final Set<T> selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onToggle;

  const MultiSelectDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
  });

  String _summary() {
    if (selected.isEmpty) return '$label: すべて';
    if (selected.length == 1) {
      final first = selected.first;
      return labelOf(first);
    }
    return '$label: ${selected.length} 件選択';
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final option in options)
          InkWell(
            onTap: () => onToggle(option),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: selected.contains(option),
                    onChanged: (_) => onToggle(option),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(labelOf(option), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
      ],
      builder: (context, menuController, child) {
        return InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
          child: InkWell(
            onTap: menuController.open,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    _summary(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
