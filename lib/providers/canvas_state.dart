import 'dart:convert';

import '../models/connection.dart';
import '../models/note_object.dart';

/// キャンバス全体の不変な状態モデル。
///
/// - `objects`: キャンバス上の全オブジェクト（描画順＝Z順、末尾が最前面）。
/// - `connections`: オブジェクト間を接続する線の一覧。
/// - `groupFrames`: グループ枠の一覧。
/// - `selectedId`: 現在選択されているオブジェクトの ID（未選択なら null）。
/// - `history`: Undo 用の履歴スタック（直近の最大 [maxHistory] 件のみ保持）。
/// - `redoStack`: Redo 用のスタック。Undo で退避した状態を保持し、
///   Redo で復元する。新しい操作が行われた場合はクリアされる。
class CanvasState {
  final List<NoteObject> objects;
  final List<Connection> connections;
  final List<GroupFrame> groupFrames;
  final String? selectedId;
  final List<CanvasState> history;

  /// Redo 用のスタック（Undo で退避した状態）。
  final List<CanvasState> redoStack;

  /// 保持する Undo / Redo 履歴の最大件数。
  final int maxHistory;

  const CanvasState({
    this.objects = const [],
    this.connections = const [],
    this.groupFrames = const [],
    this.selectedId,
    this.history = const [],
    this.redoStack = const [],
    this.maxHistory = 30,
  });

  /// この状態が「直近の状態」として履歴に積まれるか否か。
  /// history の末尾が自分自身と同一なら積み替え不要。
  bool _isSameAsHistoryTop(CanvasState other) {
    if (other.objects.length != objects.length) return false;
    for (var i = 0; i < objects.length; i++) {
      if (objects[i].id != other.objects[i].id) return false;
      if (objects[i].position != other.objects[i].position) return false;
      if (objects[i].size != other.objects[i].size) return false;
      if (objects[i].content != other.objects[i].content) return false;
      if (objects[i].label != other.objects[i].label) return false;
      if (objects[i].detail != other.objects[i].detail) return false;
      if (objects[i].color != other.objects[i].color) return false;
      if (objects[i].shape != other.objects[i].shape) return false;
      if (objects[i].labelColor != other.objects[i].labelColor) return false;
      if (objects[i].descriptionColor != other.objects[i].descriptionColor) return false;
      if (objects[i].isSelected != other.objects[i].isSelected) return false;
    }
    if (other.connections.length != connections.length) return false;
    for (var i = 0; i < connections.length; i++) {
      final a = connections[i];
      final b = other.connections[i];
      if (a.id != b.id || a.sourceId != b.sourceId || a.targetId != b.targetId) return false;
      if (a.lineType != b.lineType || a.lineShape != b.lineShape) return false;
    }
    if (other.groupFrames.length != groupFrames.length) return false;
    for (var i = 0; i < groupFrames.length; i++) {
      final a = groupFrames[i];
      final b = other.groupFrames[i];
      if (a.id != b.id) return false;
      if (a.memberIds.length != b.memberIds.length) return false;
      for (var j = 0; j < a.memberIds.length; j++) {
        if (a.memberIds[j] != b.memberIds[j]) return false;
      }
      if (a.name != b.name) return false;
      if (a.description != b.description) return false;
      if (a.color != b.color) return false;
    }
    return selectedId == other.selectedId;
  }

