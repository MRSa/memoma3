import 'package:file_picker/file_picker.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../models/background_config.dart';

/// メインキャンバスの背景ガイドを設定するダイアログ。
///
/// 以下の4要素を独立して設定でき、各要素の透明度を個別に調整できる。
/// - グリッド（罫線 / ドット）：種類・間隔・色・透明度
/// - 背景色：色・透明度
/// - 背景画像：ローカル画像の選択・透明度
///
/// 「リセット」で初期値に戻し、「保存」で [onSave] に結果を返す。
/// キャンセルした場合は [onCancel] を呼ぶ。
class BackgroundSettingsDialog extends StatefulWidget {
  final BackgroundConfig current;

  /// 保存時に呼び出される。
  final ValueChanged<BackgroundConfig> onSave;

  /// キャンセル時に呼び出される。
  final VoidCallback onCancel;

  /// リセット時に呼び出される（初期値に戻す）。
  final VoidCallback onReset;

  const BackgroundSettingsDialog({
    super.key,
    required this.current,
    required this.onSave,
    required this.onCancel,
    required this.onReset,
  });

  @override
  State<BackgroundSettingsDialog> createState() =>
      _BackgroundSettingsDialogState();
}

class _BackgroundSettingsDialogState extends State<BackgroundSettingsDialog> {
  late GridType _gridType;
  late double _gridSpacing;
  late Color _gridColor;
  late double _gridOpacity;

  late Color _backgroundColor;
  late double _backgroundOpacity;

  late String? _backgroundImagePath;
  late double _backgroundImageOpacity;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _gridType = c.gridType;
    _gridSpacing = c.gridSpacing;
    _gridColor = c.gridColor;
    _gridOpacity = c.gridOpacity;
    _backgroundColor = c.backgroundColor;
    _backgroundOpacity = c.backgroundOpacity;
    _backgroundImagePath = c.backgroundImagePath;
    _backgroundImageOpacity = c.backgroundImageOpacity;
  }

  BackgroundConfig _buildConfig() {
    return BackgroundConfig(
      gridType: _gridType,
      gridSpacing: _gridSpacing,
      gridColor: _gridColor,
      gridOpacity: _gridOpacity,
      backgroundColor: _backgroundColor,
      backgroundOpacity: _backgroundOpacity,
      backgroundImagePath: _backgroundImagePath,
      backgroundImageOpacity: _backgroundImageOpacity,
    );
  }

  void _save() {
    widget.onSave(_buildConfig());
  }

  void _reset() {
    widget.onReset();
  }

  /// 色を選択するためのカラーピッカーダイアログを表示する。
  Future<void> _pickColor({
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onPicked,
  }) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => BlockSemantics(
        child: AlertDialog(
          key: ValueKey('color_picker_dialog_$title'),
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
      ),
    );
    if (picked != null && mounted) {
      onPicked(picked);
    }
  }

  /// ローカル画像を選択する。
  Future<void> _pickImage() async {
    if (kIsWeb) {
      // Web では file_picker の画像選択は path を返さないため、
      // 未対応としてスナックバーで案内する。
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('背景画像は Web 環境では未対応です'),
          ),
        );
      }
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.image,
    );
    final path = result.firstOrNull?.path;
    if (path != null && mounted) {
      setState(() {
        _backgroundImagePath = path;
        // 初回選択時は透明度を 0.5 に設定する。
        if (_backgroundImageOpacity == 0.0) {
          _backgroundImageOpacity = 0.5;
        }
      });
    }
  }

  /// 背景画像を削除する。
  void _clearImage() {
    setState(() {
      _backgroundImagePath = null;
    });
  }

  /// 透明度スライダー（0〜100%）を返す。
  Widget _opacitySlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// 色選択ボタン（現在の色のプレビュー付き）。
  Widget _colorButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey),
              ),
            ),
            label: Text('変更'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('background_settings_dialog'),
      title: const Text('背景ガイド設定'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // -------------------------------------------------------------
              // グリッド
              // -------------------------------------------------------------
              Text('グリッド', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: GridType.values.map((type) {
                  final selected = type == _gridType;
                  return InkWell(
                    onTap: () => setState(() => _gridType = type),
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
                        type.displayName,
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
              if (_gridType != GridType.none) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        '間隔',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _gridSpacing,
                        min: 10.0,
                        max: 200.0,
                        divisions: 19,
                        label: '${_gridSpacing.round()}',
                        onChanged: (v) =>
                            setState(() => _gridSpacing = v),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${_gridSpacing.round()}',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                _colorButton(
                  label: '色',
                  color: _gridColor,
                  onTap: () => _pickColor(
                    title: 'グリッドの色',
                    initialColor: _gridColor,
                    onPicked: (c) => setState(() => _gridColor = c),
                  ),
                ),
                const SizedBox(height: 8),
                _opacitySlider(
                  label: '透明度',
                  value: _gridOpacity,
                  onChanged: (v) => setState(() => _gridOpacity = v),
                ),
              ],
              const SizedBox(height: 20),

              // -------------------------------------------------------------
              // 背景色
              // -------------------------------------------------------------
              Text('背景色', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _colorButton(
                label: '色',
                color: _backgroundColor,
                onTap: () => _pickColor(
                  title: '背景色',
                  initialColor: _backgroundColor,
                  onPicked: (c) => setState(() {
                    _backgroundColor = c;
                    // 初回選択時は透明度を 0.5 に設定し、
                    // 色を選択した時点で背景色が見えるようにする。
                    if (_backgroundOpacity == 0.0) {
                      _backgroundOpacity = 0.5;
                    }
                  }),
                ),
              ),
              const SizedBox(height: 8),
              _opacitySlider(
                label: '透明度',
                value: _backgroundOpacity,
                onChanged: (v) => setState(() => _backgroundOpacity = v),
              ),
              const SizedBox(height: 20),

              // -------------------------------------------------------------
              // 背景画像
              // -------------------------------------------------------------
              Text('背景画像', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image, size: 18),
                      label: Text(
                        _backgroundImagePath == null
                            ? '画像を選択'
                            : '画像を変更',
                      ),
                    ),
                  ),
                  if (_backgroundImagePath != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '画像を削除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _clearImage,
                    ),
                  ],
                ],
              ),
              if (_backgroundImagePath != null) ...[
                const SizedBox(height: 4),
                Text(
                  _backgroundImagePath!,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                _opacitySlider(
                  label: '透明度',
                  value: _backgroundImageOpacity,
                  onChanged: (v) =>
                      setState(() => _backgroundImageOpacity = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _reset,
          child: const Text('リセット'),
        ),
        TextButton(
          onPressed: () => widget.onCancel(),
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
