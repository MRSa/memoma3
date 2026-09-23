import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_object.dart';
import '../providers/canvas_provider.dart';
import '../providers/canvas_state.dart';
import '../services/storage_service.dart';
import 'widgets/my_custom_color_picker.dart';
import 'object_list/object_list_controller.dart';
import 'object_list/object_list_editable_label_cell.dart';
import 'object_list/object_list_link_text_cell.dart';
import 'object_list/object_list_multi_select_dropdown.dart';
import 'object_list/object_list_sort_header.dart';
import 'object_list/object_list_ui.dart';

/// キャンバスの中心座標（[kCanvasSize] = 50000 x 50000 の中心）。
/// 新規オブジェクトのデフォルト配置位置として使用する。
const Offset _canvasCenter = Offset(25000, 25000);

/// 全オブジェクトを表形式（DataTable）で一覧表示する画面。
///
/// - 名称・形状・色・強調・グループ・接続線（from / to）・座標を表示する。
/// - カラムヘッダのタップで並べ替え、名称 / 形状 / 強調でフィルタリングできる。
/// - 名称・説明・詳細・形状・色・強調・X/Y 座標はテーブル上で直接編集できる。
/// - 各行に番号（全オブジェクト中の位置）を表示し、中心座標設定ボタンを備える。
/// - 新規オブジェクトをキャンバス中心に追加できる。
/// - 画面幅が足りない場合は横スクロールできる。
/// - 一覧データを Excel で読める CSV 形式でエクスポートできる。
class ObjectListScreen extends ConsumerStatefulWidget {
  const ObjectListScreen({super.key});

  @override
  ConsumerState<ObjectListScreen> createState() => _ObjectListScreenState();
}

class _ObjectListScreenState extends ConsumerState<ObjectListScreen> {
  final StorageService _storageService = StorageService();

  /// ロジック（フィルタ / ソート / CSV 生成）を担うコントローラ。
  final ObjectListController _controller = ObjectListController();

  /// 名称フィルタのテキスト。
  final TextEditingController _filterController = TextEditingController();

  /// 左右パネルの縦スクロールを同期させるためのスクロールコントローラ。
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _filterController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 編集
  // ---------------------------------------------------------------------------

  /// 名称（label）を編集する。
  void _updateLabel(String id, String label) {
    ref.read(canvasNotifierProvider.notifier).editObject(id: id, label: label);
  }

  /// 説明（detail）を編集するダイアログを表示する。
  Future<void> _onEditDetail(BuildContext context, NoteObject note) async {
    final value = await _showTextEditDialog(
      context,
      title: '説明を編集',
      initial: note.detail,
    );
    if (value != null) {
      ref.read(canvasNotifierProvider.notifier).editObject(id: note.id, detail: value);
    }
  }

