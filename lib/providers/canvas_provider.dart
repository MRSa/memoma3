import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/background_config.dart';
import '../models/connection.dart';
import '../models/note_object.dart';
import '../services/background_persistence_service.dart';
import 'canvas_state.dart';

/// IDの一意性を保証するための静的カウンタ。
///
/// [DateTime.now().microsecondsSinceEpoch] だけでは、同一マイクロ秒内に
/// 複数回IDを生成すると（例: connectSelected がループで連続呼び出し、
/// 連続してグループ化操作）IDが重複する。そのためカウンタを併用して
/// 一意性を確保する。
int _idCounter = 0;

/// 一意なIDを生成する。[prefix] で種別（conn / group 等）を指定する。
String _generateId(String prefix) {
  _idCounter++;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
}

/// 一意な接続線IDを生成する。
String _generateConnectionId() => _generateId('conn');

/// 一意なグループIDを生成する。
String _generateGroupId() => _generateId('group');

/// 整列モード。
enum AlignMode {
  /// 左揃え。
  left,
  /// 右揃え。
  right,
  /// 上揃え。
  top,
  /// 下揃え。
  bottom,
  /// 等間隔（横幅 / X 方向）。
  distributeHorizontal,
  /// 等間隔（縦幅 / Y 方向）。
  distributeVertical,
}

/// キャンバスの状態（オブジェクト一覧・選択・Undo履歴）を管理する Notifier。
///
/// ドラッグ中は [localDraftPositions] に表示用のローカル座標を持ち、
/// ドラッグ終了時（PanEnd）にのみ Undo 履歴へ状態を保存する。
class CanvasNotifier extends Notifier<CanvasState> {
  @override
  CanvasState build() => const CanvasState();

  /// ドラッグ中のオブジェクトに対して、描画専用のローカル座標を一時的に保持する。
  /// キーはオブジェクトの ID。ドラッグ終了時に [objects] に反映される。
  final Map<String, Offset> localDraftPositions = {};

  /// ドラッグ開始地点のキャンバス座標を一時的に保持する。
  final Map<String, Offset> dragStartCanvas = {};

  /// ドラッグ開始時のオブジェクトの位置（Undo 履歴に正しく積むため）。
  /// キーはオブジェクトの ID。[resetDraft] で設定され、
  /// [endDrag] / [cancelDrag] で削除される。
  final Map<String, Offset> dragStartPositions = {};

  /// 直近に追加されたオブジェクトの ID（UI 側で即座に選択状態を反映するため）。
  String? lastAddedId;

  /// 最後に設定された形状。新規オブジェクト作成時はこの形状をデフォルトとする。
  NoteShape lastShape = NoteShape.rectangle;

  /// 最後に設定された形状を更新する。
  void updateLastShape(NoteShape shape) {
    lastShape = shape;
  }

  // ---------------------------------------------------------------------------
  // オブジェクト操作
  // ---------------------------------------------------------------------------

