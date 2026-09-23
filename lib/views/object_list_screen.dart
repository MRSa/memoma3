import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/canvas_provider.dart';
import '../services/storage_service.dart';
import 'object_list/object_list_controller.dart';
import 'object_list/object_list_edit_actions.dart';
import 'object_list/object_list_table_ui.dart';

/// 全オブジェクトを表形式（DataTable）で一覧表示する画面。
///
/// - 名称・形状・色・強調・グループ・接続線（from / to）・座標を表示する。
/// - カラムヘッダのタップで並べ替え、名称 / 形状 / 強調でフィルタリングできる。
/// - 名称・説明・詳細・形状・色・強調・X/Y 座標はテーブル上で直接編集できる。
/// - 各行に番号（全オブジェクト中の位置）を表示し、中心座標設定ボタンを備える。
/// - 新規オブジェクトをキャンバス中心に追加できる。
/// - 画面幅が足りない場合は横スクロールできる。
/// - 一覧データを Excel で読める CSV 形式でエクスポートできる。
///
/// 編集・ダイアログ系は [ObjectListEditActions]、テーブル・フィルタバーの
/// UI 構築は [ObjectListTableUi] に分離されている。
class ObjectListScreen extends ConsumerStatefulWidget {
  const ObjectListScreen({super.key});

  @override
  ConsumerState<ObjectListScreen> createState() => _ObjectListScreenState();
}

class _ObjectListScreenState extends ConsumerState<ObjectListScreen>
    with ObjectListEditActions, ObjectListTableUi {
  @override
  final StorageService storageService = StorageService();

  /// ロジック（フィルタ / ソート / CSV 生成）を担うコントローラ。
  @override
  final ObjectListController controller = ObjectListController();

  /// 名称フィルタのテキスト。
  @override
  final TextEditingController filterController = TextEditingController();

  /// 左右パネルの縦スクロールを同期させるためのスクロールコントローラ。
  @override
  final ScrollController verticalController = ScrollController();

  @override
  void dispose() {
    filterController.dispose();
    verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(canvasNotifierProvider);
    final objects = controller.filteredAndSorted(
      state.objects,
      state.connections,
      state.groupFrames,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('オブジェクト一覧'),
        actions: [
          IconButton(
            tooltip: '新規オブジェクト追加（中心座標）',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onAddObject(context),
          ),
          IconButton(
            tooltip: 'CSV エクスポート',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => onExportCsv(context),
          ),
        ],
      ),
      body: Column(
        children: [
          buildFilterBar(context),
          Expanded(
            child: objects.isEmpty
                ? const Center(child: Text('表示するオブジェクトがありません'))
                : buildTable(context, objects, state),
          ),
        ],
      ),
    );
  }
}
