import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/note_object.dart';
import '../../providers/canvas_provider.dart';
import '../../services/storage_service.dart';
import '../object_list_screen.dart';
import '../widgets/my_custom_color_picker.dart';
import 'object_list_controller.dart';

/// キャンバスの中心座標（[kCanvasSize] = 50000 x 50000 の中心）。
/// 新規オブジェクトのデフォルト配置位置として使用する。
const Offset _canvasCenter = Offset(25000, 25000);

/// オブジェクト一覧画面の編集・ダイアログ系ロジック。
///
/// [ObjectListScreen] の state クラスが本 mixin を適用することで、
/// 編集ダイアログの表示やオブジェクト操作（追加 / 複製 / 削除 / 中心設定）
/// を利用する。[ConsumerState] を継承するため [ref] に直接アクセスできる。
mixin ObjectListEditActions on ConsumerState<ObjectListScreen> {
  /// 画面側が提供する [StorageService]。
  StorageService get storageService;

  /// 画面側が提供する [ObjectListController]。
  ObjectListController get controller;

  // ---------------------------------------------------------------------------
  // 編集
  // ---------------------------------------------------------------------------

  /// 名称（label）を編集する。
  void updateLabel(String id, String label) {
    ref.read(canvasNotifierProvider.notifier).editObject(id: id, label: label);
  }

  /// 説明（detail）を編集するダイアログを表示する。
  Future<void> onEditDetail(BuildContext context, NoteObject note) async {
    final value = await showTextEditDialog(
      context,
      title: '説明を編集',
      initial: note.detail,
    );
    if (value != null) {
      ref.read(canvasNotifierProvider.notifier).editObject(id: note.id, detail: value);
    }
  }

  /// 詳細（content）を編集するダイアログを表示する。
  Future<void> onEditContent(BuildContext context, NoteObject note) async {
    final value = await showTextEditDialog(
      context,
      title: '詳細を編集',
      initial: note.content,
    );
    if (value != null) {
      ref.read(canvasNotifierProvider.notifier).editObject(id: note.id, content: value);
    }
  }

  /// 複数行テキストを編集するダイアログを表示し、確定した文字列を返す。
  /// キャンセルした場合は null を返す。
  ///
  /// 説明・詳細は長文になり得るため、従来の AlertDialog より大きく
  /// （約 3 倍程度）の [Dialog] を使用し、広い編集領域を確保する。
  Future<String?> showTextEditDialog(
    BuildContext context, {
    required String title,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    // 画面サイズに応じてダイアログの大きさを調整する（最大 900 x 640）。
    final screenSize = MediaQuery.of(context).size;
    final width = (900.0).clamp(0.0, screenSize.width * 0.9);
    final height = (640.0).clamp(0.0, screenSize.height * 0.9);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: height,
            minWidth: 480,
            minHeight: 360,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(dialogContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                // expands: true は親の高さ制約に敏感でアサーションを起こしやすいため、
                // 代わりに maxLines を大きくしてスクロール可能なテキストフィールドにする。
                // 内容が 14 行を超えると内部でスクロールされる。
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 14,
                  minLines: 8,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('キャンセル'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(controller.text),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 色を編集する。カラーピッカーダイアログを表示する。
  Future<void> pickColor(BuildContext context, NoteObject note) async {
    final picked = await MyCustomColorPicker.showAsDialog(
      context,
      initialColor: note.color,
      title: '色を選択',
    );
    if (picked != null) {
      ref.read(canvasNotifierProvider.notifier).editObject(id: note.id, color: picked);
    }
  }

  /// 形状を編集する。ドロップダウンダイアログを表示する。
  Future<void> onEditShape(BuildContext context, NoteObject note) async {
    final picked = await showDialog<NoteShape>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('形状を選択'),
        content: SizedBox(
          width: 280,
          // オブジェクト編集ダイアログと同様のセグメントボタン（Wrap + InkWell）で選択する。
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kDisplayShapes.map((shape) {
              final selected = shape == note.shape;
              return InkWell(
                onTap: () => Navigator.of(dialogContext).pop(shape),
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
        ),
      ),
    );
    if (picked != null) {
      final notifier = ref.read(canvasNotifierProvider.notifier);
      notifier.editObject(id: note.id, shape: picked);
      // 次回新規作成時のデフォルト形状として保持する（編集ダイアログと同一挙動）。
      notifier.updateLastShape(picked);
    }
  }

  /// 強調レベルを編集する。ドロップダウンダイアログを表示する。
  Future<void> onEditEmphasis(BuildContext context, NoteObject note) async {
    final picked = await showDialog<Emphasis>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('強調を選択'),
        content: SizedBox(
          width: 240,
          child: RadioGroup<Emphasis>(
            groupValue: note.emphasis,
            onChanged: (value) {
              if (value != null) Navigator.of(dialogContext).pop(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final emphasis in Emphasis.values)
                  RadioListTile<Emphasis>(
                    title: Text(emphasis.displayName),
                    value: emphasis,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) {
      ref.read(canvasNotifierProvider.notifier).editObject(id: note.id, emphasis: picked);
    }
  }

  /// X 座標を編集する。数値入力ダイアログを表示する。
  Future<void> onEditX(BuildContext context, NoteObject note) async {
    final value = await showNumberDialog(
      context,
      title: 'X 座標を編集',
      initial: note.position.dx,
    );
    if (value != null) {
      updatePosition(note.id, value, note.position.dy);
    }
  }

  /// Y 座標を編集する。数値入力ダイアログを表示する。
  Future<void> onEditY(BuildContext context, NoteObject note) async {
    final value = await showNumberDialog(
      context,
      title: 'Y 座標を編集',
      initial: note.position.dy,
    );
    if (value != null) {
      updatePosition(note.id, note.position.dx, value);
    }
  }

  /// 座標（左上）を絶対値で更新する。
  void updatePosition(String id, double x, double y) {
    ref.read(canvasNotifierProvider.notifier).setPosition(id, Offset(x, y));
  }

  /// 選択したオブジェクトの中心をキャンバス中心（[canvasCenter]）に設定する。
  void setCenter(BuildContext context, NoteObject note) {
    final target = Offset(
      _canvasCenter.dx - note.size.width / 2,
      _canvasCenter.dy - note.size.height / 2,
    );
    updatePosition(note.id, target.dx, target.dy);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('中心座標に設定しました')),
      );
    }
  }

  /// 数値（double）を入力するダイアログを表示し、確定値を返す。
  /// キャンセルした場合は null を返す。
  Future<double?> showNumberDialog(
    BuildContext context, {
    required String title,
    required double initial,
  }) {
    final controller = TextEditingController(
      text: initial.toStringAsFixed(0),
    );
    return showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '数値',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 新規オブジェクトを追加する。座標はキャンバス中心に設定する。
  ///
  /// 末尾（最大の No.）に追加し、デフォルトの No. 降順ソートにより
  /// 一覧の先頭（上）に表示される。
  void onAddObject(BuildContext context) {
    final notifier = ref.read(canvasNotifierProvider.notifier);
    // 中心座標に配置（左上 = 中心 - サイズ/2）。
    final position = _canvasCenter - const Offset(90, 60);
    final newNote = notifier.makeNewNote(position);
    notifier.addObject(newNote);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先頭にオブジェクトを追加しました')),
      );
    }
  }

  /// 指定したオブジェクトを複製する。
  void onDuplicate(BuildContext context, NoteObject o) {
    ref.read(canvasNotifierProvider.notifier).duplicateObject(o.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('オブジェクトを複製しました')),
      );
    }
  }

  /// 指定したオブジェクトの削除を確認ダイアログで確認し、
  /// 承認されたときのみ削除を実行する。
  void confirmDelete(BuildContext context, NoteObject o) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('削除の確認'),
        content: Text(
          '${o.label.isNotEmpty ? o.label : 'このオブジェクト'}を削除しますか？\n'
          '接続されている接続線も削除されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () {
              ref.read(canvasNotifierProvider.notifier).deleteObject(o.id);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('オブジェクトを削除しました')),
                );
              }
            },
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CSV エクスポート
  // ---------------------------------------------------------------------------

  /// CSV をファイルに保存する。
  Future<void> onExportCsv(BuildContext context) async {
    final state = ref.read(canvasNotifierProvider);
    if (state.objects.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('エクスポートするオブジェクトがありません')),
        );
      }
      return;
    }

    final canvasName = ref.read(canvasNameProvider);
    final csv = controller.buildCsv(
      state.objects,
      state.connections,
      state.groupFrames,
    );

    try {
      final path = await storageService.saveCanvas(
        fileContent: csv,
        fileName: canvasName,
        extension: 'csv',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(path != null ? 'エクスポートしました: $path' : 'エクスポートしました'),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エクスポート中にエラーが発生しました: $e')),
        );
      }
    }
  }
}