  /// キャンバス上に新しいオブジェクトを追加する。
  /// 追加前 の状態を Undo 履歴へ積む。
  void addObject(NoteObject object) {
    final newHistory = state.pushHistory(state);
    final newState = CanvasState(
      objects: [...state.objects, object],
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: object.id,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
    state = newState;
    lastAddedId = object.id;
  }

  /// オブジェクトの位置を更新する。
  /// [delta] はローカル座標空間（ズーム補正済み）での移動量。
  void updatePosition(String id, Offset delta) {
    final existing = state.getObject(id);
    if (existing == null) return;

    final base = state.objects.firstWhere((o) => o.id == id);
    final currentDraft = localDraftPositions[id] ?? base.position;
    final newPosition = Offset(
      currentDraft.dx + delta.dx,
      currentDraft.dy + delta.dy,
    );

    localDraftPositions[id] = newPosition;

    // ドラッグ中は描画専用として即座に反映する。
    final updated = base.copyWith(position: newPosition);
    final newObjects = List<NoteObject>.from(state.objects)
      ..[state.objects.indexWhere((o) => o.id == id)] = updated;

    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// ドラッグを終了し、ローカルドラフト座標を実オブジェクトへ反映して
  /// Undo 履歴へ保存する。
  ///
  /// [updatePosition] はドラッグ中に [state.objects] を直接更新するため、
  /// この時点の [state] は既にドラッグ後の位置を含む。そのため、履歴に積む
  /// 「操作前の状態」は、オブジェクトの位置をドラッグ開始位置
  /// （[dragStartPositions]）に戻した状態として再構築する。これにより、
  /// Undo で正しくドラッグ前の位置へ復元される。
  ///
  /// [pushHistory] が false の場合は履歴に積まない（グループドラッグでは
  /// [endGroupDrag] が一括で履歴を積むため）。
  void endDrag(String id, {bool pushHistory = true}) {
    final draft = localDraftPositions.remove(id);
    final startPos = dragStartPositions.remove(id);
    if (draft == null) return;

    final base = state.objects.firstWhere((o) => o.id == id);
    final updated = base.copyWith(position: draft);
    final newObjects = List<NoteObject>.from(state.objects)
      ..[state.objects.indexWhere((o) => o.id == id)] = updated;

    // 履歴を積まない場合（グループドラッグの一括処理）。
    if (!pushHistory) {
      state = CanvasState(
        objects: newObjects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: state.selectedId,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
      return;
    }

    // 位置が変化していない場合は履歴に積まない（見た目が変わらないため）。
    if (startPos != null && startPos == draft) {
      state = CanvasState(
        objects: newObjects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: state.selectedId,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
      return;
    }

    // 履歴に積む「操作前の状態」を構築する。
    // state.objects は既にドラッグ後の位置を含むため、
    // 開始位置（dragStartPositions）に戻した状態を履歴に積む。
    CanvasState preDragState = state;
    if (startPos != null) {
      final preObjects = List<NoteObject>.from(state.objects);
      final idx = preObjects.indexWhere((o) => o.id == id);
      if (idx != -1) {
        preObjects[idx] = preObjects[idx].copyWith(position: startPos);
      }
      preDragState = CanvasState(
        objects: preObjects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: state.selectedId,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
    }

    final newHistory = preDragState.pushHistory(preDragState);
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      redoStack: newHistory.redoStack,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// オブジェクトの位置を絶対座標 [position] に設定する。
  ///
  /// ドラッグ（相対移動）ではなく、一覧画面などから座標を直接指定して
  /// 移動するためのメソッド。変更がある場合のみ Undo 履歴へ積む。
  void setPosition(String id, Offset position) {
    final existing = state.getObject(id);
    if (existing == null) return;
    if (existing.position == position) return;

    final updated = existing.copyWith(position: position);
    final newObjects = List<NoteObject>.from(state.objects)
      ..[state.objects.indexWhere((o) => o.id == id)] = updated;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// ドラッグをキャンセルした場合はドラフトを破棄する。
  void cancelDrag(String id) {
    localDraftPositions.remove(id);
    dragStartPositions.remove(id);
  }

  /// ドラッグ開始時に、ローカルドラフト座標をオブジェクトの現在の
  /// 実オブジェクト座標へリセットする。
  ///
  /// 前回のドラッグや失敗したジェスチャが残したドラフトオフセットを
  /// 排除し、移動量を実位置からの相対量として安全に計算するための
  /// 処理である。これにより、画面外から移動してきたオブジェクトを触った
  /// ときにドラフトオフセットが二重に加算されて描画位置がズレる
  /// 問題を防ぐ。
  void resetDraft(String id) {
    final base = state.objects.firstWhere((o) => o.id == id);
    localDraftPositions[id] = base.position;
    // ドラッグ開始時の位置を記録する（Undo 履歴に正しく積むため）。
    dragStartPositions[id] = base.position;
  }

  /// グループの全メンバーのドラフトを開始位置へリセットする。
  ///
  /// グループ枠のドラッグ開始時に呼び、全メンバーの開始位置を
  /// [dragStartPositions] に記録する。これにより [endGroupDrag] で
  /// 各メンバーの Undo 履歴が正しく積まれる。
  void resetGroupDrafts(String groupId) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;
    for (final memberId in frame.memberIds) {
      final obj = state.getObject(memberId);
      if (obj == null) continue;
      localDraftPositions[memberId] = obj.position;
      dragStartPositions[memberId] = obj.position;
    }
  }

  /// 全オブジェクトをドラフト状態からクリアする。
  void clearLocalDrafts() {
    localDraftPositions.clear();
    dragStartPositions.clear();
  }

  /// 指定したオブジェクトを最前面（リスト末尾）へ移動する。
  void bringToFront(String id) {
    final index = state.objects.indexWhere((o) => o.id == id);
    if (index == -1) return;

    final moved = state.objects[index];
    final newObjects = List<NoteObject>.from(state.objects)..removeAt(index);
    newObjects.add(moved);

    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// オブジェクトを選択する。もう一度タップで選択解除する。
  void selectObject(String? id) {
    if (state.selectedId == id) {
      // 選択解除
      _setAllSelected(false);
      state = CanvasState(
        objects: state.objects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: null,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
      return;
    }

    _setAllSelected(false);
    if (id != null) {
      final updated = state.objects
          .map((o) => o.id == id ? o.copyWith(isSelected: true) : o)
          .toList();
      state = CanvasState(
        objects: updated,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: id,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
    }
  }

  /// 指定したオブジェクトの選択状態をトグルする（複数選択用）。
  /// 既に選択されていれば解除、未選択であれば追加する。
  /// 他のオブジェクトの選択状態は維持される。
  void toggleSelect(String id) {
    final target = state.getObject(id);
    if (target == null) return;

    final updated = state.objects
        .map((o) => o.id == id ? o.copyWith(isSelected: !o.isSelected) : o)
        .toList();

    // 選択中のオブジェクトが1つもいなければ selectedId は null。
    // 1つ以上あれば、最後にトグルしたオブジェクトを selectedId として保持する。
    final selectedCount = updated.where((o) => o.isSelected).length;
    final newSelectedId = selectedCount > 0 ? id : null;

    state = CanvasState(
      objects: updated,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: newSelectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// 選択中のオブジェクトの数を返す。
  int get selectedCount => state.objects.where((o) => o.isSelected).length;

  void _setAllSelected(bool selected) {
    final updated = state.objects.map((o) => o.copyWith(isSelected: selected)).toList();
    state = CanvasState(
      objects: updated,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// 選択中のオブジェクトの情報を編集する。
  ///
  /// [id] のオブジェクトの shape / label / detail / color / labelColor を
  /// 更新し、Undo 履歴へ積む。[id] が存在しない場合は何もしない。
  void editObject({
    required String id,
    NoteShape? shape,
    String? label,
    String? detail,
    String? content,
    Color? color,
    Emphasis? emphasis,
    Color? labelColor,
    Color? descriptionColor,
  }) {
    final existing = state.getObject(id);
    if (existing == null) return;

    final updated = existing.copyWith(
      shape: shape,
      label: label,
      detail: detail,
      content: content,
      color: color,
      emphasis: emphasis,
      labelColor: labelColor,
      descriptionColor: descriptionColor,
    );
    // 形状が変更された場合は、次回新規作成時のデフォルト形状として保持する。
    if (shape != null) {
      lastShape = shape;
    }
    final newObjects = List<NoteObject>.from(state.objects)
      ..[state.objects.indexWhere((o) => o.id == id)] = updated;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 選択中のオブジェクトを削除する（複数選択対応）。
  void deleteSelected() {
    if (selectedCount == 0) return;
    final newHistory = state.pushHistory(state);
    final newObjects = state.objects.where((o) => !o.isSelected).toList();
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: null,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  // ---------------------------------------------------------------------------
  // オブジェクト整列機能
  // ---------------------------------------------------------------------------

  /// 座標を [step] の倍数に丸める。
  double _snap(double value, double step) {
    if (step <= 0) return value;
    return (value / step).round() * step;
  }

  /// 選択中のオブジェクトの X 座標・Y 座標を [step]（既定 10）の倍数に
  /// 揃える（オブジェクト整列機能）。
  ///
  /// 各オブジェクトの左上座標（position）を [step] の倍数に丸めることで、
  /// 配置位置を揃えられる。選択中のオブジェクトが 1 個以上必要。
  /// 変更がある場合のみ Undo 履歴へ積む。
  void alignSelectedToStep({double step = 10.0}) {
    if (selectedCount == 0) return;

    var changed = false;
    final newObjects = List<NoteObject>.from(state.objects);
    for (var i = 0; i < newObjects.length; i++) {
      final obj = newObjects[i];
      if (!obj.isSelected) continue;
      final snappedX = _snap(obj.position.dx, step);
      final snappedY = _snap(obj.position.dy, step);
      if (snappedX != obj.position.dx || snappedY != obj.position.dy) {
        newObjects[i] = obj.copyWith(
          position: Offset(snappedX, snappedY),
        );
        changed = true;
      }
    }

    if (!changed) return;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 選択中のオブジェクトを [mode] で整列する。
  ///
  /// - 選択が 1 個：[alignSelectedToStep] と同じく X/Y を 10 の倍数に整列する。
  /// - 選択が 2 個以上：[AlignMode] ごとに以下のように整列する。
  ///   - [AlignMode.left]   : 一番左の左端を 10 の倍数に整えて全 X を揃える。
  ///   - [AlignMode.right]  : 一番右の右端を 10 の倍数に整えて全 X を揃える。
  ///   - [AlignMode.top]    : 一番上の上端を 10 の倍数に整えて全 Y を揃える。
  ///   - [AlignMode.bottom] : 一番下の下端を 10 の倍数に整えて全 Y を揃える。
  ///   - [AlignMode.distributeHorizontal] : 左右の端を基準に X を等間隔に配置。
  ///   - [AlignMode.distributeVertical]   : 上下の端を基準に Y を等間隔に配置。
  ///
  /// 変更がある場合のみ Undo 履歴へ積む。
  void alignSelected(AlignMode mode) {
    final selected = state.objects.where((o) => o.isSelected).toList();
    if (selected.isEmpty) return;

    // 単一選択時は従来どおり X/Y を 10 の倍数に整列する。
    if (selected.length == 1) {
      alignSelectedToStep(step: 10.0);
      return;
    }

    const step = 10.0;
    final newObjects = List<NoteObject>.from(state.objects);
    final indexById = <String, int>{};
    for (var i = 0; i < newObjects.length; i++) {
      indexById[newObjects[i].id] = i;
    }

    switch (mode) {
      case AlignMode.left:
        final leftEdge = selected.map((o) => o.position.dx).reduce(min);
        final target = _snap(leftEdge, step);
        for (final o in selected) {
          final i = indexById[o.id]!;
          newObjects[i] = o.copyWith(position: Offset(target, o.position.dy));
        }
        break;
      case AlignMode.right:
        final rightEdge =
            selected.map((o) => o.position.dx + o.size.width).reduce(max);
        final target = _snap(rightEdge, step);
        for (final o in selected) {
          final i = indexById[o.id]!;
          newObjects[i] = o.copyWith(
            position: Offset(target - o.size.width, o.position.dy),
          );
        }
        break;
      case AlignMode.top:
        final topEdge = selected.map((o) => o.position.dy).reduce(min);
        final target = _snap(topEdge, step);
        for (final o in selected) {
          final i = indexById[o.id]!;
          newObjects[i] = o.copyWith(position: Offset(o.position.dx, target));
        }
        break;
      case AlignMode.bottom:
        final bottomEdge =
            selected.map((o) => o.position.dy + o.size.height).reduce(max);
        final target = _snap(bottomEdge, step);
        for (final o in selected) {
          final i = indexById[o.id]!;
          newObjects[i] = o.copyWith(
            position: Offset(o.position.dx, target - o.size.height),
          );
        }
        break;
      case AlignMode.distributeHorizontal:
        final sorted = [...selected]
          ..sort((a, b) => a.position.dx.compareTo(b.position.dx));
        final leftEdge = sorted.first.position.dx;
        final rightEdge =
            sorted.map((o) => o.position.dx + o.size.width).reduce(max);
        final totalWidth =
            sorted.fold<double>(0, (sum, o) => sum + o.size.width);
        final gap = (rightEdge - leftEdge - totalWidth) / (sorted.length - 1);
        var x = leftEdge;
        for (final o in sorted) {
          final i = indexById[o.id]!;
          newObjects[i] = o.copyWith(position: Offset(x, o.position.dy));
          x += o.size.width + gap;
        }
        break;
      case AlignMode.distributeVertical:
        final sorted = [...selected]
          ..sort((a, b) => a.position.dy.compareTo(b.position.dy));
        final topEdge = sorted.first.position.dy;
        final bottomEdge =
            sorted.map((o) => o.position.dy + o.size.height).reduce(max);
        final totalHeight =
            sorted.fold<double>(0, (sum, o) => sum + o.size.height);
        final gap = (bottomEdge - topEdge - totalHeight) / (sorted.length - 1);
        var y = topEdge;
        for (final o in sorted) {
          final i = indexById[o.id]!;
          newObjects[i] = o.copyWith(position: Offset(o.position.dx, y));
          y += o.size.height + gap;
        }
        break;
    }

    // 変更がある場合のみ Undo 履歴へ積む。
    var changed = false;
    for (var i = 0; i < newObjects.length; i++) {
      if (newObjects[i].position != state.objects[i].position) {
        changed = true;
        break;
      }
    }
    if (!changed) return;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  // ---------------------------------------------------------------------------
  // 接続線・グループ操作
  // ---------------------------------------------------------------------------

  /// 2つのオブジェクトを接続する新しい接続線を追加する。
  ///
  /// 既存の線と ID が重複しないよう生成する。[sourceId] と [targetId] が
  /// 既に接続されている場合は、新しい線を追加せず既存の線を返す。
  Connection? addConnection({
    required String sourceId,
    required String targetId,
    LineType lineType = LineType.normal,
    LineShape lineShape = LineShape.straight,
  }) {
    if (sourceId == targetId) return null;

    // 同一の接続が既に存在するか確認。
    final existing = state.connections.firstWhere(
      (c) =>
          (c.sourceId == sourceId && c.targetId == targetId) ||
          (c.sourceId == targetId && c.targetId == sourceId),
      orElse: () => const Connection(id: '', sourceId: '', targetId: ''),
    );
    if (existing.id.isNotEmpty) return existing;

    final newConnection = Connection(
      id: _generateConnectionId(),
      sourceId: sourceId,
      targetId: targetId,
      lineType: lineType,
      lineShape: lineShape,
    );
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: [...state.connections, newConnection],
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
    return newConnection;
  }

  /// 接続線の線種・形状・色を切り替える。
  void updateConnection({
    required String id,
    LineType? lineType,
    LineShape? lineShape,
    Color? color,
  }) {
    final existing = state.getConnection(id);
    if (existing == null) return;

    final updated = existing.copyWith(
      lineType: lineType ?? existing.lineType,
      lineShape: lineShape ?? existing.lineShape,
      color: color ?? existing.color,
    );
    final newConnections = List<Connection>.from(state.connections)
      ..[state.connections.indexWhere((c) => c.id == id)] = updated;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: newConnections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 接続線を解除する。その際、対象の線に接続されていたオブジェクトの
  /// 選択状態も解除する。
  void deleteConnection(String id) {
    final newConnections = state.connections.where((c) => c.id != id).toList();
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: newConnections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 指定した [id] のオブジェクトを削除する。
  ///
  /// 同時に、そのオブジェクトに接続されていた接続線と、
  /// 含まれていたグループ枠も削除する。
  void deleteObject(String id) {
    final newObjects = state.objects.where((o) => o.id != id).toList();
    final newConnections = state.connections
        .where((c) => c.sourceId != id && c.targetId != id)
        .toList();
    final newGroups = state.groupFrames
        .where((g) => !g.memberIds.contains(id))
        .toList();
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: newObjects,
      connections: newConnections,
      groupFrames: newGroups,
      selectedId: state.selectedId == id ? null : state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 全オブジェクト（および接続線・グループ枠）を削除する。
  void deleteAllObjects() {
    if (state.objects.isEmpty) return;
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: const [],
      connections: const [],
      groupFrames: const [],
      selectedId: null,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 選択中の全オブジェクトを結ぶ接続線を追加する。
  ///
  /// 選択中没有の場合は何もしない。
  void connectSelected({
    LineType lineType = LineType.normal,
    LineShape lineShape = LineShape.straight,
  }) {
    final selectedIds = state.objects.where((o) => o.isSelected).map((o) => o.id).toList();
    if (selectedIds.length < 2) return;

    final newConnections = List<Connection>.from(state.connections);
    for (var i = 0; i < selectedIds.length; i++) {
      for (var j = i + 1; j < selectedIds.length; j++) {
        final created = addConnection(
          sourceId: selectedIds[i],
          targetId: selectedIds[j],
          lineType: lineType,
          lineShape: lineShape,
        );
        if (created != null) {
          newConnections.add(created);
        }
      }
    }

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: newConnections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 指定したオブジェクト群を囲むグループ枠を作成する。
  ///
  /// [memberIds] のオブジェクトが1つ以上必要。既存のグループ枠と
  /// メンバーが完全に一致する場合は新しい枠を作らない。
  GroupFrame? createGroup(List<String> memberIds) {
    if (memberIds.isEmpty) return null;
    final uniqueIds = memberIds.toSet().toList();

    // 既存の枠と完全一致するか確認。
    final existing = state.groupFrames.firstWhere(
      (g) =>
          g.memberIds.length == uniqueIds.length &&
          g.memberIds.toSet().containsAll(uniqueIds.toSet()) &&
          uniqueIds.toSet().containsAll(g.memberIds.toSet()),
      orElse: () => const GroupFrame(id: '', memberIds: []),
    );
    if (existing.id.isNotEmpty) return existing;

    final newGroup = GroupFrame(
      id: _generateGroupId(),
      memberIds: uniqueIds,
    );
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: [...state.groupFrames, newGroup],
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
    return newGroup;
  }

  /// グループ枠を解除する。枠に属していたオブジェクトの選択状態も解除する。
  void deleteGroup(String groupId) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;

    final newGroups = state.groupFrames.where((g) => g.id != groupId).toList();
    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: newGroups,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// グループ枠の名称・説明・枠線色を更新する。
  void updateGroup({
    required String id,
    String? name,
    String? description,
    Color? color,
  }) {
    final existing = state.getGroupFrame(id);
    if (existing == null) return;

    final updated = existing.copyWith(
      name: name ?? existing.name,
      description: description ?? existing.description,
      color: color ?? existing.color,
    );
    final newGroups = List<GroupFrame>.from(state.groupFrames)
      ..[state.groupFrames.indexWhere((g) => g.id == id)] = updated;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: newGroups,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// 選択中のオブジェクトを新しいグループ枠へ追加（または統合）する。
  void addToGroup({required String groupId, required String objectId}) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;
    if (frame.memberIds.contains(objectId)) return;

    final newMemberIds = [...frame.memberIds, objectId];
    final updated = frame.copyWith(memberIds: newMemberIds);
    final newGroups = List<GroupFrame>.from(state.groupFrames)
      ..[state.groupFrames.indexWhere((g) => g.id == groupId)] = updated;

    final newHistory = state.pushHistory(state);
    state = CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: newGroups,
      selectedId: state.selectedId,
      history: newHistory.history,
      maxHistory: newHistory.maxHistory,
    );
  }

  /// グループ枠を構成する全オブジェクトを、キャンバス座標空間で
  /// [delta] だけ同時に移動する。
  ///
  /// [groupId] に属していないオブジェクトは移動しない。
  void moveGroup(String groupId, Offset delta) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;

    final newObjects = List<NoteObject>.from(state.objects);
    for (final memberId in frame.memberIds) {
      final index = newObjects.indexWhere((o) => o.id == memberId);
      if (index == -1) continue;
      final base = state.objects[index];
      final currentDraft = localDraftPositions[memberId] ?? base.position;
      final newPosition = Offset(
        currentDraft.dx + delta.dx,
        currentDraft.dy + delta.dy,
      );
      localDraftPositions[memberId] = newPosition;
      newObjects[index] = base.copyWith(position: newPosition);
    }

    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// グループ枠のドラッグを終了し、全メンバーのドラフト座標を実オブジェクトへ反映する。
  ///
  /// 全メンバーのドラッグ開始位置（[dragStartPositions]）をまとめて記録し、
  /// 履歴には「全メンバーが開始位置にある状態」を 1 件だけ積む。
  /// これにより、Undo でグループ全体がドラッグ前の位置へ一括復元される。
  void endGroupDrag(String groupId) {
    final frame = state.getGroupFrame(groupId);
    if (frame == null) return;

    // 全メンバーのドラフト位置と開始位置を収集する。
    final drafts = <String, Offset>{};
    final starts = <String, Offset>{};
    var anyChanged = false;
    for (final memberId in frame.memberIds) {
      final draft = localDraftPositions[memberId];
      if (draft == null) continue;
      drafts[memberId] = draft;
      final start = dragStartPositions[memberId];
      if (start != null) {
        starts[memberId] = start;
        if (start != draft) anyChanged = true;
      }
    }
    if (drafts.isEmpty) return;

    // 全メンバーのドラフト位置を実オブジェクトへ反映する。
    final newObjects = List<NoteObject>.from(state.objects);
    for (final entry in drafts.entries) {
      final idx = newObjects.indexWhere((o) => o.id == entry.key);
      if (idx == -1) continue;
      newObjects[idx] = newObjects[idx].copyWith(position: entry.value);
    }

    // 位置が変化していない場合は履歴に積まない。
    if (!anyChanged) {
      for (final memberId in drafts.keys) {
        localDraftPositions.remove(memberId);
        dragStartPositions.remove(memberId);
      }
      state = CanvasState(
        objects: newObjects,
        connections: state.connections,
        groupFrames: state.groupFrames,
        selectedId: state.selectedId,
        history: state.history,
        redoStack: state.redoStack,
        maxHistory: state.maxHistory,
      );
      return;
    }

    // 履歴に積む「操作前の状態」を構築する（全メンバーを開始位置に戻す）。
    final preObjects = List<NoteObject>.from(state.objects);
    for (final entry in starts.entries) {
      final idx = preObjects.indexWhere((o) => o.id == entry.key);
      if (idx == -1) continue;
      preObjects[idx] = preObjects[idx].copyWith(position: entry.value);
    }
    final preDragState = CanvasState(
      objects: preObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );

    final newHistory = preDragState.pushHistory(preDragState);

    // ドラフトをクリアする。
    for (final memberId in drafts.keys) {
      localDraftPositions.remove(memberId);
      dragStartPositions.remove(memberId);
    }

    state = CanvasState(
      objects: newObjects,
      connections: state.connections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: newHistory.history,
      redoStack: newHistory.redoStack,
      maxHistory: newHistory.maxHistory,
    );
  }

  // ---------------------------------------------------------------------------
  // Undo / Redo
  // ---------------------------------------------------------------------------

  /// 1つ戻る（Undo）。
  ///
  /// 退避した現在の状態は Redo スタックに積まれるため、[redo] で復元できる。
  void undo() {
    state = state.undo();
    clearLocalDrafts();
  }

  /// 1つ進む（Redo）。
  ///
  /// [undo] で退避した状態を復元する。進む先がない場合は何もしない。
  void redo() {
    state = state.redo();
    clearLocalDrafts();
  }

  // ---------------------------------------------------------------------------
  // データ読み込み / エクスポート
  // ---------------------------------------------------------------------------

  /// JSON 文字列から状態を復元する。現在の状態は破棄され、Undo 履歴には積まれない。
  void loadFromJson(String jsonString) {
    final restored = CanvasState.fromJson(jsonString, maxHistory: state.maxHistory);
    // 旧データで接続線ID・グループIDが重複している場合、一意なIDに再割り当てする。
    var fixed = _deduplicateConnectionIds(restored);
    fixed = _deduplicateGroupIds(fixed);
    clearLocalDrafts();
    state = fixed;
  }

  /// 接続線IDの重複を解消する。
  ///
  /// 旧バージョンのID生成では同一マイクロ秒内に複数生成するとIDが重複し、
  /// 結果として「1本選択すると全線が選択される」「解除すると全線が削除される」
  /// 問題が発生した。読み込み時に重複IDを検出し、一意なIDに再割り当てする。
  CanvasState _deduplicateConnectionIds(CanvasState state) {
    final seen = <String>{};
    final newConnections = <Connection>[];
    var changed = false;

    for (final conn in state.connections) {
      if (seen.contains(conn.id)) {
        // 重複しているため、一意なIDに再割り当てする。
        final newId = _generateConnectionId();
        newConnections.add(conn.copyWith(id: newId));
        seen.add(newId);
        changed = true;
      } else {
        newConnections.add(conn);
        seen.add(conn.id);
      }
    }

    if (!changed) return state;

    return CanvasState(
      objects: state.objects,
      connections: newConnections,
      groupFrames: state.groupFrames,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// グループ枠IDの重複を解消する。
  ///
  /// 旧バージョンのID生成では同一マイクロ秒内に複数生成するとIDが重複し、
  /// 結果として「1つ選択すると全グループが選択される」「解除すると全グループ
  /// が削除される」問題が発生した。読み込み時に重複IDを検出し、一意なIDに
  /// 再割り当てする。
  CanvasState _deduplicateGroupIds(CanvasState state) {
    final seen = <String>{};
    final newGroups = <GroupFrame>[];
    var changed = false;

    for (final group in state.groupFrames) {
      if (seen.contains(group.id)) {
        // 重複しているため、一意なIDに再割り当てする。
        final newId = _generateGroupId();
        newGroups.add(group.copyWith(id: newId));
        seen.add(newId);
        changed = true;
      } else {
        newGroups.add(group);
        seen.add(group.id);
      }
    }

    if (!changed) return state;

    return CanvasState(
      objects: state.objects,
      connections: state.connections,
      groupFrames: newGroups,
      selectedId: state.selectedId,
      history: state.history,
      redoStack: state.redoStack,
      maxHistory: state.maxHistory,
    );
  }

  /// 全オブジェクトを JSON 文字列として出力する。
  String exportToJson() {
    return state.toJson();
  }

  // ---------------------------------------------------------------------------
  // 生成ヘルパー
  // ---------------------------------------------------------------------------

  /// ランダムな色と形状で新しいオブジェクトを生成する。
  NoteObject makeNewNote(Offset position) {
    final random = Random();
    // 新規作成時は毎回形状を変えず、最後に設定された形状をデフォルトとする。
    final shape = lastShape;
    return NoteObject(
      id: DateTime.now().microsecondsSinceEpoch.toString() + random.nextInt(10000).toString(),
      position: position,
      size: const Size(180, 120),
      content: '',
      label: '',
      detail: '',
      // 新規作成時のデフォルト色は淡いクリーム色。
      color: const Color(0xFFFFF8DC),
      shape: shape,
      labelColor: Colors.black,
      descriptionColor: Colors.purple,
    );
  }
}

/// CanvasNotifier の Provider。
final canvasNotifierProvider = NotifierProvider<CanvasNotifier, CanvasState>(
  () => CanvasNotifier(),
);

/// キャンバス全体の名称を管理する Notifier。
///
/// 画面上部のパネル中央に表示し、タップで変更できる。
/// 保存時の初期ファイル名にも使う。
///
/// [lastShape] と異なり UI がリアクティブに更新する必要があるため、
/// 独立した [Notifier] として管理する。
class CanvasNameNotifier extends Notifier<String> {
  @override
  String build() => 'めもま';

  /// キャンバス名を設定する。空文字列の場合は既定値に戻す。
  void set(String name) {
    state = name.trim().isEmpty ? 'めもま' : name.trim();
  }
}

/// キャンバス名の Provider。
final canvasNameProvider = NotifierProvider<CanvasNameNotifier, String>(
  () => CanvasNameNotifier(),
);

// ---------------------------------------------------------------------------
// 背景ガイド設定
// ---------------------------------------------------------------------------

/// メインキャンバスの背景ガイド設定（罫線・ドット・背景色・背景画像）を
/// 管理する Notifier。
///
/// 設定は [BackgroundPersistenceService] 経由でアプリ内で記憶され、
/// 次回起動時にも維持される。[reset] で初期値に戻せる。
class BackgroundConfigNotifier extends Notifier<BackgroundConfig> {
  final BackgroundPersistenceService _persistence = BackgroundPersistenceService();

  /// 初期値（リセット時の既定値）。
  @override
  BackgroundConfig build() => BackgroundConfig.initial;

  /// 保存済みの設定を読み込み、state に反映する。
  ///
  /// 初回起動時に呼び出す。未設定（初回）の場合は初期値のまま。
  Future<void> load() async {
    final config = await _persistence.load();
    state = config;
  }

  /// 背景設定を更新し、永続化する。
  Future<void> update(BackgroundConfig config) async {
    state = config;
    await _persistence.save(config);
  }

  /// 背景設定を初期値（リセット）に戻し、永続化をクリアする。
  Future<void> reset() async {
    state = BackgroundConfig.initial;
    await _persistence.reset();
  }
}

/// 背景ガイド設定の Provider。
final backgroundConfigProvider =
    NotifierProvider<BackgroundConfigNotifier, BackgroundConfig>(
  () => BackgroundConfigNotifier(),
);