import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

class MyCustomColorPicker extends StatelessWidget {
  const MyCustomColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
    this.title = '色を選択',
  });

  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final String title;

  /// ダイアログとして表示するための内部用 ColorPicker インスタンスを生成するヘルパー関数
  static ColorPicker _buildPicker(
    BuildContext context, {
    required Color initialColor,
    required ValueChanged<Color> onColorChanged,
    String title = '色を選択',
  }) {
    return ColorPicker(
      color: initialColor,
      onColorChanged: onColorChanged,

      // ピッカーの種類
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: true,
        ColorPickerType.wheel: true,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: false,
        ColorPickerType.custom: false,
      },

      // デザイン調整
      width: 40,
      height: 40,
      borderRadius: 8,
      spacing: 5,
      runSpacing: 5,
      wheelDiameter: 220,

      // カラーコード表示
      showColorCode: true,
      colorCodeReadOnly: false,

      // コピー＆ペースト設定
      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
        copyFormat: ColorPickerCopyFormat.numHexAARRGGBB,
        copyButton: true,
        pasteButton: true,
        longPressMenu: false,
      ),

      // ダイアログのOK/キャンセルボタン
      actionButtons: const ColorPickerActionButtons(
        okButton: true,
        closeButton: true,
        dialogActionButtons: true,
      ),

      // 日本語表示
      heading: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subheading: Text(
        'シェード（明度）を選択',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      wheelSubheading: Text(
        'カラーホイールで調整',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 通常の埋め込みWidgetとして使う場合
    return _buildPicker(
      context,
      initialColor: initialColor,
      onColorChanged: onColorChanged,
      title: title,
    );
  }

  /// ダイアログとして呼び出すための静的メソッド
  static Future<Color?> showAsDialog(
    BuildContext context, {
    required Color initialColor,
    String title = '色を選択',
  }) async {
    // 選択された色を保持しておく変数
    Color selectedColor = initialColor;

    // showPickerDialog は bool (OKならtrue, キャンセルならfalse) を返す
    final bool isConfirmed = await _buildPicker(
      context,
      initialColor: initialColor,
      onColorChanged: (Color color) {
        selectedColor = color; // 変更されるたびに色を保持
      },
      title: title,
    ).showPickerDialog(
      context,
      constraints: const BoxConstraints(
        minWidth: 320,
        minHeight: 450,
        maxWidth: 400,
      ),
    );

    // OKボタンが押された場合のみ選択された色を返し、キャンセル時は null を返す
    if (isConfirmed) {
      return selectedColor;
    }
    return null;
  }
}