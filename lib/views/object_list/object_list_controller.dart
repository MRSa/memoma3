import 'package:flutter/material.dart';

import '../../models/connection.dart';
import '../../models/note_object.dart';
import 'object_list_ui.dart';

/// オブジェクト一覧画面のロジック（フィルタ / ソート / CSV 生成）。
///
/// Flutter UI や Riverpod に依存しない純 Dart クラスとして実装し、
/// 単体テストを容易にする。画面側（[ObjectListScreen]）はフィルタ・ソート
/// 状態の変更時に `setState` を呼び、再描画を行う。
class ObjectListController {
  // ---------------------------------------------------------------------------
  // 状態
  // ---------------------------------------------------------------------------

  /// 名称フィルタのテキスト。
  String _filterText = '';

  /// 形状フィルタ（空 = すべて）。複数選択可能。
  final Set<NoteShape> _shapeFilters = {};

  /// 強調フィルタ（空 = すべて）。複数選択可能。
  final Set<Emphasis> _emphasisFilters = {};

  /// 現在のソート対象カラムと方向。
  /// デフォルトは No.（番号）降順でソートし、最新（最大の No.）が先頭に来る。
  SortColumn _sortColumn = SortColumn.number;
  SortDirection _sortDirection = SortDirection.descending;

  String get filterText => _filterText;
  Set<NoteShape> get shapeFilters => _shapeFilters;
  Set<Emphasis> get emphasisFilters => _emphasisFilters;
  SortColumn get sortColumn => _sortColumn;
  SortDirection get sortDirection => _sortDirection;

  // ---------------------------------------------------------------------------
  // フィルタ
  // ---------------------------------------------------------------------------

  /// 名称フィルタのテキストを設定する。
  void setFilterText(String value) {
    _filterText = value;
  }

  /// 形状フィルタをトグルする。
  void toggleShapeFilter(NoteShape shape) {
    if (!_shapeFilters.add(shape)) _shapeFilters.remove(shape);
  }

  /// 強調フィルタをトグルする。
  void toggleEmphasisFilter(Emphasis emphasis) {
    if (!_emphasisFilters.add(emphasis)) _emphasisFilters.remove(emphasis);
  }

