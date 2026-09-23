import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/canvas_provider.dart';
import '../object_list_screen.dart';
import 'background_settings_dialog.dart';
import 'object_edit_dialog.dart';
import 'top_action_bar.dart';

/// トップアクションバーの右側ボタン群。
///
/// 編集系（編集 / 複製 / 整列 / グループ化 / 接続）、削除系（削除 / 全削除）、
/// 構成系（接続モード / 選択モード / 全選択）、表示系（オブジェクト一覧 /
/// 背景ガイド設定）を並べる。
class TopActionBarRight extends ConsumerWidget {
  final VoidCallback? onConnectionModeToggle;
  final bool connectionMode;
  final VoidCallback? onSelectionModeToggle;
  final bool selectionMode;

  const TopActionBarRight({
    super.key,
    this.onConnectionModeToggle,
    this.connectionMode = false,
    this.onSelectionModeToggle,
    this.selectionMode = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.read(canvasNotifierProvider);
    final notifier = ref.read(canvasNotifierProvider.notifier);
    final itemCount = state.objects.length;

    return Row(
      children: [
        // ---------------------------------------------------------------
        // [5] 編集系：編集 / 複製 / 整列 / グループ化 / 接続
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
                      const SnackBar(
                        duration: Duration(milliseconds: 1500),
                        content: Text('オブジェクトを複製しました')
                      ),
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
                          duration: Duration(milliseconds: 1500),
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
                      const SnackBar(
                        duration: Duration(milliseconds: 1500),
                        content: Text('接続しました'),
                      ),
                    );
                  }
                },
        ),
        actionBarDivider(context),
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
        actionBarDivider(context),
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
        actionBarDivider(context),
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
      SnackBar(
        duration: Duration(milliseconds: 1500),
        content: Text(_alignModeLabel(mode))
      ),
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
              const SnackBar(
                duration: Duration(milliseconds: 1500),
                content: Text('背景ガイド設定を保存しました')
              ),
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
              const SnackBar(
                duration: Duration(milliseconds: 1500),
                content: Text('背景ガイド設定を初期値に戻しました')
              ),
            );
          }
        },
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
                  const SnackBar(
                    duration: Duration(milliseconds: 1500),
                    content: Text('オブジェクトを削除しました')
                  ),
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
                  const SnackBar(
                    duration: Duration(milliseconds: 1500),
                    content: Text('全オブジェクトを削除しました')
                  ),
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
