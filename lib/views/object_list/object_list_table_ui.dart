import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/note_object.dart';
import '../../providers/canvas_state.dart';
import '../object_list_screen.dart';
import 'object_list_controller.dart';
import 'object_list_editable_label_cell.dart';
import 'object_list_link_text_cell.dart';
import 'object_list_multi_select_dropdown.dart';
import 'object_list_sort_header.dart';
import 'object_list_ui.dart';

/// オブジェクト一覧画面のテーブル・フィルタバーの UI 構築ロジック。
///
/// [ObjectListScreen] の state クラスが本 mixin を適用することで、
/// テーブル（ヘッダ / 行）やフィルタバーのウィジェットを構築する。
/// 編集系メソッドは [ObjectListEditActions] が提供する。
mixin ObjectListTableUi on ConsumerState<ObjectListScreen> {
  /// 画面側が提供する [ObjectListController]。
  ObjectListController get controller;

  /// 画面側が提供する縦スクロールコントローラ。
  ScrollController get verticalController;

  /// 画面側が提供する名称フィルタのテキストコントローラ。
  TextEditingController get filterController;

  // ---------------------------------------------------------------------------
  // 編集系メソッド（ObjectListEditActions が実装）
  // ---------------------------------------------------------------------------

  void updateLabel(String id, String label);
  Future<void> onEditDetail(BuildContext context, NoteObject note);
  Future<void> onEditContent(BuildContext context, NoteObject note);
  Future<void> onEditShape(BuildContext context, NoteObject note);
  Future<void> onEditEmphasis(BuildContext context, NoteObject note);
  Future<void> pickColor(BuildContext context, NoteObject note);
  Future<void> onEditX(BuildContext context, NoteObject note);
  Future<void> onEditY(BuildContext context, NoteObject note);
  void setCenter(BuildContext context, NoteObject note);
  void onDuplicate(BuildContext context, NoteObject o);
  void confirmDelete(BuildContext context, NoteObject o);

  // ---------------------------------------------------------------------------
  // UI 構築
  // ---------------------------------------------------------------------------

  /// 固定カラム（No. / 名称）とスクロール可能カラム（それ以外）を
  /// 左右に並べたテーブルを構築する。
  ///
  /// - 外側：縦スクロール（左右パネルを一緒に縦スクロール）。
  /// - 左パネル：No. と名称を常時表示（横スクロールしても固定）。
  /// - 右パネル：残りのカラムを横スクロール可能。
  Widget buildTable(
    BuildContext context,
    List<NoteObject> objects,
    CanvasState state,
  ) {
    final rows = buildRowData(objects, state);
    final leftWidth = kNoWidth + kNameWidth;

    return SingleChildScrollView(
      controller: verticalController,
      scrollDirection: Axis.vertical,
      child: Row(
        // 縦スクロールビュー内では高さが無制限になるため、stretch は使えない。
        // 左右パネルは同じ行数・行高なので start で高さが揃う。
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -------------------------------------------------------------
          // 左パネル（固定）：No. / 名称
          // -------------------------------------------------------------
          // 右端の 1px 境界線は幅の内側に描かれるため、幅に 1px を加算して
          // 内容（No. + 名称）がはみ出さないようにする。
          Container(
            width: leftWidth + 1,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildLeftHeader(context),
                for (final row in rows) buildLeftRow(context, row),
              ],
            ),
          ),
          // -------------------------------------------------------------
          // 右パネル（横スクロール可能）：残りのカラム
          // -------------------------------------------------------------
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                // 横スクロールビュー内では幅が無制限になるため、stretch は使えない。
                // 各行は MainAxisSize.min で内容幅に収まる。
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildRightHeader(context),
                  for (final row in rows) buildRightRow(context, row),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 1 行分の表示データを構築する。
  List<RowData> buildRowData(List<NoteObject> objects, CanvasState state) {
    final map = controller.objectMap(objects);
    return objects.map((o) {
      final groupsFor = controller.groupNamesFor(o.id, state.groupFrames);
      final from = controller.connectionsFrom(o.id, state.connections, map);
      final to = controller.connectionsTo(o.id, state.connections, map);
      // 番号は全オブジェクト（フィルタ前）での位置に基づける。
      final number = state.objects.indexWhere((a) => a.id == o.id) + 1;
      return RowData(
        object: o,
        number: number,
        groupsFor: groupsFor,
        from: from,
        to: to,
      );
    }).toList();
  }

  /// ソートヘッダを構築するヘルパー。
  /// [width] を指定すると固定幅で表示する（データセルと揃える）。
  Widget sortHeader(String label, SortColumn col, {double? width}) {
    final header = SortHeader(
      label: label,
      sortCol: col,
      isSorted: controller.isSortedColumn(col),
      icon: controller.sortIcon(col),
      onTap: () {
        controller.onSort(col);
        setState(() {});
      },
    );
    if (width == null) return header;
    return SizedBox(width: width, child: header);
  }

  /// 左パネル（No. / 名称）のヘッダ行を構築する。
  Widget buildLeftHeader(BuildContext context) {
    return Container(
      height: kHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          SizedBox(
            width: kNoWidth,
            child: sortHeader('No.', SortColumn.number),
          ),
          SizedBox(
            width: kNameWidth,
            child: sortHeader('名称', SortColumn.name),
          ),
        ],
      ),
    );
  }

  /// 左パネル（No. / 名称）のデータ行を構築する。
  Widget buildLeftRow(BuildContext context, RowData row) {
    final o = row.object;
    return Container(
      height: kRowHeight,
      color: rowColor(context),
      child: Row(
        children: [
          SizedBox(
            width: kNoWidth,
            child: Center(
              child: Text('${row.number}', style: const TextStyle(fontSize: 12)),
            ),
          ),
          SizedBox(
            width: kNameWidth,
            // 右端に 5px のマージンを取り、説明欄との間隔を確保する。
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: EditableLabelCell(
                key: ValueKey('label-${o.id}'),
                id: o.id,
                label: o.label,
                onCommit: (id, label) => updateLabel(id, label),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ソート不可のカラムヘッダ（ラベルのみ）を構築する。
  /// [width] を指定すると固定幅で表示する（データセルと揃える）。
  Widget plainHeader(String label, {double? width}) {
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: kCellGap / 2),
      child: Text(label, overflow: TextOverflow.ellipsis),
    );
    if (width == null) return header;
    return SizedBox(width: width, child: header);
  }

  /// 右パネル（残りのカラム）のヘッダ行を構築する。
  /// 各カラムは固定幅で、データセルと揃える。
  Widget buildRightHeader(BuildContext context) {
    return Container(
      height: kHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          plainHeader('説明', width: kDetailWidth),
          plainHeader('詳細', width: kContentWidth),
          sortHeader('グループ', SortColumn.group, width: kGroupWidth),
          sortHeader('形状', SortColumn.shape, width: kShapeWidth),
          sortHeader('強調', SortColumn.emphasis, width: kEmphasisWidth),
          sortHeader('色', SortColumn.color, width: kColorWidth),
          sortHeader('接続(from / to)', SortColumn.connection, width: kConnectionWidth),
          sortHeader('X', SortColumn.x, width: kXWidth),
          sortHeader('Y', SortColumn.y, width: kYWidth),
          sortHeader('サイズ', SortColumn.scale, width: kScaleWidth),
          plainHeader('中心', width: kCenterWidth),
          plainHeader('複製', width: kDuplicateWidth),
          plainHeader('削除', width: kDeleteWidth),
        ],
      ),
    );
  }

  /// 右パネル（残りのカラム）のデータ行を構築する。
  Widget buildRightRow(BuildContext context, RowData row) {
    final o = row.object;
    return Container(
      height: kRowHeight,
      color: rowColor(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 説明（detail）。タップで編集ダイアログ、http リンクはブラウザで開く。
          LinkTextCell(
            key: ValueKey('detail-${o.id}'),
            text: o.detail,
            maxLines: 5,
            onEdit: () => onEditDetail(context, o),
          ),
          // 詳細（content）。タップで編集ダイアログ、http リンクはブラウザで開く。
          LinkTextCell(
            key: ValueKey('content-${o.id}'),
            text: o.content,
            maxLines: 5,
            onEdit: () => onEditContent(context, o),
          ),
          // グループ（編集不可）。
          cell(
            width: kGroupWidth,
            child: Text(
              row.groupsFor.isEmpty ? '-' : row.groupsFor.join(' / '),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 形状（タップで編集）。
          cell(
            width: kShapeWidth,
            child: InkWell(
              onTap: () => onEditShape(context, o),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(o.shape.displayName, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 12, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          // 強調（タップで編集）。
          cell(
            width: kEmphasisWidth,
            child: InkWell(
              onTap: () => onEditEmphasis(context, o),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(o.emphasis.displayName, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 12, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          // 色（タップでカラーピッカー）。
          cell(
            width: kColorWidth,
            child: InkWell(
              onTap: () => pickColor(context, o),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: o.color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade500),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: Text(controller.colorToHex(o.color), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
          // 接続（from / to、編集不可）。
          cell(
            width: kConnectionWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '→ ${row.from.isEmpty ? '-' : row.from.join(' / ')}',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '← ${row.to.isEmpty ? '-' : row.to.join(' / ')}',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // X 座標（タップで編集）。
          cell(
            width: kXWidth,
            child: InkWell(
              onTap: () => onEditX(context, o),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(o.position.dx.toStringAsFixed(0), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 12, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          // Y 座標（タップで編集）。
          cell(
            width: kYWidth,
            child: InkWell(
              onTap: () => onEditY(context, o),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(o.position.dy.toStringAsFixed(0), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 12, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          // サイズ（倍率）。
          cell(
            width: kScaleWidth,
            child: Text(
              '${o.scale.toStringAsFixed(1)}倍',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 中心移動ボタン。
          cell(
            width: kCenterWidth,
            child: IconButton(
              tooltip: '中心座標に設定',
              icon: const Icon(Icons.center_focus_strong, size: 18),
              onPressed: () => setCenter(context, o),
            ),
          ),
          // 複製ボタン。
          cell(
            width: kDuplicateWidth,
            child: IconButton(
              tooltip: '複製',
              icon: const Icon(Icons.content_copy, size: 18),
              onPressed: () => onDuplicate(context, o),
            ),
          ),
          // 削除ボタン。確認ダイアログで承認されたときのみ削除する。
          cell(
            width: kDeleteWidth,
            child: IconButton(
              tooltip: '削除',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => confirmDelete(context, o),
            ),
          ),
        ],
      ),
    );
  }

  /// 右パネルのセル（固定幅 + 左右パディング）を返す。
  ///
  /// [width] を指定すると、ヘッダとデータセルで同じ幅になるよう揃える。
  Widget cell({required Widget child, double? width}) {
    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: kCellGap / 2),
      child: child,
    );
    if (width == null) return inner;
    return SizedBox(width: width, child: inner);
  }

  /// 行の背景色（交互に色を付ける）。
  Color rowColor(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerLow;
  }

  /// フィルタバー（名称テキスト + 形状ドロップダウン + 強調ドロップダウン）を構築する。
  /// 画面幅が足りない場合は横スクロールできるようにする。
  Widget buildFilterBar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: filterController,
              onChanged: (v) {
                controller.setFilterText(v);
                setState(() {});
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '名称でフィルタ',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 形状フィルタ（複数選択可能）。使用できない形状（雲・台形（非対称））は除外。
          SizedBox(
            width: 180,
            child: MultiSelectDropdown<NoteShape>(
              label: '形状',
              options: kDisplayShapes,
              selected: controller.shapeFilters,
              labelOf: (s) => s.displayName,
              onToggle: (s) {
                controller.toggleShapeFilter(s);
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          // 強調フィルタ（複数選択可能）。
          SizedBox(
            width: 160,
            child: MultiSelectDropdown<Emphasis>(
              label: '強調',
              options: Emphasis.values,
              selected: controller.emphasisFilters,
              labelOf: (e) => e.displayName,
              onToggle: (e) {
                controller.toggleEmphasisFilter(e);
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'フィルタをクリア',
            icon: const Icon(Icons.filter_alt_off),
            onPressed: () {
              controller.clearFilters();
              filterController.clear();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
