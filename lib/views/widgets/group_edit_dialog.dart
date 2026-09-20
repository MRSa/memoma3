import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

import '../../../models/connection.dart';

/// グループ枠の情報を編集するダイアログ。
///
/// グループ名称（name）・説明（description）・枠線色（color）を変更でき、
/// 「保存」で [onSave] に結果を返す。キャンセルした場合は [onCancel] を呼ぶ。
class GroupEditDialog extends StatefulWidget {
  final GroupFrame frame;

  /// 保存時に呼び出される。変更内容は [updated] に格納される。
  final ValueChanged<GroupFrame> onSave;

  /// キャンセル時に呼び出される。
  final VoidCallback onCancel;

  /// グループを解除するボタンが押されたときに呼び出される。
  final VoidCallback? onDissolve;

  const GroupEditDialog({
    super.key,
    required this.frame,
    required this.onSave,
    required this.onCancel,
    this.onDissolve,
  });

  @override
  State<GroupEditDialog> createState() => _GroupEditDialogState();
}

class _GroupEditDialogState extends State<GroupEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late Color _color;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.frame.name);
    _descriptionController = TextEditingController(text: widget.frame.description);
    _color = widget.frame.color;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(
      widget.frame.copyWith(
        name: _nameController.text,
        description: _descriptionController.text,
        color: _color,
      ),
    );
  }

  /// 枠線色を選択するためのカラーピッカーダイアログを表示する。
  Future<void> _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('枠線の色を選択'),
        content: SizedBox(
          width: 320,
          child: ColorPicker(
            color: _color,
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
      setState(() => _color = picked);
    }
  }

  /// グループ解除の確認ダイアログを表示し、確認されたら解除する。
  void _confirmDissolve() {
    if (widget.onDissolve == null) return;
    showDialog<void>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: const Text('グループを解除しますか？'),
        content: const Text(
          'グループ枠を削除します。\n'
          '枠に属していたオブジェクト自体は残ります。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (confirmContext.mounted) {
                Navigator.of(confirmContext).pop();
              }
            },
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              if (confirmContext.mounted) {
                Navigator.of(confirmContext).pop();
              }
              widget.onDissolve?.call();
            },
            child: const Text('解除する'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('グループを編集'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 枠線色
              Text('枠線の色', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  InkWell(
                    onTap: _pickColor,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _color,
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'クリックして色を選択',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // グループ名称
              Text('グループ名称', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'グループ名称',
                ),
              ),
              const SizedBox(height: 12),

              // 説明
              Text('説明', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '説明',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onDissolve != null) ...[
          TextButton(
            onPressed: _confirmDissolve,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('グループを解除'),
          ),
          const VerticalDivider(width: 1),
        ],
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
