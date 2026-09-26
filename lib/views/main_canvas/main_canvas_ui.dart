import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/connection.dart';
import '../../models/note_object.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/canvas_state.dart';
import '../../services/canvas_persistence_service.dart';
import '../../services/storage_service.dart';
import '../main_canvas_screen.dart';
import '../widgets/background_grid_painter.dart';
import '../widgets/connection_painter.dart';
import '../widgets/connection_preview_painter.dart';
import '../widgets/group_frame_widget.dart';
import '../widgets/note_object_widget.dart';
import '../widgets/top_action_bar.dart';
import 'build_hint_card.dart';
import 'zoom_control_panel.dart';

/// [MainCanvasScreen] の UI（[build]）。
///
/// [MainCanvasState] が提供するフィールド・ロジックを使って、
/// キャンバス（背景 / グループ枠 / 接続線 / オブジェクト）を描画する。
mixin MainCanvasUi on ConsumerState<MainCanvasScreen> {
  // ---------------------------------------------------------------------------
  // MainCanvasState が提供するメンバー（abstract 宣言）
  // ---------------------------------------------------------------------------

  TransformationController get transformationController;
  StorageService get storageService;
  GlobalKey get bodyStackKey;
  AnimationController get tapIndicatorController;
  Offset get tapIndicatorPos;
  Offset get cursorScreen;
  set cursorScreen(Offset value);
  Offset get tapScreen;
  set tapScreen(Offset value);
  Offset get tapCanvas;
  set tapCanvas(Offset value);
  Offset get tapLocal;
  set tapLocal(Offset value);
  Size get viewport;
  set viewport(Size value);
  Rect get visibleCanvasBounds;
  bool get connectionMode;
  bool get selectionMode;
  bool get debugMode;
  set debugMode(bool value);
  String? get selectedConnectionId;
  set selectedConnectionId(String? value);
  String? get dragSourceId;
  Offset get dragEnd;
  bool get isCentered;
  set isCentered(bool value);

  void onTransformationChanged();
  void showTapIndicator(Offset screenPos);
  Offset screenToCanvas(Offset screenPoint);
  Offset screenToLocal(Offset screenPoint);
  void updateVisibleCanvasBounds(Size viewport);
  Future<void> addNoteAt(Offset screenPoint);
  void toggleConnectionMode();
  void toggleSelectionMode();
  void exitSelectionMode();
  NoteObject? objectById(List<NoteObject> objects, String id);
  Rect? groupFrameRect(GroupFrame frame, List<NoteObject> objects);
  double groupFrameArea(GroupFrame frame, List<NoteObject> objects);
  int groupNestingDepth(GroupFrame frame, List<GroupFrame> frames, List<NoteObject> objects);
  void onConnectionEnd(String sourceId);
  void onConnectionDrag(String sourceId, Offset dragEnd);
  Connection? findConnectionAt(Offset canvasPoint);
  Future<void> showConnectionMenu(BuildContext context, Connection connection, Offset screenPos);

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(canvasNotifierProvider);

    // キャンバス状態が変更されるたびに、デバウンス付きで逐次永続化する。
    ref.listen<CanvasState>(
      canvasNotifierProvider,
      (previous, next) {
        ref.read(canvasPersistenceProvider).scheduleSaveState(next);
      },
    );
    // キャンバス名が変更されるたびに永続化する。
    ref.listen<String>(
      canvasNameProvider,
      (previous, next) {
        if (next.isNotEmpty) {
          ref.read(canvasPersistenceProvider).saveName(next);
        }
      },
    );

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          bottom: false,
          child: TopActionBar(
            storageService: storageService,
            onConnectionModeToggle: toggleConnectionMode,
            connectionMode: connectionMode,
            onSelectionModeToggle: toggleSelectionMode,
            selectionMode: selectionMode,
            onSelectionDone: exitSelectionMode,
          ),
        ),
      ),
      body: Stack(
        key: bodyStackKey,
        children: [
          // ---------------------------------------------------------------
          // 背景ガイド（ビューポート固定、キャンバスの後ろに描画）
          // ---------------------------------------------------------------
          // 背景色はキャンバス座標（最上位座標 0,0）に固定するため、
          // キャンバス本体の Stack 内で描画する（下記参照）。
          // 背景画像・グリッドはビューポート固定で描画する。
          // 背景画像
          if (ref.watch(backgroundConfigProvider).hasImage)
            Positioned.fill(
              child: IgnorePointer(
                child: Image.file(
                  File(
                    ref
                        .watch(backgroundConfigProvider)
                        .backgroundImagePath!,
                  ),
                  fit: BoxFit.cover,
                  opacity: AlwaysStoppedAnimation(
                    ref
                        .watch(backgroundConfigProvider)
                        .backgroundImageOpacity,
                  ),
                ),
              ),
            ),
          // グリッド（罫線 / ドット）
          // Positioned.fill にして、Stack のサイズ計算（非配置子要素）から
          // 外す。これによりパン/ズーム時の再レイアウトが Stack のサイズを
          // 揺らさず、ドラッグでズームが変わる問題を回避する。
          Positioned.fill(
            child: IgnorePointer(
              child: BackgroundGridOverlay(
                transformationController: transformationController,
                config: ref.watch(backgroundConfigProvider),
              ),
            ),
          ),
          // ---------------------------------------------------------------
          // キャンバス本体
          // ---------------------------------------------------------------
          LayoutBuilder(
            builder: (context, constraints) {
              final viewport = constraints.biggest;

              // 初回ビルド時に一度だけキャンバスの中心を画面中央に合わせる
              if (!isCentered && viewport.width > 0 && viewport.height > 0) {
                isCentered = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final translateX = (viewport.width - kCanvasSize.width) / 2;
                  final translateY = (viewport.height - kCanvasSize.height) / 2;
                  transformationController.value =
                      Matrix4.translationValues(translateX, translateY, 0);
                });
              }

              if (this.viewport != viewport) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      this.viewport = viewport;
                      updateVisibleCanvasBounds(viewport);
                    });
                  }
                });
              }
              return MouseRegion(
                onHover: (event) {
                  if (!mounted) return;
                  setState(() => cursorScreen = event.position);
                },
                child: InteractiveViewer(
                  transformationController: transformationController,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(100000), // キャンバス用の有限な大マージン
                  minScale: 0.1,
                  maxScale: 5.0,
                  panEnabled: !connectionMode,
                  scaleEnabled: !connectionMode,
                  onInteractionStart: (_) =>
                      ref.read(canvasNotifierProvider.notifier).clearLocalDrafts(),
                  onInteractionEnd: (_) =>
                      ref.read(canvasNotifierProvider.notifier).clearLocalDrafts(),
                  child: SizedBox(
                    width: kCanvasSize.width,
                    height: kCanvasSize.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // -------------------------------------------------
                        // 背景色（キャンバス座標 0,0 から、マージンなしで
                        // キャンバス全体に描画。パン/ズームに追従する）。
                        // -------------------------------------------------
                        if (ref.watch(backgroundConfigProvider).hasBackground)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                color: ref
                                    .watch(backgroundConfigProvider)
                                    .backgroundColor
                                    .withValues(
                                      alpha: ref
                                          .watch(backgroundConfigProvider)
                                          .backgroundOpacity,
                                    ),
                              ),
                            ),
                          ),
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapDown: (details) {
                              if (!mounted) return;
                              // デバッグモードのとき、タップ位置にインジケーターを表示。
                              showTapIndicator(details.globalPosition);
                              setState(() {
                                tapScreen = details.globalPosition;
                                tapCanvas = screenToCanvas(details.globalPosition);
                                tapLocal = screenToLocal(details.globalPosition);
                              });

                              // 接続線のタップを検出する
                              final canvasPoint = screenToCanvas(details.globalPosition);
                              final connection = findConnectionAt(canvasPoint);
                              if (connection != null) {
                                setState(() => selectedConnectionId = connection.id);
                                showConnectionMenu(context, connection, details.globalPosition);
                                return;
                              }
                              // 選択モード：空き領域タップで全選択を解除する。
                              if (selectionMode) {
                                ref.read(canvasNotifierProvider.notifier).clearSelection();
                              }
                            },
                            onDoubleTapDown: (details) {
                              // 選択モード中は新規作成しない（誤操作防止）。
                              if (selectionMode) return;
                              addNoteAt(details.globalPosition);
                            },
                            onLongPressStart: (details) {
                              // 選択モード中は新規作成しない（誤操作防止）。
                              if (selectionMode) return;
                              addNoteAt(details.globalPosition);
                            },
                          ),
                        ),
                        // グループ枠を描画する（オブジェクトの後ろに描画）。
                        // ネストしたグループでは、面積の大きい（外側の）枠ほど
                        // 先に描画し、小さい（内側の）枠を手前に出すことで、
                        // 内側グループがタップで選択できるようにする。
                        // また、ネスト深さ（内包するグループ数）に応じてマージンを
                        // 外側に拡大し、境界線が重ならないようにする。
                        ...[
                          for (final frame in state.groupFrames.toList()
                              ..sort((a, b) => groupFrameArea(b, state.objects)
                                  .compareTo(groupFrameArea(a, state.objects))))
                            GroupFrameWidget(
                              key: ValueKey(frame.id),
                              frame: frame,
                              objects: state.objects,
                              transformationController: transformationController,
                              margin: 24.0 +
                                  groupNestingDepth(
                                          frame, state.groupFrames, state.objects) *
                                      20.0,
                              onTapDown: (globalPos) {
                                // グループ枠の上でも接続線を選択できるようにする。
                                final canvasPoint = screenToCanvas(globalPos);
                                final connection = findConnectionAt(canvasPoint);
                                if (connection != null) {
                                  setState(() => selectedConnectionId = connection.id);
                                  showConnectionMenu(context, connection, globalPos);
                                  return true;
                                }
                                return false;
                              },
                            ),
                        ],
                        // 接続線を描画する（オブジェクトの後ろに描画）。
                        ...state.connections.map(
                          (connection) {
                            final source = objectById(state.objects, connection.sourceId);
                            final target = objectById(state.objects, connection.targetId);
                            if (source == null || target == null) return const SizedBox.shrink();
                            return Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: ConnectionPainter(
                                    connection: connection,
                                    sourceRect: source.rectInCanvas(),
                                    targetRect: target.rectInCanvas(),
                                    color: connection.color,
                                    isSelected: selectedConnectionId == connection.id,
                                  ),
                                ),
                              )
                            );
                          },
                        ),
                        ...state.objects.map(
                          (note) => NoteObjectWidget(
                            key: ValueKey(note.id),
                            note: note,
                            transformationController: transformationController,
                            connectionMode: connectionMode,
                            selectionMode: selectionMode,
                            onConnectionDrag: (dragEnd) {
                              if (!mounted) return;
                              onConnectionDrag(note.id, dragEnd);
                            },
                            onConnectionDragEnd: () {
                              if (!mounted) return;
                              onConnectionEnd(note.id);
                            },
                          ),
                        ),
                        // 接続モードでドラッグ中にプレビュー線を描画する。
                        if (connectionMode && dragSourceId != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: ConnectionPreviewPainter(
                                  start: dragSourceId != null
                                      ? (objectById(state.objects, dragSourceId!)!.position +
                                          objectById(state.objects, dragSourceId!)!.size.center(Offset.zero))
                                      : Offset.zero,
                                  end: dragEnd,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // デバッグモードでタップ位置にインジケーター（円）を表示する。
          if (debugMode)
            AnimatedBuilder(
              animation: tapIndicatorController,
              builder: (context, _) {
                final box = bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null) return const SizedBox.shrink();

                final localPos = box.globalToLocal(tapIndicatorPos);
                final t = tapIndicatorController.value;

                // 半径の計算（詳細は下記「2. クリックサイズの調整」を参照）
                final radius = 3.0 + 3.0 * t;
                final opacity = 0.9 * (1.0 - t);

                // Stack の直下に Positioned を配置し、IgnorePointer でラップする
                return Positioned(
                  left: localPos.dx - radius,
                  top: localPos.dy - radius,
                  width: radius * 2,
                  height: radius * 2,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.yellow.withValues(alpha: opacity),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: opacity),
                          width: 1.0,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
         Positioned(
            right: 12,
            bottom: 12,
            child: BuildHintCard(
              debugMode: debugMode,
              onTap: () => setState(() => debugMode = !debugMode),
              cursorScreen: cursorScreen,
              tapScreen: tapScreen,
              tapLocal: tapLocal,
              tapCanvas: tapCanvas,
              visibleCanvasBounds: visibleCanvasBounds,
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: ZoomControlPanel(
              transformationController: transformationController,
            ),
          ),
        ],
      ),
    );
  }
}
