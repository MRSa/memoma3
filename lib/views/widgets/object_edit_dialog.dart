import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

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
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          child: ColorPicker(
            color: initialColor,
            onColorChanged: (color) {
              Navigator.of(context).pop(color);
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
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 強調
              Text('強調', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Emphasis.values.map((emphasis) {
                  final selected = emphasis == _emphasis;
                  return InkWell(
                    onTap: () => setState(() => _emphasis = emphasis),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
                        emphasis.displayName,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: selected
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // 形状
              Text('形状', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kDisplayShapes.map((shape) {
                  final selected = shape == _shape;
                  return InkWell(
                    onTap: () {
                      setState(() => _shape = shape);
                      // 形状選択時に即座に lastShape を更新し、
                      // 次回新規作成時のデフォルト形状として保持する。
                      widget.onShapeSelected(shape);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
                        shape.displayName,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: selected
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // 色
              Text('色', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Row(
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
                  const SizedBox(width: 12),
                  _ColorSwatch(
                    label: 'ラベル色',
                    color: _labelColor ?? _color,
                    onTap: () => _pickColor(
                      title: 'ラベル色を選択',
                      initialColor: _labelColor ?? _color,
                      target: ColorPickerTarget.label,
                    ),
                  ),
                  const SizedBox(width: 12),
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
              const SizedBox(height: 16),

              // ラベル
              Text('ラベル', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'ラベル',
                ),
              ),
              const SizedBox(height: 12),

              // 説明
              Text('説明', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _detailController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '説明',
                ),
              ),
              const SizedBox(height: 12),

              // 詳細
              Text('詳細', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
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
