import 'package:flutter/material.dart';

/// 名称をインライン編集するためのセル。
///
/// 自身の [TextEditingController] を保持し、Enter（onSubmitted）または
/// フォーカス喪失（onEditingComplete）で確定する。確定時に [onCommit] を
/// 呼び、親の state を更新する。
class EditableLabelCell extends StatefulWidget {
  final String id;
  final String label;
  final void Function(String id, String label) onCommit;

  const EditableLabelCell({
    super.key,
    required this.id,
    required this.label,
    required this.onCommit,
  });

  @override
  State<EditableLabelCell> createState() => _EditableLabelCellState();
}

class _EditableLabelCellState extends State<EditableLabelCell> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.label);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant EditableLabelCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部から label が変更された場合（フォーカス外）に同期する。
    if (!_focusNode.hasFocus && _controller.text != widget.label) {
      _controller.text = widget.label;
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final value = _controller.text;
    if (value != widget.label) {
      widget.onCommit(widget.id, value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(fontSize: 13),
        // 名称は最大 2 行まで表示する。
        maxLines: 2,
        minLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 6),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
      ),
    );
  }
}
