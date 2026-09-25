import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection.dart';
import '../models/note_object.dart';
import 'canvas_id.dart';
import 'canvas_state.dart';

/// [CanvasNotifier] の履歴（Undo / Redo）・データ読み込み / エクスポート・
/// 新規オブジェクト生成。
mixin CanvasHistoryOps on Notifier<CanvasState> {
  // ---------------------------------------------------------------------------
  // CanvasObjectOps が提供するメンバー（abstract 宣言）
  // ---------------------------------------------------------------------------

  /// 最後に設定された形状（[makeNewNote] 用）。
  NoteShape get lastShape;

  /// 全オブジェクトのドラフト状態をクリアする（[undo] / [redo] / [loadFromJson] 用）。
  void clearLocalDrafts();

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
        final newId = generateConnectionId();
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
        final newId = generateGroupId();
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