  /// 現在の状態を履歴スタックに1件積む。
  /// すでに末尾が同一状態なら追加しない。
  ///
  /// 新しい操作が行われたため、Redo スタックはクリアされる。
  CanvasState pushHistory(CanvasState state) {
    final historyList = List<CanvasState>.from(history);
    if (historyList.isNotEmpty && historyList.last._isSameAsHistoryTop(state)) {
      return CanvasState(
        objects: state.objects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: state.selectedId,
        history: historyList,
        redoStack: const [],
        maxHistory: maxHistory,
      );
    }
    historyList.add(state);
    if (historyList.length > maxHistory) {
      historyList.removeRange(0, historyList.length - maxHistory);
    }
    return CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: historyList,
      redoStack: const [],
      maxHistory: maxHistory,
    );
  }

  /// 1つ戻る（Undo）。戻り先がない場合は自身を返す。
  ///
  /// 退避した現在の状態は Redo スタックに積まれるため、[redo] で復元できる。
  CanvasState undo() {
    if (history.isEmpty) return this;
    final previous = history.last;
    final newRedo = List<CanvasState>.from(redoStack)..add(this);
    if (newRedo.length > maxHistory) {
      newRedo.removeRange(0, newRedo.length - maxHistory);
    }
    return CanvasState(
      objects: previous.objects,
      connections: previous.connections,
      groupFrames: previous.groupFrames,
      selectedId: previous.selectedId,
      history: List<CanvasState>.from(history)..removeLast(),
      redoStack: newRedo,
      maxHistory: maxHistory,
    );
  }

  /// 1つ進む（Redo）。進む先がない場合は自身を返す。
  ///
  /// [undo] で退避した状態を復元する。
  CanvasState redo() {
    if (redoStack.isEmpty) return this;
    final next = redoStack.last;
    final newHistory = List<CanvasState>.from(history)..add(this);
    if (newHistory.length > maxHistory) {
      newHistory.removeRange(0, newHistory.length - maxHistory);
    }
    return CanvasState(
      objects: next.objects,
      connections: next.connections,
      groupFrames: next.groupFrames,
      selectedId: next.selectedId,
      history: newHistory,
      redoStack: List<CanvasState>.from(redoStack)..removeLast(),
      maxHistory: maxHistory,
    );
  }

  /// 指定した ID のオブジェクトを返す。
  NoteObject? getObject(String id) {
    for (final obj in objects) {
      if (obj.id == id) return obj;
    }
    return null;
  }

  /// 指定した ID のグループ枠を返す。
  GroupFrame? getGroupFrame(String id) {
    for (final frame in groupFrames) {
      if (frame.id == id) return frame;
    }
    return null;
  }

  /// 指定した ID の接続線を返す。
  Connection? getConnection(String id) {
    for (final connection in connections) {
      if (connection.id == id) return connection;
    }
    return null;
  }

  /// 指定したオブジェクトに接続されている全接続線を返す。
  List<Connection> getConnectionsFor(String id) {
    return connections.where((c) => c.sourceId == id || c.targetId == id).toList();
  }

  /// データ（オブジェクト一覧）を複製して返す。
  List<NoteObject> copyObjects() => List<NoteObject>.from(objects);

  /// JSON 文字列へエクスポートするためのデータを変換する。
  ///
  /// 構造は `{ "objects": [...], "connections": [...], "groups": [...] }`。
  String toJson() {
    final objectList = objects.map((o) => o.toJson()).toList();
    final connectionList = connections.map((c) => c.toJson()).toList();
    final groupList = groupFrames.map((g) => g.toJson()).toList();
    return _encodeTriple(objectList, connectionList, groupList);
  }

  /// JSON 文字列から CanvasState を復元する。
  ///
  /// 旧形式（オブジェクト配列のみ）にも後方互換性を持つ。
  factory CanvasState.fromJson(String jsonString, {int maxHistory = 30}) {
    final decoded = _decodeTriple(jsonString);
    final objects = (decoded[0] as List)
        .map<NoteObject>((e) => NoteObject.fromJson(e as Map<String, dynamic>))
        .toList();
    final connections = (decoded[1] as List)
        .map<Connection>((e) => Connection.fromJson(e as Map<String, dynamic>))
        .toList();
    final groupFrames = (decoded[2] as List)
        .map<GroupFrame>((e) => GroupFrame.fromJson(e as Map<String, dynamic>))
        .toList();
    return CanvasState(
      objects: objects,
      connections: connections,
      groupFrames: groupFrames,
      maxHistory: maxHistory,
    );
  }

  /// JSON エンコーダの取得（ライブラリ間で互換性を取るためラップ）。
  static String _encodeTriple(List<dynamic> objects, List<dynamic> connections, List<dynamic> groups) {
    return const JsonEncoder.withIndent('  ').convert({
      'objects': objects,
      'connections': connections,
      'groups': groups,
    });
  }

  /// JSON デンコーダの取得。旧形式（単一のオブジェクト配列）にも対応する。
  static List<dynamic> _decodeTriple(String jsonString) {
    final trimmed = jsonString.trim();
    // 旧形式：ルートが配列。
    if (trimmed.startsWith('[')) {
      final list = const JsonDecoder().convert(jsonString) as List;
      return [list, const [], const []];
    }
    // 新形式：オブジェクト。
    final decoded = const JsonDecoder().convert(jsonString) as Map<String, dynamic>;
    return [
      decoded['objects'] as List? ?? const [],
      decoded['connections'] as List? ?? const [],
      decoded['groups'] as List? ?? const [],
    ];
  }
}