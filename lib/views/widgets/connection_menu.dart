import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/connection.dart';
import '../../../providers/canvas_provider.dart';

/// 接続線タップ時に表示されるコンテキストメニュー。
///
/// 線種（lineType）と形状（lineShape）の切り替え、接続解除を提供する。
class ConnectionContextMenu extends ConsumerStatefulWidget {
  final Connection connection;
  final Offset anchor;

  const ConnectionContextMenu({
    super.key,
    required this.connection,
    required this.anchor,
  });

  @override
  ConsumerState<ConnectionContextMenu> createState() => _ConnectionContextMenuState();
}

class _ConnectionContextMenuState extends ConsumerState<ConnectionContextMenu> {
  late LineType _lineType;
  late LineShape _lineShape;
  late Color _color;

  @override
  void initState() {
    super.initState();
    _lineType = widget.connection.lineType;
    _lineShape = widget.connection.lineShape;
    _color = widget.connection.color;
  }

  void _update({LineType? lineType, LineShape? lineShape, Color? color}) {
    ref.read(canvasNotifierProvider.notifier).updateConnection(
      id: widget.connection.id,
      lineType: lineType,
      lineShape: lineShape,
      color: color,
    );
  }

  /// 接続線の色を選択するカラーピッカーダイアログを表示する。
  Future<void> _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('接続線の色を選択'),
        content: SizedBox(
          width: 320,
          child: ColorPicker(
            color: _color,
            onColorChanged: (color) {
              Navigator.of(dialogContext).pop(color);
            },
            pickersEnabled: const <ColorPickerType, bool>{
              ColorPickerType.primary: true,
              ColorPickerType.accent: true,
              ColorPickerType.bw: true,
              ColorPickerType.wheel: true,
            },
            enableShadesSelection: true,
            width: 32,
            height: 32,
            spacing: 4,
            runSpacing: 4,
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _color = picked);
      _update(color: picked);
    }
  }

  void _disconnect() {
    // 確認ダイアログを表示し、確認が取れたときのみ解除する。
    showDialog<void>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: const Text('接続線を解除しますか？'),
        content: const Text('この接続線を削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmContext).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              ref
                  .read(canvasNotifierProvider.notifier)
                  .deleteConnection(widget.connection.id);
              if (confirmContext.mounted) Navigator.of(confirmContext).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('接続線を解除しました')),
                );
                // 接続線が消えたため、コンテキストメニュー自体も閉じる。
                Navigator.of(context).pop();
              }
            },
            child: const Text('解除する'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          // オブジェクト編集ダイアログ（AlertDialog）と同様の背景色にする。
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '接続線',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _SectionTitle(text: '線種'),
              _OptionRow<LineType>(
                options: LineType.values,
                selected: _lineType,
                label: (t) => t.displayName,
                onSelect: (value) {
                  _update(lineType: value);
                  if (mounted) setState(() => _lineType = value);
                },
              ),
              const SizedBox(height: 8),
              _SectionTitle(text: '形状'),
              _OptionRow<LineShape>(
                options: LineShape.values,
                selected: _lineShape,
                label: (s) => s.displayName,
                onSelect: (value) {
                  _update(lineShape: value);
                  if (mounted) setState(() => _lineShape = value);
                },
              ),
              const SizedBox(height: 8),
              _SectionTitle(text: '色'),
              InkWell(
                onTap: _pickColor,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '色を変更',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Icon(Icons.palette_outlined,
                          size: 16, color: Colors.grey.shade500),
                    ],
                  ),
                ),
              ),
              const Divider(height: 16),
              InkWell(
                onTap: _disconnect,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: const [
                      Icon(Icons.link_off, size: 18),
                      SizedBox(width: 8),
                      Text('接続線を解除'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _OptionRow<T extends Enum> extends StatelessWidget {
  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelect;

  /// オプションの表示ラベルを返す関数（日本語名など）。
  final String Function(T option) label;

  const _OptionRow({
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((option) {
        final isSelected = option == selected;
        return InkWell(
          onTap: () => onSelect(option),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label(option),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
