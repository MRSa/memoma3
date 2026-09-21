import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../providers/canvas_state.dart';

/// キャンバスの状態（オブジェクト・接続線・グループ枠）とキャンバス名を
/// [hive_ce] に永続化するサービス。
///
/// アプリを再起動しても前回の状態をそのまま復元できるように、
/// 状態変更を逐次（デバウンス付きで）ローカルに記録する。
///
/// - 保存形式は [CanvasState.toJson] の JSON 文字列（`objects` / `connections` / `groups`）。
///   Undo / Redo 履歴は含めない（再起動時は履歴なしの状態で復元する）。
/// - キャンバス名も併せて保存する。
///
/// 書き込みは [scheduleSaveState] 経由でデバウンスされ、ドラッグ中の
/// 高頻度更新が 1 回のディスク書き込みにまとまる。[flush] で即時書き込み
/// できる（アプリの一時停止時などに呼ぶ）。
class CanvasPersistenceService {
  /// 使用する box の名前。
  static const String boxName = 'memoma3_canvas';

  /// キャンバス状態を保存するキー。
  static const String stateKey = 'state';

  /// キャンバス名を保存するキー。
  static const String nameKey = 'name';

  /// デバウンスの間隔。この間隔で状態変更が止まったら書き込む。
  static const Duration _debounce = Duration(milliseconds: 400);

  Box<dynamic>? _box;
  Timer? _saveTimer;
  CanvasState? _pendingState;

  /// box を開く（未開なら開く）。既に開いていれば既存のインスタンスを返す。
  Future<Box<dynamic>> _ensureBox() async {
    final box = _box;
    if (box != null && box.isOpen) return box;
    final opened = await Hive.openBox<dynamic>(boxName);
    _box = opened;
    return opened;
  }

  /// キャンバス状態を即座に保存する。
  Future<void> saveState(CanvasState state) async {
    final box = await _ensureBox();
    await box.put(stateKey, state.toJson());
  }

  /// 保存済みのキャンバス状態（JSON 文字列）を読み込む。
  /// 未保存（初回起動）の場合は `null` を返す。
  Future<String?> loadState() async {
    final box = await _ensureBox();
    return box.get(stateKey) as String?;
  }

  /// キャンバス名を即座に保存する。
  Future<void> saveName(String name) async {
    final box = await _ensureBox();
    await box.put(nameKey, name);
  }

  /// 保存済みのキャンバス名を読み込む。未保存の場合は `null` を返す。
  Future<String?> loadName() async {
    final box = await _ensureBox();
    return box.get(nameKey) as String?;
  }

  /// 状態変更をデバウンス付きで保存する。
  ///
  /// 連続して呼ばれた場合は最後の状態のみが [_debounce] 後に書き込まれる。
  /// ドラッグ中の高頻度更新を 1 回の書き込みにまとめる。
  void scheduleSaveState(CanvasState state) {
    _pendingState = state;
    _saveTimer?.cancel();
    _saveTimer = Timer(_debounce, () {
      _saveTimer = null;
      final pending = _pendingState;
      if (pending != null) {
        _pendingState = null;
        saveState(pending);
      }
    });
  }

  /// 保留中の保存を即座に実行する。
  ///
  /// アプリの一時停止（[AppLifecycleState.paused]）時などに呼び、
  /// デバウンス待ちの状態でアプリが終了するのを防ぐ。
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final pending = _pendingState;
    if (pending != null) {
      _pendingState = null;
      await saveState(pending);
    }
  }

  /// 保存済みの全データを削除する。
  Future<void> clear() async {
    final box = await _ensureBox();
    await box.clear();
  }
}

/// [CanvasPersistenceService] の Provider。
final canvasPersistenceProvider = Provider<CanvasPersistenceService>((ref) {
  return CanvasPersistenceService();
});
