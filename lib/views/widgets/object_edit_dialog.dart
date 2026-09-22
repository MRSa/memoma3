import 'package:flutter/material.dart';
import 'my_custom_color_picker.dart';

import '../../../models/note_object.dart';

/// 選択された色を適用する先。
///
/// 本体・ラベル・説明の3種類を明確に区別するため、
/// 真偽値ではなく列挙型で指定する。
enum ColorPickerTarget {
  /// オブジェクトの本体色。
  body,

  /// ラベルの文字色。
  label,

  /// 本文（説明）の文字色。
  description,
}

/// 選択中のオブジェクトの情報を編集するダイアログ。
///
/// 形状（shape）・ラベル（label）・詳細（detail）・色（color）・
/// ラベル色（labelColor）・説明色（descriptionColor）を変更でき、
/// 「保存」で [onSave] に結果を返す。
/// キャンセルした場合は [onCancel] を呼ぶ。
class ObjectEditDialog extends StatefulWidget {
  final NoteObject note;

  /// 保存時に呼び出される。変更内容は [changes] に格納される。
  final ValueChanged<NoteObject> onSave;

  /// キャンセル時に呼び出される。
  final VoidCallback onCancel;

  /// 形状が選択された時に呼び出される。次回新規作成時のデフォルト形状として使用される。
  final ValueChanged<NoteShape> onShapeSelected;

  const ObjectEditDialog({
    super.key,
    required this.note,
    required this.onSave,
    required this.onCancel,
    required this.onShapeSelected,
  });

  @override
  State<ObjectEditDialog> createState() => _ObjectEditDialogState();
}

class _ObjectEditDialogState extends State<ObjectEditDialog> {
  late TextEditingController _labelController;
  late TextEditingController _detailController;
  late TextEditingController _contentController;

