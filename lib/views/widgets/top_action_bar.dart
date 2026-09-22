import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../providers/canvas_provider.dart';
import '../../services/canvas_export_service.dart';
import '../../services/storage_service.dart';
import '../object_list_screen.dart';
import 'background_settings_dialog.dart';
import 'object_edit_dialog.dart';

/// キャンバスの上部に配置されるアクションバー。
///
/// Undo ボタン、保存ボタン、読み込みボタン、オブジェクト編集ボタン、
/// オブジェクト件数・Undo件数の情報を表示する。
class TopActionBar extends ConsumerWidget {
  final StorageService storageService;
  final VoidCallback? onConnectionModeToggle;
  final bool connectionMode;

  /// 選択モードのトグル（キーボードのない環境向けの複数選択）。
  final VoidCallback? onSelectionModeToggle;
  final bool selectionMode;

  /// 選択モードを終了する（選択状態は保持）。
  final VoidCallback? onSelectionDone;

  const TopActionBar({
    super.key,
    required this.storageService,
    this.onConnectionModeToggle,
    this.connectionMode = false,
    this.onSelectionModeToggle,
    this.selectionMode = false,
    this.onSelectionDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.read(canvasNotifierProvider);
    final notifier = ref.read(canvasNotifierProvider.notifier);
    final itemCount = state.objects.length;
    final undoCount = state.history.length;
    final canvasName = ref.watch(canvasNameProvider);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
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
          _divider(context),
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
          _divider(context),
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
          _divider(context),
          // ---------------------------------------------------------------
          // [4] キャンバス名（中央表示、タップで変更）
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
          _divider(context),
          // ---------------------------------------------------------------
          // [5] 編集系：編集 / 整列 / グループ化 / 接続
          // ---------------------------------------------------------------
          IconButton(
            tooltip: '編集',
            icon: const Icon(Icons.edit),
            onPressed: state.selectedId == null
                ? null
                : () => _onEdit(context, ref),
          ),
          IconButton(
            tooltip: '複製 (Ctrl+D)',
            icon: const Icon(Icons.content_copy),
            onPressed: notifier.selectedCount == 0
                ? null
                : () {
                    notifier.duplicateSelected();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('オブジェクトを複製しました')),
                      );
                    }
                  },
          ),
          IconButton(
            tooltip: notifier.selectedCount > 1
                ? '整列（左/右/上/下/等間隔）'
                : '整列（X/Y を 10 の倍数に揃える）',
            icon: const Icon(Icons.align_horizontal_center),
            onPressed: notifier.selectedCount == 0
                ? null
                : () {
                    if (notifier.selectedCount > 1) {
                      _showAlignModeDialog(context, ref);
                    } else {
                      notifier.alignSelectedToStep(step: 10.0);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('選択中のオブジェクトを 10 の倍数に整列しました'),
                          ),
                        );
                      }
                    }
                  },
          ),
          IconButton(
            tooltip: 'グループ化',
            icon: const Icon(Icons.dashboard),
            onPressed: state.objects.any((o) => o.isSelected)
                ? () => notifier.createGroup(
                      state.objects
                          .where((o) => o.isSelected)
                          .map((o) => o.id)
                          .toList(),
                    )
                : null,
          ),
          IconButton(
            tooltip: '接続',
            icon: const Icon(Icons.link),
            onPressed: notifier.selectedCount < 2
                ? null
                : () {
                    notifier.connectSelected();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('接続しました')),
                      );
                    }
                  },
          ),
          _divider(context),
          // ---------------------------------------------------------------
          // [6] 削除系：削除 / 全削除
          // ---------------------------------------------------------------
          IconButton(
            tooltip: '削除',
            icon: const Icon(Icons.delete_outline),
            onPressed: notifier.selectedCount == 0
                ? null
                : () => _confirmDelete(context, ref),
          ),
          IconButton(
            tooltip: '全削除',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: itemCount == 0
                ? null
                : () => _confirmDeleteAll(context, ref),
          ),
          _divider(context),
          // ---------------------------------------------------------------
          // [7] 構成系：接続モード / 選択モード / 全選択
          // ---------------------------------------------------------------
          IconButton(
            tooltip: '接続モード',
            icon: const Icon(Icons.draw),
            style: _modeButtonStyle(connectionMode, context),
            onPressed: onConnectionModeToggle,
          ),
          IconButton(
            tooltip: '選択モード',
            icon: const Icon(Icons.checklist_rtl_outlined),
            style: _modeButtonStyle(selectionMode, context),
            onPressed: onSelectionModeToggle,
          ),
          IconButton(
            tooltip: '全選択',
            icon: const Icon(Icons.select_all),
            onPressed: (!selectionMode || state.objects.isEmpty)
                ? null
                : () => notifier.selectAll(),
          ),
          _divider(context),
          // ---------------------------------------------------------------
          // [8] 表示系：オブジェクト一覧 / 背景ガイド設定
          // ---------------------------------------------------------------
          IconButton(
            tooltip: 'オブジェクト一覧',
            icon: const Icon(Icons.table_rows),
            onPressed: () => _onObjectList(context),
          ),
          IconButton(
            tooltip: '背景ガイド設定',
            icon: const Icon(Icons.settings),
            onPressed: () => _onBackgroundSettings(context, ref),
          ),
        ],
      ),
    );
  }

  /// 操作カテゴリの区切り線（縦線）を返す。
  Widget _divider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: Theme.of(context).dividerColor,
      ),
    );
  }

  /// モード ON 時のボタンスタイル（枠線＋背景＋アイコン色）を返す。
  /// [active] が false のときは null（既定スタイル）を返す。
  ButtonStyle? _modeButtonStyle(bool active, BuildContext context) {
    if (!active) return null;
    final primary = Theme.of(context).colorScheme.primary;
    return IconButton.styleFrom(
      foregroundColor: primary,
      backgroundColor: primary.withValues(alpha: 0.12),
      side: BorderSide(color: primary, width: 2),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    );
  }

  /// オブジェクト一覧画面へ遷移する。
  /// 画面切り替え中はプログレスインジケータを表示する。
  void _onObjectList(BuildContext context) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: Container(
          color: Colors.black54,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
    overlay.insert(entry);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ObjectListScreen(),
      ),
    );

    // 遷移・初期描画が完了した時点でプログレスインジケータを除去する。
    Future.delayed(const Duration(milliseconds: 500), () {
      if (entry.mounted) entry.remove();
    });
  }

  /// 複数選択時の整列モード選択ダイアログを表示する。
  ///
  /// 「左揃え」「右揃え」「上揃え」「下揃え」「等間隔(横幅)」「等間隔(縦幅)」
  /// のいずれか 1 つを選択させ、選択に応じて [CanvasNotifier.alignSelected]
  /// を実行する。
  void _showAlignModeDialog(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(canvasNotifierProvider.notifier);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('整列方法を選択'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AlignOption(
                icon: Icons.format_align_left,
                label: '左揃え',
                onTap: () => _applyAlign(dialogContext, notifier, AlignMode.left),
              ),
              _AlignOption(
                icon: Icons.format_align_right,
                label: '右揃え',
                onTap: () => _applyAlign(dialogContext, notifier, AlignMode.right),
              ),
              _AlignOption(
                icon: Icons.align_vertical_top,
                label: '上揃え',
                onTap: () => _applyAlign(dialogContext, notifier, AlignMode.top),
              ),
              _AlignOption(
                icon: Icons.align_vertical_bottom,
                label: '下揃え',
                onTap: () => _applyAlign(dialogContext, notifier, AlignMode.bottom),
              ),
              _AlignOption(
                icon: Icons.horizontal_distribute,
                label: '等間隔（横幅）',
                onTap: () => _applyAlign(
                  dialogContext,
                  notifier,
                  AlignMode.distributeHorizontal,
                ),
              ),
              _AlignOption(
                icon: Icons.vertical_distribute,
                label: '等間隔（縦幅）',
                onTap: () => _applyAlign(
                  dialogContext,
                  notifier,
                  AlignMode.distributeVertical,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }

  /// 整列を実行し、ダイアログを閉じて結果を SnackBar で表示する。
  void _applyAlign(
    BuildContext dialogContext,
    CanvasNotifier notifier,
    AlignMode mode,
  ) {
    notifier.alignSelected(mode);
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    final messenger = ScaffoldMessenger.of(dialogContext);
    messenger.showSnackBar(
      SnackBar(content: Text(_alignModeLabel(mode))),
    );
  }

  /// 整列モードの人間向けラベルを返す。
  String _alignModeLabel(AlignMode mode) {
    switch (mode) {
      case AlignMode.left:
        return '左揃えを実行しました';
      case AlignMode.right:
        return '右揃えを実行しました';
      case AlignMode.top:
        return '上揃えを実行しました';
      case AlignMode.bottom:
        return '下揃えを実行しました';
      case AlignMode.distributeHorizontal:
        return '等間隔（横幅）で整列しました';
      case AlignMode.distributeVertical:
        return '等間隔（縦幅）で整列しました';
    }
  }

  /// 背景ガイド設定ダイアログを表示する。
  void _onBackgroundSettings(BuildContext context, WidgetRef ref) {
    final current = ref.read(backgroundConfigProvider);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => BackgroundSettingsDialog(
        current: current,
        onSave: (config) async {
          await ref.read(backgroundConfigProvider.notifier).update(config);
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('背景ガイド設定を保存しました')),
            );
          }
        },
        onCancel: () {
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
        onReset: () async {
          await ref.read(backgroundConfigProvider.notifier).reset();
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('背景ガイド設定を初期値に戻しました')),
            );
          }
        },
      ),
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

  /// 選択中のオブジェクトの削除を確認ダイアログで確認し、
  /// 確認がとれたときだけ削除する。
  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final count = ref.read(canvasNotifierProvider.notifier).selectedCount;
    final message = count == 1
        ? '選択中のオブジェクトを削除しますか？'
        : '選択中の $count 個のオブジェクトを削除しますか？';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('削除の確認'),
        content: Text(message),
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
              ref.read(canvasNotifierProvider.notifier).deleteSelected();
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

  /// 全オブジェクトの削除を確認ダイアログで確認し、承認されたときのみ実行する。
  void _confirmDeleteAll(BuildContext context, WidgetRef ref) {
    final count = ref.read(canvasNotifierProvider).objects.length;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('全削除の確認'),
        content: Text('全 $count 個のオブジェクトを削除しますか？\n'
            '接続線・グループ枠もすべて削除されます。'),
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
              ref.read(canvasNotifierProvider.notifier).deleteAllObjects();
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('全オブジェクトを削除しました')),
                );
              }
            },
            child: const Text('全削除'),
          ),
        ],
      ),
    );
  }

  /// 選択中のオブジェクトの情報を編集する。
  void _onEdit(BuildContext context, WidgetRef ref) {
    final state = ref.read(canvasNotifierProvider);
    final id = state.selectedId;
    if (id == null) return;
    final note = state.objects.firstWhere((o) => o.id == id);

    showDialog(
      context: context,
      builder: (dialogContext) => ObjectEditDialog(
        note: note,
        onShapeSelected: (shape) =>
            ref.read(canvasNotifierProvider.notifier).updateLastShape(shape),
        onSave: (updated) {
          ref
              .read(canvasNotifierProvider.notifier)
              .editObject(
                id: updated.id,
                shape: updated.shape,
                label: updated.label,
                detail: updated.detail,
                content: updated.content,
                color: updated.color,
                emphasis: updated.emphasis,
                labelColor: updated.labelColor,
                descriptionColor: updated.descriptionColor,
              );
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
        onCancel: () {
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
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
        await _showJsonDialog(context, title: '保存', json: json);
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
        _showErrorDialog(context, 'エラーが発生しました', '保存中にエラーが発生しました。');
      }
    }
  }

  Future<void> _onLoad(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(canvasNotifierProvider.notifier);

    // Web はダイアログ内のフィールドに JSON を入力して読み込む。
    if (kIsWeb) {
      if (context.mounted) {
        final json = await _showJsonDialog(context, title: '読み込み', json: '');
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
            _showErrorDialog(context, 'エラーが発生しました', '読み込み中にエラーが発生しました。JSON の形式を確認してください。');
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
        _showErrorDialog(context, 'エラーが発生しました', '読み込み中にエラーが発生しました。');
      }
    }
  }

  /// JSON をダイアログのフィールドに表示・入力する。
  ///
  /// 保存時は現在の JSON を表示し、読み込み時は空欄（または入力済みの JSON）
  /// を表示する。OK でフィールドの値を返す。キャンセルした場合は null を返す。
  Future<String?> _showJsonDialog(
    BuildContext context, {
    required String title,
    required String json,
  }) {
    final controller = TextEditingController(text: json);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 480,
            height: 320,
            child: TextField(
              controller: controller,
              maxLines: 12,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'JSON',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(title == '保存' ? '保存' : '読み込み'),
            ),
          ],
        );
      },
    );
  }

  /// エラー内容を伝えるダイアログを表示する。
  Future<void> _showErrorDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// 整列モード選択ダイアログ内の 1 行（アイコン + ラベル）の選択肢。
class _AlignOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AlignOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}