  /// 詳細（content）を編集するダイアログを表示する。
  Future<void> _onEditContent(BuildContext context, NoteObject note) async {
    final value = await _showTextEditDialog(
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
  Future<String?> _showTextEditDialog(
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
  Future<void> _pickColor(BuildContext context, NoteObject note) async {
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
  Future<void> _onEditShape(BuildContext context, NoteObject note) async {
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
  Future<void> _onEditEmphasis(BuildContext context, NoteObject note) async {
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
  Future<void> _onEditX(BuildContext context, NoteObject note) async {
    final value = await _showNumberDialog(
      context,
      title: 'X 座標を編集',
      initial: note.position.dx,
    );
    if (value != null) {
      _updatePosition(note.id, value, note.position.dy);
    }
  }

  /// Y 座標を編集する。数値入力ダイアログを表示する。
  Future<void> _onEditY(BuildContext context, NoteObject note) async {
    final value = await _showNumberDialog(
      context,
      title: 'Y 座標を編集',
      initial: note.position.dy,
    );
    if (value != null) {
      _updatePosition(note.id, note.position.dx, value);
    }
  }

  /// 座標（左上）を絶対値で更新する。
  void _updatePosition(String id, double x, double y) {
    ref.read(canvasNotifierProvider.notifier).setPosition(id, Offset(x, y));
  }

  /// 選択したオブジェクトの中心をキャンバス中心（[canvasCenter]）に設定する。
  void _setCenter(BuildContext context, NoteObject note) {
    final target = Offset(
      _canvasCenter.dx - note.size.width / 2,
      _canvasCenter.dy - note.size.height / 2,
    );
    _updatePosition(note.id, target.dx, target.dy);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('中心座標に設定しました')),
      );
    }
  }

  /// 数値（double）を入力するダイアログを表示し、確定値を返す。
  /// キャンセルした場合は null を返す。
  Future<double?> _showNumberDialog(
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
  void _onAddObject(BuildContext context) {
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
  void _onDuplicate(BuildContext context, NoteObject o) {
    ref.read(canvasNotifierProvider.notifier).duplicateObject(o.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('オブジェクトを複製しました')),
      );
    }
  }

  /// 指定したオブジェクトの削除を確認ダイアログで確認し、
  /// 承認されたときのみ削除を実行する。
  void _confirmDelete(BuildContext context, NoteObject o) {
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
  Future<void> _onExportCsv(BuildContext context, WidgetRef ref) async {
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
    final csv = _controller.buildCsv(
      state.objects,
      state.connections,
      state.groupFrames,
    );

    try {
      final path = await _storageService.saveCanvas(
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

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(canvasNotifierProvider);
    final objects = _controller.filteredAndSorted(
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
            onPressed: () => _onAddObject(context),
          ),
          IconButton(
            tooltip: 'CSV エクスポート',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _onExportCsv(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(context),
          Expanded(
            child: objects.isEmpty
                ? const Center(child: Text('表示するオブジェクトがありません'))
                : _buildTable(context, objects, state),
          ),
        ],
      ),
    );
  }

  /// 固定カラム（No. / 名称）とスクロール可能カラム（それ以外）を
  /// 左右に並べたテーブルを構築する。
  ///
  /// - 外側：縦スクロール（左右パネルを一緒に縦スクロール）。
  /// - 左パネル：No. と名称を常時表示（横スクロールしても固定）。
  /// - 右パネル：残りのカラムを横スクロール可能。
  Widget _buildTable(
    BuildContext context,
    List<NoteObject> objects,
    CanvasState state,
  ) {
    final rows = _buildRowData(objects, state);
    final leftWidth = kNoWidth + kNameWidth;

    return SingleChildScrollView(
      controller: _verticalController,
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
                _buildLeftHeader(context),
                for (final row in rows) _buildLeftRow(context, row),
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
                  _buildRightHeader(context),
                  for (final row in rows) _buildRightRow(context, row),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 1 行分の表示データを構築する。
  List<RowData> _buildRowData(List<NoteObject> objects, CanvasState state) {
    final map = _controller.objectMap(objects);
    return objects.map((o) {
      final groupsFor = _controller.groupNamesFor(o.id, state.groupFrames);
      final from = _controller.connectionsFrom(o.id, state.connections, map);
      final to = _controller.connectionsTo(o.id, state.connections, map);
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
  Widget _sortHeader(String label, SortColumn col, {double? width}) {
    final header = SortHeader(
      label: label,
      sortCol: col,
      isSorted: _controller.isSortedColumn(col),
      icon: _controller.sortIcon(col),
      onTap: () {
        _controller.onSort(col);
        setState(() {});
      },
    );
    if (width == null) return header;
    return SizedBox(width: width, child: header);
  }

  /// 左パネル（No. / 名称）のヘッダ行を構築する。
  Widget _buildLeftHeader(BuildContext context) {
    return Container(
      height: kHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          SizedBox(
            width: kNoWidth,
            child: _sortHeader('No.', SortColumn.number),
          ),
          SizedBox(
            width: kNameWidth,
            child: _sortHeader('名称', SortColumn.name),
          ),
        ],
      ),
    );
  }

  /// 左パネル（No. / 名称）のデータ行を構築する。
  Widget _buildLeftRow(BuildContext context, RowData row) {
    final o = row.object;
    return Container(
      height: kRowHeight,
      color: _rowColor(context),
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
                onCommit: (id, label) => _updateLabel(id, label),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ソート不可のカラムヘッダ（ラベルのみ）を構築する。
  /// [width] を指定すると固定幅で表示する（データセルと揃える）。
  Widget _plainHeader(String label, {double? width}) {
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: kCellGap / 2),
      child: Text(label, overflow: TextOverflow.ellipsis),
    );
    if (width == null) return header;
    return SizedBox(width: width, child: header);
  }

  /// 右パネル（残りのカラム）のヘッダ行を構築する。
  /// 各カラムは固定幅で、データセルと揃える。
  Widget _buildRightHeader(BuildContext context) {
    return Container(
      height: kHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _plainHeader('説明', width: kDetailWidth),
          _plainHeader('詳細', width: kContentWidth),
          _sortHeader('グループ', SortColumn.group, width: kGroupWidth),
          _sortHeader('形状', SortColumn.shape, width: kShapeWidth),
          _sortHeader('強調', SortColumn.emphasis, width: kEmphasisWidth),
          _sortHeader('色', SortColumn.color, width: kColorWidth),
          _sortHeader('接続(from / to)', SortColumn.connection, width: kConnectionWidth),
          _sortHeader('X', SortColumn.x, width: kXWidth),
          _sortHeader('Y', SortColumn.y, width: kYWidth),
          _sortHeader('サイズ', SortColumn.scale, width: kScaleWidth),
          _plainHeader('中心', width: kCenterWidth),
          _plainHeader('複製', width: kDuplicateWidth),
          _plainHeader('削除', width: kDeleteWidth),
        ],
      ),
    );
  }

  /// 右パネル（残りのカラム）のデータ行を構築する。
  Widget _buildRightRow(BuildContext context, RowData row) {
    final o = row.object;
    return Container(
      height: kRowHeight,
      color: _rowColor(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 説明（detail）。タップで編集ダイアログ、http リンクはブラウザで開く。
          LinkTextCell(
            key: ValueKey('detail-${o.id}'),
            text: o.detail,
            maxLines: 5,
            onEdit: () => _onEditDetail(context, o),
          ),
          // 詳細（content）。タップで編集ダイアログ、http リンクはブラウザで開く。
          LinkTextCell(
            key: ValueKey('content-${o.id}'),
            text: o.content,
            maxLines: 5,
            onEdit: () => _onEditContent(context, o),
          ),
          // グループ（編集不可）。
          _cell(
            width: kGroupWidth,
            child: Text(
              row.groupsFor.isEmpty ? '-' : row.groupsFor.join(' / '),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 形状（タップで編集）。
          _cell(
            width: kShapeWidth,
            child: InkWell(
              onTap: () => _onEditShape(context, o),
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
          _cell(
            width: kEmphasisWidth,
            child: InkWell(
              onTap: () => _onEditEmphasis(context, o),
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
          _cell(
            width: kColorWidth,
            child: InkWell(
              onTap: () => _pickColor(context, o),
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
                  Flexible(child: Text(_controller.colorToHex(o.color), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
          // 接続（from / to、編集不可）。
          _cell(
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
          _cell(
            width: kXWidth,
            child: InkWell(
              onTap: () => _onEditX(context, o),
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
          _cell(
            width: kYWidth,
            child: InkWell(
              onTap: () => _onEditY(context, o),
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
          _cell(
            width: kScaleWidth,
            child: Text(
              '${o.scale.toStringAsFixed(1)}倍',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 中心移動ボタン。
          _cell(
            width: kCenterWidth,
            child: IconButton(
              tooltip: '中心座標に設定',
              icon: const Icon(Icons.center_focus_strong, size: 18),
              onPressed: () => _setCenter(context, o),
            ),
          ),
          // 複製ボタン。
          _cell(
            width: kDuplicateWidth,
            child: IconButton(
              tooltip: '複製',
              icon: const Icon(Icons.content_copy, size: 18),
              onPressed: () => _onDuplicate(context, o),
            ),
          ),
          // 削除ボタン。確認ダイアログで承認されたときのみ削除する。
          _cell(
            width: kDeleteWidth,
            child: IconButton(
              tooltip: '削除',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _confirmDelete(context, o),
            ),
          ),
        ],
      ),
    );
  }

  /// 右パネルのセル（固定幅 + 左右パディング）を返す。
  ///
  /// [width] を指定すると、ヘッダとデータセルで同じ幅になるよう揃える。
  Widget _cell({required Widget child, double? width}) {
    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: kCellGap / 2),
      child: child,
    );
    if (width == null) return inner;
    return SizedBox(width: width, child: inner);
  }

  /// 行の背景色（交互に色を付ける）。
  Color _rowColor(BuildContext context) {
    return Theme.of(context).colorScheme.surfaceContainerLow;
  }

  /// フィルタバー（名称テキスト + 形状ドロップダウン + 強調ドロップダウン）を構築する。
  /// 画面幅が足りない場合は横スクロールできるようにする。
  Widget _buildFilterBar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _filterController,
              onChanged: (v) {
                _controller.setFilterText(v);
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
              selected: _controller.shapeFilters,
              labelOf: (s) => s.displayName,
              onToggle: (s) {
                _controller.toggleShapeFilter(s);
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
              selected: _controller.emphasisFilters,
              labelOf: (e) => e.displayName,
              onToggle: (e) {
                _controller.toggleEmphasisFilter(e);
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'フィルタをクリア',
            icon: const Icon(Icons.filter_alt_off),
            onPressed: () {
              _controller.clearFilters();
              _filterController.clear();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
