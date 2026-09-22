import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'widgets/my_custom_color_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/connection.dart';
import '../models/note_object.dart';
import '../providers/canvas_provider.dart';
import '../providers/canvas_state.dart';
import '../services/storage_service.dart';

/// キャンバスの中心座標（[kCanvasSize] = 50000 x 50000 の中心）。
/// 新規オブジェクトのデフォルト配置位置として使用する。
const Offset _canvasCenter = Offset(25000, 25000);

/// 固定カラム（No. / 名称）の幅。
const double _kNoWidth = 56.0;
const double _kNameWidth = 180.0;

/// ヘッダ行の高さ。
const double _kHeaderHeight = 56.0;

/// データ行の高さ（説明・詳細の複数行表示に合わせる）。
const double _kRowHeight = 90.0;

/// セル間の左右パディング。
const double _kCellGap = 12.0;

/// 右パネル各カラムの固定幅（ヘッダとデータセルで揃える）。
const double _kDetailWidth = 220.0;
const double _kContentWidth = 220.0;
const double _kShapeWidth = 90.0;
const double _kColorWidth = 110.0;
const double _kEmphasisWidth = 90.0;
const double _kGroupWidth = 160.0;
const double _kConnectionWidth = 220.0;
const double _kXWidth = 80.0;
const double _kYWidth = 80.0;
const double _kScaleWidth = 70.0;
const double _kCenterWidth = 56.0;
const double _kDuplicateWidth = 56.0;
const double _kDeleteWidth = 56.0;

/// 一覧テーブルのソート対象カラム。
enum _SortColumn {
  number,
  name,
  shape,
  color,
  emphasis,
  group,
  connection,
  x,
  y,
  scale,
}

