import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/action_bar_page_persistence_service.dart';
import '../../services/storage_service.dart';
import 'top_action_bar_left.dart';
import 'top_action_bar_right.dart';

/// アクションバーが 1 行に収まるとみなす最小幅（論理ピクセル）。
///
/// この幅以上なら左・右のボタン群を 1 行に並べ、
/// 未満なら左右 2 ページに切り替える表示にする。
const double kActionBarMinWidth = 1200.0;

/// キャンバスの上部に配置されるアクションバー。
///
/// 幅が広いときは左側（[TopActionBarLeft]）と右側（[TopActionBarRight]）の
/// ボタン群を 1 行に並べる。幅が狭いときは左右 2 ページに切り替える表示にし、
/// 現在のページを [ActionBarPagePersistenceService] で記憶する。
class TopActionBar extends ConsumerStatefulWidget {
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
  ConsumerState<TopActionBar> createState() => _TopActionBarState();
}

class _TopActionBarState extends ConsumerState<TopActionBar> {
  /// 右ページを表示中かどうか（2 ページ表示モードでのみ有効）。
  bool _showRightPage = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  /// 記憶された表示ページを読み込む。
  Future<void> _loadPage() async {
    final page = await ActionBarPagePersistenceService().load();
    if (!mounted) return;
    setState(() {
      _showRightPage = (page == ActionBarPagePersistenceService.pageRight);
    });
  }

  /// 左右ページを切り替え、選択を記憶する。
  void _togglePage() {
    setState(() {
      _showRightPage = !_showRightPage;
    });
    ActionBarPagePersistenceService().save(
      _showRightPage
          ? ActionBarPagePersistenceService.pageRight
          : ActionBarPagePersistenceService.pageLeft,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kActionBarMinWidth;

        if (wide) {
          // 1 行モード：左・右のボタン群を 1 行に並べる。
          return Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(child: _buildLeft()),
                actionBarDivider(context),
                _buildRight(),
              ],
            ),
          );
        }

        // 2 ページモード：左右を切り替える。
        // ページ読み込み中は左ページを表示する（既定）。
        if (!_showRightPage) {
          return Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(child: _buildLeft()),
                IconButton(
                  tooltip: '右ページへ',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _togglePage,
                ),
              ],
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                IconButton(
                  tooltip: '左ページへ',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _togglePage,
                ),
                Expanded(child: _buildRight()),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildLeft() {
    return TopActionBarLeft(storageService: widget.storageService);
  }

  Widget _buildRight() {
    return TopActionBarRight(
      onConnectionModeToggle: widget.onConnectionModeToggle,
      connectionMode: widget.connectionMode,
      onSelectionModeToggle: widget.onSelectionModeToggle,
      selectionMode: widget.selectionMode,
    );
  }
}

/// 操作カテゴリの区切り線（縦線）を返す。
///
/// 左・右のアクションバーで共通して使うため、トップレベル関数として公開する。
Widget actionBarDivider(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: VerticalDivider(
      width: 1,
      thickness: 1,
      color: Theme.of(context).dividerColor,
    ),
  );
}

/// JSON をダイアログのフィールドに表示・入力する。
///
/// 保存時は現在の JSON を表示し、読み込み時は空欄（または入力済みの JSON）
/// を表示する。OK でフィールドの値を返す。キャンセルした場合は null を返す。
Future<String?> showJsonDialog(
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
Future<void> showErrorDialog(
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