  late NoteShape _shape;
  late Color _color;
  late Color? _labelColor;
  late Color? _descriptionColor;
  late Emphasis _emphasis;
  late double _scale;
  late int _labelFontSizeLevel;
  late int _descriptionFontSizeLevel;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.note.label);
    _detailController = TextEditingController(text: widget.note.detail);
    _contentController = TextEditingController(text: widget.note.content);
    _shape = widget.note.shape;
    _color = widget.note.color;
    _labelColor = widget.note.labelColor;
    _descriptionColor = widget.note.descriptionColor;
    _emphasis = widget.note.emphasis;
    _scale = widget.note.scale;
    _labelFontSizeLevel = widget.note.labelFontSizeLevel;
    _descriptionFontSizeLevel = widget.note.descriptionFontSizeLevel;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _detailController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(
      widget.note.copyWith(
        label: _labelController.text,
        detail: _detailController.text,
        content: _contentController.text,
        shape: _shape,
        color: _color,
        emphasis: _emphasis,
        labelColor: _labelColor,
        descriptionColor: _descriptionColor,
        scale: _scale,
        labelFontSizeLevel: _labelFontSizeLevel,
        descriptionFontSizeLevel: _descriptionFontSizeLevel,
      ),
    );
  }

  /// 色を選択するためのカラーピッカーダイアログを表示する。
  ///
  /// [title] でダイアログのタイトルを、[target] で適用先の色を指定する。
  Future<void> _pickColor({
    required String title,
    required Color initialColor,
    required ColorPickerTarget target,
  }) async {
    final picked = await MyCustomColorPicker.showAsDialog(
      context,
      initialColor: initialColor,
      title: title,
    );
    if (picked != null && mounted) {
      setState(() {
        switch (target) {
          case ColorPickerTarget.body:
            _color = picked;
          case ColorPickerTarget.label:
            _labelColor = picked;
          case ColorPickerTarget.description:
            _descriptionColor = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('オブジェクトを編集'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 上段：強調 / 色 / フォントサイズ（3カラム）
              // 下段：サイズ
              // 縦に伸ばさず、横幅を使って並べる。
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 上段：強調 / 色 / フォントサイズ
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左：強調
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('強調',
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: Emphasis.values.map((emphasis) {
                                final selected = emphasis == _emphasis;
                                return _ChipButton(
                                  label: emphasis.displayName,
                                  selected: selected,
                                  onTap: () =>
                                      setState(() => _emphasis = emphasis),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      // 中：色
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('色',
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                _ColorSwatch(
                                  label: '本体',
                                  color: _color,
                                  onTap: () => _pickColor(
                                    title: '本体の色を選択',
                                    initialColor: _color,
                                    target: ColorPickerTarget.body,
                                  ),
                                ),
                                _ColorSwatch(
                                  label: 'ラベル色',
                                  color: _labelColor ?? _color,
                                  onTap: () => _pickColor(
                                    title: 'ラベル色を選択',
                                    initialColor: _labelColor ?? _color,
                                    target: ColorPickerTarget.label,
                                  ),
                                ),
                                _ColorSwatch(
                                  label: '説明色',
                                  color: _descriptionColor ?? _color,
                                  onTap: () => _pickColor(
                                    title: '説明色を選択',
                                    initialColor: _descriptionColor ?? _color,
                                    target: ColorPickerTarget.description,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      // 右：フォントサイズ（ラベル・説明を横に並べる）
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('フォントサイズ',
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ラベル
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('ラベル',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                      const SizedBox(height: 4),
                                      DropdownButton<int>(
                                        value: _labelFontSizeLevel,
                                        underline: const SizedBox.shrink(),
                                        isExpanded: false,
                                        items: List.generate(
                                          kMaxFontSizeLevel -
                                              kMinFontSizeLevel +
                                          1,
                                          (i) {
                                            final level =
                                                kMinFontSizeLevel + i;
                                            return DropdownMenuItem<int>(
                                              value: level,
                                              child: Text(
                                                '$level (${fontSizeForLevel(level).toInt()}px)',
                                              ),
                                            );
                                          },
                                        ),
                                        onChanged: (level) {
                                          if (level != null) {
                                            setState(() =>
                                                _labelFontSizeLevel = level);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 説明
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('説明',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                      const SizedBox(height: 4),
                                      DropdownButton<int>(
                                        value: _descriptionFontSizeLevel,
                                        underline: const SizedBox.shrink(),
                                        isExpanded: false,
                                        items: List.generate(
                                          kMaxFontSizeLevel -
                                              kMinFontSizeLevel +
                                          1,
                                          (i) {
                                            final level =
                                                kMinFontSizeLevel + i;
                                            return DropdownMenuItem<int>(
                                              value: level,
                                              child: Text(
                                                '$level (${fontSizeForLevel(level).toInt()}px)',
                                              ),
                                            );
                                          },
                                        ),
                                        onChanged: (level) {
                                          if (level != null) {
                                            setState(() =>
                                                _descriptionFontSizeLevel =
                                                    level);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 下段：サイズ
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('サイズ',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: kObjectScales.map((s) {
                          final selected = s == _scale;
                          return _ChipButton(
                            label: '${s.toStringAsFixed(1)}倍',
                            selected: selected,
                            onTap: () => setState(() => _scale = s),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 形状
              Text('形状', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kDisplayShapes.map((shape) {
                  final selected = shape == _shape;
                  return _ChipButton(
                    label: shape.displayName,
                    selected: selected,
                    onTap: () {
                      setState(() => _shape = shape);
                      // 形状選択時に即座に lastShape を更新し、
                      // 次回新規作成時のデフォルト形状として保持する。
                      widget.onShapeSelected(shape);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // ラベル
              Text('ラベル', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'ラベル',
                ),
              ),
              const SizedBox(height: 10),

              // 説明
              Text('説明', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              TextField(
                controller: _detailController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '説明',
                ),
              ),
              const SizedBox(height: 10),

              // 詳細
              Text('詳細', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              TextField(
                controller: _contentController,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '詳細',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 選択可能なチップボタン（強調・サイズ・文字サイズレベル用）。
class _ChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : null,
          ),
        ),
      ),
    );
  }
}

/// 色を選択するためのスウォッチ表示。
class _ColorSwatch extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