/// 一覧テーブルのソート方向。
enum _SortDirection {
  ascending,
  descending,
}

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

  /// 名称フィルタのテキスト。
  final TextEditingController _filterController = TextEditingController();
  String _filterText = '';

  /// 形状フィルタ（空 = すべて）。複数選択可能。
  final Set<NoteShape> _shapeFilters = {};

  /// 強調フィルタ（空 = すべて）。複数選択可能。
  final Set<Emphasis> _emphasisFilters = {};

  /// 現在のソート対象カラムと方向。
  /// デフォルトは No.（番号）降順でソートし、最新（最大の No.）が先頭に来る。
  _SortColumn _sortColumn = _SortColumn.number;
  _SortDirection _sortDirection = _SortDirection.descending;

  /// 左右パネルの縦スクロールを同期させるためのスクロールコントローラ。
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _filterController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // データ集約
  // ---------------------------------------------------------------------------

  /// ID → オブジェクト のマップを構築する。
  Map<String, NoteObject> _objectMap(List<NoteObject> objects) {
    final map = <String, NoteObject>{};
    for (final o in objects) {
      map[o.id] = o;
    }
    return map;
  }

  /// オブジェクトが属するグループ名称の一覧を返す。
  List<String> _groupNamesFor(String objectId, List<GroupFrame> groups) {
    final names = <String>[];
    for (final g in groups) {
      if (g.memberIds.contains(objectId)) {
        names.add(g.name.isNotEmpty ? g.name : g.id);
      }
    }
    return names;
  }

  /// オブジェクトが「発端（from）」になっている接続先の名称一覧。
  List<String> _connectionsFrom(String objectId, List<Connection> connections, Map<String, NoteObject> map) {
    final names = <String>[];
    for (final c in connections) {
      if (c.sourceId == objectId) {
        final target = map[c.targetId];
        names.add(target != null && target.label.isNotEmpty ? target.label : c.targetId);
      }
    }
    return names;
  }

  /// オブジェクトが「着地（to）」になっている接続元の名称一覧。
  List<String> _connectionsTo(String objectId, List<Connection> connections, Map<String, NoteObject> map) {
    final names = <String>[];
    for (final c in connections) {
      if (c.targetId == objectId) {
        final source = map[c.sourceId];
        names.add(source != null && source.label.isNotEmpty ? source.label : c.sourceId);
      }
    }
    return names;
  }

  /// 名称フィルタ・形状フィルタ・強調フィルタを適用したオブジェクト一覧を返す。
  List<NoteObject> _filteredObjects(List<NoteObject> objects) {
    final filter = _filterText.trim().toLowerCase();
    return objects.where((o) {
      // 形状フィルタ：選択済み（空でなければ）に属するもののみ。
      if (_shapeFilters.isNotEmpty && !_shapeFilters.contains(o.shape)) return false;
      // 強調フィルタ：選択済み（空でなければ）に属するもののみ。
      if (_emphasisFilters.isNotEmpty && !_emphasisFilters.contains(o.emphasis)) return false;
      if (filter.isEmpty) return true;
      return o.label.toLowerCase().contains(filter) ||
          o.content.toLowerCase().contains(filter) ||
          o.detail.toLowerCase().contains(filter);
    }).toList();
  }

  /// ソートキーを返す。
  String _sortKey(NoteObject o, List<Connection> connections, List<GroupFrame> groups, Map<String, NoteObject> map, List<NoteObject> allObjects) {
    switch (_sortColumn) {
      case _SortColumn.number:
        // 番号は全オブジェクト（フィルタ前）中の位置。数値としてソートするため
        // 桁数を揃えた文字列を返す。
        final index = allObjects.indexWhere((a) => a.id == o.id);
        return (index < 0 ? 0 : index).toString().padLeft(6, '0');
      case _SortColumn.name:
        return o.label;
      case _SortColumn.shape:
        return o.shape.displayName;
      case _SortColumn.color:
        return o.color.toARGB32().toRadixString(16);
      case _SortColumn.emphasis:
        return o.emphasis.displayName;
      case _SortColumn.group:
        return _groupNamesFor(o.id, groups).join(',');
      case _SortColumn.connection:
        return '${_connectionsFrom(o.id, connections, map).join(',')}|${_connectionsTo(o.id, connections, map).join(',')}';
      case _SortColumn.x:
        return o.position.dx.toStringAsFixed(0);
      case _SortColumn.y:
        return o.position.dy.toStringAsFixed(0);
      case _SortColumn.scale:
        // 0.5〜4.0 の 0.5 刻みなので、1 桁小数の文字列で数値順にソートできる。
        return o.scale.toStringAsFixed(1);
    }
  }

  /// ソート済み・フィルタ済みオブジェクト一覧を返す。
  /// [allObjects] はフィルタ前の全オブジェクト（番号・No. ソート用）。
  List<NoteObject> _sortedObjects(List<NoteObject> objects, List<Connection> connections, List<GroupFrame> groups, List<NoteObject> allObjects) {
    final map = _objectMap(objects);
    final list = List<NoteObject>.from(objects);
    list.sort((a, b) {
      final ka = _sortKey(a, connections, groups, map, allObjects);
      final kb = _sortKey(b, connections, groups, map, allObjects);
      final result = ka.compareTo(kb);
      return _sortDirection == _SortDirection.ascending ? result : -result;
    });
    return list;
  }

  /// カラムヘッダのタップでソートを切り替える。
  void _onSort(_SortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortDirection = _sortDirection == _SortDirection.ascending
            ? _SortDirection.descending
            : _SortDirection.ascending;
      } else {
        _sortColumn = column;
        _sortDirection = _SortDirection.ascending;
      }
    });
  }

  /// ソートインジケータのアイコンを返す。
  IconData _sortIcon(_SortColumn column) {
    if (_sortColumn != column) return Icons.arrow_upward;
    return _sortDirection == _SortDirection.ascending
        ? Icons.arrow_upward
        : Icons.arrow_downward;
  }

  /// 現在ソートに使用しているカラムかどうか。
  bool _isSortedColumn(_SortColumn column) => _sortColumn == column;

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

  // ---------------------------------------------------------------------------
  // CSV エクスポート
  // ---------------------------------------------------------------------------

  /// CSV のフィールドをエスケープする（カンマ・改行・引用符を含む場合）。
  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// 一覧データを Excel で読める CSV 文字列（UTF-8 BOM 付き）を生成する。
  String _buildCsv(List<NoteObject> objects, List<Connection> connections, List<GroupFrame> groups) {
    final map = _objectMap(objects);
    const headers = [
      '名称',
      '説明',
      '詳細',
      '形状',
      '強調',
      '色',
      'グループ',
      '接続(from)',
      '接続(to)',
      'X',
      'Y',
      'サイズ',
    ];
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_csvEscape).join(','));

    for (final o in objects) {
      final row = <String>[
        o.label,
        o.detail,
        o.content,
        o.shape.displayName,
        o.emphasis.displayName,
        _colorToHex(o.color),
        _groupNamesFor(o.id, groups).join(' / '),
        _connectionsFrom(o.id, connections, map).join(' / '),
        _connectionsTo(o.id, connections, map).join(' / '),
        o.position.dx.toStringAsFixed(0),
        o.position.dy.toStringAsFixed(0),
        '${o.scale.toStringAsFixed(1)}倍',
      ];
      buffer.writeln(row.map(_csvEscape).join(','));
    }

    // Excel が UTF-8 を正しく認識できるよう BOM を付与する。
    return '\uFEFF${buffer.toString()}';
  }

  /// Color を #RRGGBB 形式の文字列に変換する。
  String _colorToHex(Color color) {
    final hex = color.toARGB32() & 0xFFFFFF;
    return '#${hex.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

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
    final csv = _buildCsv(state.objects, state.connections, state.groupFrames);

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
    final objects = _sortedObjects(
      _filteredObjects(state.objects),
      state.connections,
      state.groupFrames,
      state.objects,
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
    final leftWidth = _kNoWidth + _kNameWidth;

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
  List<_RowData> _buildRowData(List<NoteObject> objects, CanvasState state) {
    final map = _objectMap(objects);
    return objects.map((o) {
      final groupsFor = _groupNamesFor(o.id, state.groupFrames);
      final from = _connectionsFrom(o.id, state.connections, map);
      final to = _connectionsTo(o.id, state.connections, map);
      // 番号は全オブジェクト（フィルタ前）での位置に基づける。
      final number = state.objects.indexWhere((a) => a.id == o.id) + 1;
      return _RowData(
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
  Widget _sortHeader(String label, _SortColumn col, {double? width}) {
    final header = _SortHeader(
      label: label,
      sortCol: col,
      isSorted: _isSortedColumn(col),
      icon: _sortIcon(col),
      onTap: () => _onSort(col),
    );
    if (width == null) return header;
    return SizedBox(width: width, child: header);
  }

  /// 左パネル（No. / 名称）のヘッダ行を構築する。
  Widget _buildLeftHeader(BuildContext context) {
    return Container(
      height: _kHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          SizedBox(
            width: _kNoWidth,
            child: _sortHeader('No.', _SortColumn.number),
          ),
          SizedBox(
            width: _kNameWidth,
            child: _sortHeader('名称', _SortColumn.name),
          ),
        ],
      ),
    );
  }

  /// 左パネル（No. / 名称）のデータ行を構築する。
  Widget _buildLeftRow(BuildContext context, _RowData row) {
    final o = row.object;
    return Container(
      height: _kRowHeight,
      color: _rowColor(context),
      child: Row(
        children: [
          SizedBox(
            width: _kNoWidth,
            child: Center(
              child: Text('${row.number}', style: const TextStyle(fontSize: 12)),
            ),
          ),
          SizedBox(
            width: _kNameWidth,
            // 右端に 5px のマージンを取り、説明欄との間隔を確保する。
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: _EditableLabelCell(
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
      padding: const EdgeInsets.symmetric(horizontal: _kCellGap / 2),
      child: Text(label, overflow: TextOverflow.ellipsis),
    );
    if (width == null) return header;
    return SizedBox(width: width, child: header);
  }

  /// 右パネル（残りのカラム）のヘッダ行を構築する。
  /// 各カラムは固定幅で、データセルと揃える。
  Widget _buildRightHeader(BuildContext context) {
    return Container(
      height: _kHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _plainHeader('説明', width: _kDetailWidth),
          _plainHeader('詳細', width: _kContentWidth),
          _sortHeader('グループ', _SortColumn.group, width: _kGroupWidth),
          _sortHeader('形状', _SortColumn.shape, width: _kShapeWidth),
          _sortHeader('強調', _SortColumn.emphasis, width: _kEmphasisWidth),
          _sortHeader('色', _SortColumn.color, width: _kColorWidth),
          _sortHeader('接続(from / to)', _SortColumn.connection, width: _kConnectionWidth),
          _sortHeader('X', _SortColumn.x, width: _kXWidth),
          _sortHeader('Y', _SortColumn.y, width: _kYWidth),
          _sortHeader('サイズ', _SortColumn.scale, width: _kScaleWidth),
          _plainHeader('中心', width: _kCenterWidth),
          _plainHeader('複製', width: _kDuplicateWidth),
          _plainHeader('削除', width: _kDeleteWidth),
        ],
      ),
    );
  }

  /// 右パネル（残りのカラム）のデータ行を構築する。
  Widget _buildRightRow(BuildContext context, _RowData row) {
    final o = row.object;
    return Container(
      height: _kRowHeight,
      color: _rowColor(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 説明（detail）。タップで編集ダイアログ、http リンクはブラウザで開く。
          _LinkTextCell(
            key: ValueKey('detail-${o.id}'),
            text: o.detail,
            maxLines: 5,
            onEdit: () => _onEditDetail(context, o),
          ),
          // 詳細（content）。タップで編集ダイアログ、http リンクはブラウザで開く。
          _LinkTextCell(
            key: ValueKey('content-${o.id}'),
            text: o.content,
            maxLines: 5,
            onEdit: () => _onEditContent(context, o),
          ),
          // グループ（編集不可）。
          _cell(
            width: _kGroupWidth,
            child: Text(
              row.groupsFor.isEmpty ? '-' : row.groupsFor.join(' / '),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 形状（タップで編集）。
          _cell(
            width: _kShapeWidth,
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
            width: _kEmphasisWidth,
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
            width: _kColorWidth,
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
                  Flexible(child: Text(_colorToHex(o.color), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
          // 接続（from / to、編集不可）。
          _cell(
            width: _kConnectionWidth,
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
            width: _kXWidth,
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
            width: _kYWidth,
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
            width: _kScaleWidth,
            child: Text(
              '${o.scale.toStringAsFixed(1)}倍',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 中心移動ボタン。
          _cell(
            width: _kCenterWidth,
            child: IconButton(
              tooltip: '中心座標に設定',
              icon: const Icon(Icons.center_focus_strong, size: 18),
              onPressed: () => _setCenter(context, o),
            ),
          ),
          // 複製ボタン。
          _cell(
            width: _kDuplicateWidth,
            child: IconButton(
              tooltip: '複製',
              icon: const Icon(Icons.content_copy, size: 18),
              onPressed: () => _onDuplicate(context, o),
            ),
          ),
          // 削除ボタン。確認ダイアログで承認されたときのみ削除する。
          _cell(
            width: _kDeleteWidth,
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
      padding: const EdgeInsets.symmetric(horizontal: _kCellGap / 2),
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
              onChanged: (v) => setState(() => _filterText = v),
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
            child: _MultiSelectDropdown<NoteShape>(
              label: '形状',
              options: kDisplayShapes,
              selected: _shapeFilters,
              labelOf: (s) => s.displayName,
              onToggle: (s) => setState(() {
                if (_shapeFilters.contains(s)) {
                  _shapeFilters.remove(s);
                } else {
                  _shapeFilters.add(s);
                }
              }),
            ),
          ),
          const SizedBox(width: 8),
          // 強調フィルタ（複数選択可能）。
          SizedBox(
            width: 160,
            child: _MultiSelectDropdown<Emphasis>(
              label: '強調',
              options: Emphasis.values,
              selected: _emphasisFilters,
              labelOf: (e) => e.displayName,
              onToggle: (e) => setState(() {
                if (_emphasisFilters.contains(e)) {
                  _emphasisFilters.remove(e);
                } else {
                  _emphasisFilters.add(e);
                }
              }),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'フィルタをクリア',
            icon: const Icon(Icons.filter_alt_off),
            onPressed: () => setState(() {
              _filterController.clear();
              _filterText = '';
              _shapeFilters.clear();
              _emphasisFilters.clear();
            }),
          ),
        ],
      ),
    );
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
}

/// 名称をインライン編集するためのセル。
///
/// 自身の [TextEditingController] を保持し、Enter（onSubmitted）または
/// フォーカス喪失（onEditingComplete）で確定する。確定時に [onCommit] を
/// 呼び、親の state を更新する。
class _EditableLabelCell extends StatefulWidget {
  final String id;
  final String label;
  final void Function(String id, String label) onCommit;

  const _EditableLabelCell({
    super.key,
    required this.id,
    required this.label,
    required this.onCommit,
  });

  @override
  State<_EditableLabelCell> createState() => _EditableLabelCellState();
}

class _EditableLabelCellState extends State<_EditableLabelCell> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.label);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _EditableLabelCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部から label が変更された場合（フォーカス外）に同期する。
    if (!_focusNode.hasFocus && _controller.text != widget.label) {
      _controller.text = widget.label;
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final value = _controller.text;
    if (value != widget.label) {
      widget.onCommit(widget.id, value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(fontSize: 13),
        // 名称は最大 2 行まで表示する。
        maxLines: 2,
        minLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 6),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
      ),
    );
  }
}

/// 説明・詳細を表示するセル。
///
/// - 複数行のテキストは最大 5 行まで表示し、超過分は省略記号（…）で切る。
/// - 含まれる `http://` / `https://` リンクは下線付きで表示し、タップすると
///   ブラウザで開く。
/// - リンク以外の部分（またはセル全体）をタップすると [onEdit] が呼ばれ、
///   編集ダイアログが開く。
class _LinkTextCell extends StatelessWidget {
  final String text;
  final VoidCallback onEdit;

  /// 表示する最大行数。
  final int maxLines;

  const _LinkTextCell({
    super.key,
    required this.text,
    required this.onEdit,
    this.maxLines = 12,
  });

  /// http(s) リンクをトークン化して [TextSpan] のリストを構築する。
  ///
  /// リンクは [TextSpan.onTap] でブラウザを開き、それ以外は通常テキスト。
  List<InlineSpan> _buildSpans(BuildContext context) {
    final spans = <InlineSpan>[];
    if (text.isEmpty) {
      return [
        const TextSpan(
          text: '-',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ];
    }

    // 行間（height）を 1.5 に設定し、固定行高に収まるようにする。
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      fontSize: 12,
      height: 1.5,
    );
    final normalStyle = const TextStyle(fontSize: 12, height: 1.5);

    final regex = RegExp(r'https?://[^\s]+');
    var last = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start), style: normalStyle));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: linkStyle,
          recognizer: _UrlTapGestureRecognizer(url),
        ),
      );
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: normalStyle));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          // 上下 4px + 左右 5px（隣接セルとの間隔）のマージンを取る。
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Text.rich(
            TextSpan(children: _buildSpans(context)),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// http(s) リンクをタップした際にブラウザで開く [TapGestureRecognizer]。
class _UrlTapGestureRecognizer extends TapGestureRecognizer {
  final String url;

  _UrlTapGestureRecognizer(this.url) {
    onTap = _open;
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // 起動できない環境（Web 未対応等）では何もしない。
    }
  }
}

/// 1 行分の表示データをまとめる。
class _RowData {
  final NoteObject object;
  final int number;
  final List<String> groupsFor;
  final List<String> from;
  final List<String> to;

  const _RowData({
    required this.object,
    required this.number,
    required this.groupsFor,
    required this.from,
    required this.to,
  });
}

/// ソート可能なカラムヘッダ（ラベル + ソートアイコン）。
///
/// [sortCol] が null の場合はソート不可（アイコンなし）。
/// 現在ソートに使用しているカラムはアイコンを主色で強調する。
class _SortHeader extends StatelessWidget {
  final String label;
  final _SortColumn? sortCol;
  final bool isSorted;
  final IconData icon;
  final VoidCallback? onTap;

  const _SortHeader({
    required this.label,
    this.sortCol,
    required this.isSorted,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kCellGap / 2),
        child: Row(
          // 固定幅の親に収まり、ラベルがはみ出た場合は省略記号で切る。
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            if (sortCol != null) ...[
              const SizedBox(width: 4),
              Icon(
                icon,
                size: 14,
                color: isSorted ? theme.colorScheme.primary : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 複数選択可能なドロップダウン（チェックボックス付き）。
///
/// - タップでメニューが開き、各オプションのチェックボックスで選択をトグルする。
/// - 選択中が 0 個なら「すべて」、1 個ならその名称、2 個以上なら「N 件選択」を表示。
class _MultiSelectDropdown<T> extends StatelessWidget {
  final String label;
  final List<T> options;
  final Set<T> selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onToggle;

  const _MultiSelectDropdown({
    required this.label,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
  });

  String _summary() {
    if (selected.isEmpty) return '$label: すべて';
    if (selected.length == 1) {
      final first = selected.first;
      return labelOf(first);
    }
    return '$label: ${selected.length} 件選択';
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final option in options)
          InkWell(
            onTap: () => onToggle(option),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: selected.contains(option),
                    onChanged: (_) => onToggle(option),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(labelOf(option), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
      ],
      builder: (context, menuController, child) {
        return InputDecorator(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
          child: InkWell(
            onTap: menuController.open,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    _summary(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
