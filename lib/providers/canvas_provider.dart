import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/background_config.dart';
import '../services/background_persistence_service.dart';
import 'canvas_connection_ops.dart';
import 'canvas_group_ops.dart';
import 'canvas_history_ops.dart';
import 'canvas_object_align.dart';
import 'canvas_object_core.dart';
import 'canvas_object_drag.dart';
import 'canvas_object_selection.dart';
import 'canvas_state.dart';

// 外部ファイル（top_action_bar_right.dart 等）が canvas_provider.dart 経由で
// AlignMode を参照するため、re-export して互換性を維持する。
export 'canvas_object_align.dart' show AlignMode;

/// キャンバスの状態（オブジェクト一覧・選択・Undo履歴）を管理する Notifier。
///
/// ドラッグ中は [localDraftPositions] に表示用のローカル座標を持ち、
/// ドラッグ終了時（PanEnd）にのみ Undo 履歴へ状態を保存する。
///
/// 実装は 7 つの mixin に分離されている：
/// - [CanvasObjectCore]     : オブジェクト基本操作（追加 / 編集 / 複製 / 削除）と共有フィールド
/// - [CanvasObjectDrag]     : オブジェクトドラッグ操作（位置更新 / ドラッグ終了 / ドラフト管理）
/// - [CanvasObjectSelection]: オブジェクト選択操作（単一 / 複数 / 全選択）
/// - [CanvasObjectAlign]    : オブジェクト整列（[AlignMode] / ステップ整列 / 等間隔配置）
/// - [CanvasConnectionOps]  : 接続線操作（追加 / 更新 / 削除 / 一括接続）
/// - [CanvasGroupOps]       : グループ枠操作（作成 / 削除 / 更新 / 追加 / 移動）
/// - [CanvasHistoryOps]     : 履歴（Undo / Redo）・読み込み / エクスポート・生成
class CanvasNotifier extends Notifier<CanvasState>
    with
        CanvasObjectCore,
        CanvasObjectDrag,
        CanvasObjectSelection,
        CanvasObjectAlign,
        CanvasConnectionOps,
        CanvasGroupOps,
        CanvasHistoryOps {
  @override
  CanvasState build() => const CanvasState();
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