  /// 全フィルタをクリアする。
  void clearFilters() {
    _filterText = '';
    _shapeFilters.clear();
    _emphasisFilters.clear();
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

  // ---------------------------------------------------------------------------
  // ソート
  // ---------------------------------------------------------------------------

  /// カラムヘッダのタップでソートを切り替える。
  void onSort(SortColumn column) {
    if (_sortColumn == column) {
      _sortDirection = _sortDirection == SortDirection.ascending
          ? SortDirection.descending
          : SortDirection.ascending;
    } else {
      _sortColumn = column;
      _sortDirection = SortDirection.ascending;
    }
  }

  /// ソートインジケータのアイコンを返す。
  IconData sortIcon(SortColumn column) {
    if (_sortColumn != column) return Icons.arrow_upward;
    return _sortDirection == SortDirection.ascending
        ? Icons.arrow_upward
        : Icons.arrow_downward;
  }

  /// 現在ソートに使用しているカラムかどうか。
  bool isSortedColumn(SortColumn column) => _sortColumn == column;

  /// ソートキーを返す。
  String _sortKey(
    NoteObject o,
    List<Connection> connections,
    List<GroupFrame> groups,
    Map<String, NoteObject> map,
    List<NoteObject> allObjects,
  ) {
    switch (_sortColumn) {
      case SortColumn.number:
        // 番号は全オブジェクト（フィルタ前）中の位置。数値としてソートするため
        // 桁数を揃えた文字列を返す。
        final index = allObjects.indexWhere((a) => a.id == o.id);
        return (index < 0 ? 0 : index).toString().padLeft(6, '0');
      case SortColumn.name:
        return o.label;
      case SortColumn.shape:
        return o.shape.displayName;
      case SortColumn.color:
        return o.color.toARGB32().toRadixString(16);
      case SortColumn.emphasis:
        return o.emphasis.displayName;
      case SortColumn.group:
        return groupNamesFor(o.id, groups).join(',');
      case SortColumn.connection:
        return '${connectionsFrom(o.id, connections, map).join(',')}|${connectionsTo(o.id, connections, map).join(',')}';
      case SortColumn.x:
        return o.position.dx.toStringAsFixed(0);
      case SortColumn.y:
        return o.position.dy.toStringAsFixed(0);
      case SortColumn.scale:
        // 0.5〜4.0 の 0.5 刻みなので、1 桁小数の文字列で数値順にソートできる。
        return o.scale.toStringAsFixed(1);
    }
  }

  /// ソート済みオブジェクト一覧を返す。
  /// [allObjects] はフィルタ前の全オブジェクト（番号・No. ソート用）。
  List<NoteObject> _sortedObjects(
    List<NoteObject> objects,
    List<Connection> connections,
    List<GroupFrame> groups,
    List<NoteObject> allObjects,
  ) {
    final map = objectMap(objects);
    final list = List<NoteObject>.from(objects);
    list.sort((a, b) {
      final ka = _sortKey(a, connections, groups, map, allObjects);
      final kb = _sortKey(b, connections, groups, map, allObjects);
      final result = ka.compareTo(kb);
      return _sortDirection == SortDirection.ascending ? result : -result;
    });
    return list;
  }

  /// フィルタ済み・ソート済みオブジェクト一覧を返す。
  /// [allObjects] はフィルタ前の全オブジェクト（番号・No. ソート用）。
  List<NoteObject> filteredAndSorted(
    List<NoteObject> allObjects,
    List<Connection> connections,
    List<GroupFrame> groups,
  ) {
    return _sortedObjects(
      _filteredObjects(allObjects),
      connections,
      groups,
      allObjects,
    );
  }

  // ---------------------------------------------------------------------------
  // データ集約ヘルパー
  // ---------------------------------------------------------------------------

  /// ID → オブジェクト のマップを構築する。
  Map<String, NoteObject> objectMap(List<NoteObject> objects) {
    final map = <String, NoteObject>{};
    for (final o in objects) {
      map[o.id] = o;
    }
    return map;
  }

  /// オブジェクトが属するグループ名称の一覧を返す。
  List<String> groupNamesFor(String objectId, List<GroupFrame> groups) {
    final names = <String>[];
    for (final g in groups) {
      if (g.memberIds.contains(objectId)) {
        names.add(g.name.isNotEmpty ? g.name : g.id);
      }
    }
    return names;
  }

  /// オブジェクトが「発端（from）」になっている接続先の名称一覧。
  List<String> connectionsFrom(
    String objectId,
    List<Connection> connections,
    Map<String, NoteObject> map,
  ) {
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
  List<String> connectionsTo(
    String objectId,
    List<Connection> connections,
    Map<String, NoteObject> map,
  ) {
    final names = <String>[];
    for (final c in connections) {
      if (c.targetId == objectId) {
        final source = map[c.sourceId];
        names.add(source != null && source.label.isNotEmpty ? source.label : c.sourceId);
      }
    }
    return names;
  }

  // ---------------------------------------------------------------------------
  // CSV エクスポート
  // ---------------------------------------------------------------------------

  /// CSV のフィールドをエスケープする（カンマ・改行・引用符を含む場合）。
  String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// 一覧データを Excel で読める CSV 文字列（UTF-8 BOM 付き）を生成する。
  String buildCsv(
    List<NoteObject> objects,
    List<Connection> connections,
    List<GroupFrame> groups,
  ) {
    final map = objectMap(objects);
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
        colorToHex(o.color),
        groupNamesFor(o.id, groups).join(' / '),
        connectionsFrom(o.id, connections, map).join(' / '),
        connectionsTo(o.id, connections, map).join(' / '),
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
  String colorToHex(Color color) {
    final hex = color.toARGB32() & 0xFFFFFF;
    return '#${hex.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
