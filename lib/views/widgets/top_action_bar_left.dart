import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../providers/canvas_provider.dart';
import '../../services/canvas_export_service.dart';
import '../../services/storage_service.dart';
import 'top_action_bar.dart';

/// トップアクションバーの左側ボタン群。
///
/// ファイル操作（読み込み / 保存 / 画像・PDF エクスポート）、
/// 履歴（Undo / Redo）、状態表示（メモ数 / 操作数）、キャンバス名を
/// 左から順に並べる。
class TopActionBarLeft extends ConsumerWidget {
  final StorageService storageService;

  const TopActionBarLeft({
    super.key,
    required this.storageService,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.read(canvasNotifierProvider);
    final notifier = ref.read(canvasNotifierProvider.notifier);
    final itemCount = state.objects.length;
    final undoCount = state.history.length;
    final canvasName = ref.watch(canvasNameProvider);

    return Row(
      children: [
        // ---------------------------------------------------------------
        // [1] ファイル操作：読み込み / 保存 / 画像・PDF エクスポート
        // ---------------------------------------------------------------
        IconButton(
          tooltip: '読み込み',
          icon: const Icon(Icons.file_open),
          onPressed: () => _onLoad(context, ref),
        ),
        IconButton(
          tooltip: '保存',
          icon: const Icon(Icons.save),
          onPressed: () => _onSave(context, ref),
        ),
        IconButton(
          tooltip: '画像/PDF エクスポート',
          icon: const Icon(Icons.image_outlined),
          onPressed: () => _onExportImage(context, ref),
        ),
        actionBarDivider(context),
        // ---------------------------------------------------------------
        // [2] 履歴：Undo / Redo
        // ---------------------------------------------------------------
        IconButton(
          tooltip: 'Undo',
          icon: const Icon(Icons.undo),
          onPressed: state.history.isEmpty ? null : () => notifier.undo(),
        ),
        IconButton(
          tooltip: 'Redo',
          icon: const Icon(Icons.redo),
          onPressed: state.redoStack.isEmpty ? null : () => notifier.redo(),
        ),
        actionBarDivider(context),
        // ---------------------------------------------------------------
        // [3] 状態表示：オブジェクト数 / 操作数（Undo 件数）
        // ---------------------------------------------------------------
        Text(
          'メモ: $itemCount',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 16),
        Text(
          '操作: $undoCount',
        ),
        actionBarDivider(context),
        // ---------------------------------------------------------------
        // [4] キャンバス名（タップで変更）
        // ---------------------------------------------------------------
        Expanded(
          child: Center(
            child: InkWell(
              onTap: () => _onEditCanvasName(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        canvasName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.edit,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// キャンバス名を編集するダイアログを表示する。
  void _onEditCanvasName(BuildContext context, WidgetRef ref) {
    final current = ref.read(canvasNameProvider);
    final controller = TextEditingController(text: current);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('キャンバス名を変更'),
        content: TextField(
          controller: controller,
          autofocus: true,
          // Enter（改行）で確定し、ダイアログを閉じる。
          onSubmitted: (value) {
            ref.read(canvasNameProvider.notifier).set(value);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'キャンバス名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(canvasNameProvider.notifier).set(controller.text);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// キャンバス状態を PNG / PDF としてエクスポートする。
  /// 形式を選択するダイアログを表示し、選択に応じて書き出す。
  Future<void> _onExportImage(BuildContext context, WidgetRef ref) async {
    final state = ref.read(canvasNotifierProvider);
    if (state.objects.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('エクスポートするオブジェクトがありません')),
        );
      }
      return;
    }

    // 形式を選択する。
    final format = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('エクスポート形式を選択'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('PNG 画像'),
              onTap: () => Navigator.of(dialogContext).pop('png'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF ファイル'),
              onTap: () => Navigator.of(dialogContext).pop('pdf'),
            ),
          ],
        ),
      ),
    );
    if (format == null) return; // キャンセル

    final canvasName = ref.read(canvasNameProvider);
    final background = ref.read(backgroundConfigProvider);
    final exportService = CanvasExportService();
    final extension = format == 'png' ? 'png' : 'pdf';

    try {
      final bytes = format == 'png'
          ? await exportService.exportPng(state, canvasName, background: background)
          : await exportService.exportPdf(state, canvasName, background: background);

      final path = await storageService.saveBytes(
        bytes: bytes,
        fileName: canvasName,
        extension: extension,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path != null ? 'エクスポートしました: $path' : 'エクスポートしました',
          ),
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

  Future<void> _onSave(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(canvasNotifierProvider.notifier);
    final json = notifier.exportToJson();
    // キャンバス名を保存時の初期ファイル名として使う。
    final canvasName = ref.read(canvasNameProvider);

    // Web はダイアログ内のフィールドに JSON を表示する。
    if (kIsWeb) {
      if (context.mounted) {
        await showJsonDialog(context, title: '保存', json: json);
      }
      return;
    }

    try {
      final path = await storageService.saveCanvas(
        fileContent: json,
        fileName: canvasName,
      );
      if (!context.mounted) return;
      if (path != null) {
        // 保存したファイル名（拡張子を除く）が現在のキャンバス名と異なる場合は、
        // そのファイル名をキャンバス名として設定する。
        final savedName = p.basenameWithoutExtension(path);
        if (savedName.isNotEmpty && savedName != canvasName) {
          ref.read(canvasNameProvider.notifier).set(savedName);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存しました: $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showErrorDialog(context, 'エラーが発生しました', '保存中にエラーが発生しました。');
      }
    }
  }

  Future<void> _onLoad(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(canvasNotifierProvider.notifier);

    // Web はダイアログ内のフィールドに JSON を入力して読み込む。
    if (kIsWeb) {
      if (context.mounted) {
        final json = await showJsonDialog(context, title: '読み込み', json: '');
        if (json == null) return;
        try {
          // ダイアログで入力された JSON を直接復元する。
          final state = storageService.decodeCanvas(json);
          notifier.loadFromJson(state.toJson());
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('読み込みました')),
          );
        } catch (e) {
          if (context.mounted) {
            showErrorDialog(context, 'エラーが発生しました', '読み込み中にエラーが発生しました。JSON の形式を確認してください。');
          }
        }
      }
      return;
    }

    try {
      final (state, fileName) = await storageService.loadCanvas();
      if (state != null) {
        notifier.loadFromJson(state.toJson());
        // 読み込んだファイル名をキャンバス名（題名）として反映する。
        if (fileName != null && fileName.isNotEmpty) {
          ref.read(canvasNameProvider.notifier).set(fileName);
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('読み込みました')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showErrorDialog(context, 'エラーが発生しました', '読み込み中にエラーが発生しました。');
      }
    }
  }
}
