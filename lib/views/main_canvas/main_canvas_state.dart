import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../models/connection.dart';
import '../../models/note_object.dart';
import '../../providers/canvas_provider.dart';
import '../../services/canvas_persistence_service.dart';
import '../../services/storage_service.dart';
import '../main_canvas_screen.dart';
import '../widgets/connection_painter.dart';
import 'connection_menu_dialog.dart';

/// [MainCanvasScreen] のロジック（フィールド / ライフサイクル / 座標変換 /
/// モード切替 / グループ枠 / 接続線）。
///
/// [MainCanvasScreen] の state クラスが本 mixin を適用することで、
/// キャンバス操作のロジックを利用する。[ConsumerState] を継承するため
/// [ref] に直接アクセスできる。
mixin MainCanvasState
    on ConsumerState<MainCanvasScreen>, WidgetsBindingObserver, TickerProvider {
  // ---------------------------------------------------------------------------
  // フィールド
  // ---------------------------------------------------------------------------

  final TransformationController transformationController =
      TransformationController();

  final StorageService storageService = StorageService();

  /// body の Stack を参照するためのキー（タップインジケーターの座標変換用）。
  final GlobalKey bodyStackKey = GlobalKey();

  /// タップインジケーター（デバッグモードでタップ位置に円を表示）のアニメーション。
  late final AnimationController tapIndicatorController;

  /// タップインジケーターを表示する位置（画面座標）。
  Offset tapIndicatorPos = Offset.zero;

  Offset cursorScreen = Offset.zero;
  Offset tapScreen = Offset.zero;
  Offset tapCanvas = Offset.zero;
  Offset tapLocal = Offset.zero;
  Size viewport = Size.zero;
  Rect visibleCanvasBounds = Rect.zero;

  /// 接続モード中かどうか。true のとき、オブジェクトをドラッグして
  /// 別のオブジェクトへ接続線を引く。
  bool connectionMode = false;

  /// 選択モード中かどうか。true のとき、オブジェクトをタップすると
  /// 選択がトグルされ、複数選択できる（キーボードのない環境向け）。
  bool selectionMode = false;

  /// デバッグモード中かどうか。true のとき、右下パネルに
  /// カーソル・タップ・表示範囲の座標情報を表示する。
  bool debugMode = false;

  /// 選択中の接続線（コンテキストメニュー表示用）。
  String? selectedConnectionId;

  /// 接続モードでドラッグ中の情報。
  /// [dragSourceId] はドラッグ開始時のオブジェクト、
  /// [dragEnd] は現在のドラッグ先のキャンバス座標。
  String? dragSourceId;
  Offset dragEnd = Offset.zero;

  bool isCentered = false;

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    transformationController.addListener(onTransformationChanged);
    tapIndicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // キーボードショートカット（Ctrl+D で複製）を登録する。
    HardwareKeyboard.instance.addHandler(onKey);
    // 起動時に保存済みの背景ガイド設定を読み込む。
    ref.read(backgroundConfigProvider.notifier).load();
    // 起動時に保存済みのキャンバス状態・キャンバス名を復元する。
    restoreCanvas();
  }

  /// キーボードショートカットのハンドラ。
  ///
  /// - Ctrl+D: 選択中のオブジェクトを複製する。
  bool onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isD = event.logicalKey == LogicalKeyboardKey.keyD;
    if (isCtrl && isD) {
      final notifier = ref.read(canvasNotifierProvider.notifier);
      if (notifier.selectedCount > 0) {
        notifier.duplicateSelected();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(milliseconds: 1500),
              content: Text('オブジェクトを複製しました')
            ),
          );
        }
      }
      return true;
    }
    return false;
  }

  /// アプリがバックグラウンドに移る（終了する）タイミングで、
  /// デバウンス待ちの未保存データを確実に書き込む。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(canvasPersistenceProvider).flush();
    }
  }

  /// 起動時に保存済みのキャンバス状態とキャンバス名を復元する。
  ///
  /// 保存データがない（初回起動）場合は何もしない。
  Future<void> restoreCanvas() async {
    final persistence = ref.read(canvasPersistenceProvider);
    try {
      final savedName = await persistence.loadName();
      if (savedName != null && savedName.isNotEmpty) {
        ref.read(canvasNameProvider.notifier).set(savedName);
      }
      final savedState = await persistence.loadState();
      if (savedState != null && savedState.isNotEmpty) {
        ref.read(canvasNotifierProvider.notifier).loadFromJson(savedState);
      }
    } catch (_) {
      // 復元失敗（破損データ等）は初期状態のまま安全に続行する。
    }
  }

  void onTransformationChanged() {
    if (!mounted) return;
    setState(() => updateVisibleCanvasBounds(viewport));
  }

  /// タップ位置にインジケーター（円）を表示する。
  /// デバッグモードのときのみ有効。
  void showTapIndicator(Offset screenPos) {
    if (!debugMode) return;
    setState(() => tapIndicatorPos = screenPos);
    tapIndicatorController.forward(from: 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(onKey);
    transformationController.removeListener(onTransformationChanged);
    transformationController.dispose();
    tapIndicatorController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 座標変換
  // ---------------------------------------------------------------------------

  /// ウィンドウ（global）座標を、body の Stack（[InteractiveViewer] の
  /// ローカル座標系）に変換する。
  ///
  /// キャンバスは Scaffold の body 内にあり、appBar（TopActionBar）の高さ分
  /// だけ下にある。[InteractiveViewer] の行列は「body 内ローカル座標 →
  /// キャンバス座標」の変換なので、global 座標をそのまま渡すと appBar の
  /// 高さ分だけずれる。そこでまず body Stack 基準に変換する。
  Offset globalToBodyLocal(Offset globalPoint) {
    final box = bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return globalPoint;
    return box.globalToLocal(globalPoint);
  }

  Offset screenToCanvas(Offset screenPoint) {
    // global 座標 → body Stack（InteractiveViewer）ローカル座標。
    final localPoint = globalToBodyLocal(screenPoint);

    final matrix = transformationController.value;
    if (matrix == Matrix4.identity()) {
      return localPoint;
    }
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) {
      return localPoint;
    }
    final transformed = inverse.transform(Vector4(localPoint.dx, localPoint.dy, 0, 1));
    return Offset(transformed.x, transformed.y);
  }

  Offset screenToLocal(Offset screenPoint) {
    // global 座標 → body Stack（InteractiveViewer）ローカル座標。
    final localPoint = globalToBodyLocal(screenPoint);

    final matrix = transformationController.value;
    if (matrix == Matrix4.identity()) {
      return localPoint;
    }
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) {
      return localPoint;
    }
    final transformed = inverse.transform(Vector4(localPoint.dx, localPoint.dy, 0, 1));
    return Offset(transformed.x, transformed.y);
  }

  void updateVisibleCanvasBounds(Size viewport) {
    final matrix = transformationController.value;
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) {
      visibleCanvasBounds = Rect.zero;
      return;
    }
    final topLeft = inverse.transform(Vector4(0, 0, 0, 1));
    final topRight = inverse.transform(Vector4(viewport.width, 0, 0, 1));
    final bottomLeft = inverse.transform(Vector4(0, viewport.height, 0, 1));
    final bottomRight =
        inverse.transform(Vector4(viewport.width, viewport.height, 0, 1));
    final xs = [topLeft.x, topRight.x, bottomLeft.x, bottomRight.x];
    final ys = [topLeft.y, topRight.y, bottomLeft.y, bottomRight.y];
    final minX = xs.reduce(min);
    final minY = ys.reduce(min);
    final maxX = xs.reduce(max);
    final maxY = ys.reduce(max);
    visibleCanvasBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // ---------------------------------------------------------------------------
  // 操作
  // ---------------------------------------------------------------------------

  Future<void> addNoteAt(Offset screenPoint) async {
    final canvasPoint = screenToCanvas(screenPoint);
    final notifier = ref.read(canvasNotifierProvider.notifier);
    final centerPoint = canvasPoint - const Offset(180, 120) / 2;
    final newNote = notifier.makeNewNote(centerPoint);
    notifier.addObject(newNote);
  }

  void toggleConnectionMode() {
    setState(() {
      connectionMode = !connectionMode;
      selectedConnectionId = null;
      // 接続モードと選択モードは排他。接続モード中は選択モードを解除する。
      if (connectionMode) selectionMode = false;
    });
  }

  /// 選択モードをトグルする。
  ///
  /// 選択モード中は、オブジェクトをタップすると選択がトグルされ、
  /// キーボードのない環境（Android 等）でも複数選択できる。
  /// 選択モードを終了するときは、選択状態は保持する（「完了」で終了）。
  void toggleSelectionMode() {
    setState(() {
      selectionMode = !selectionMode;
      // 選択モードと接続モードは排他。選択モード中は接続モードを解除する。
      if (selectionMode) connectionMode = false;
    });
  }

  /// 選択モードを終了する（選択状態は保持）。
  void exitSelectionMode() {
    setState(() {
      selectionMode = false;
    });
  }

  /// ID からオブジェクトを検索する。
  NoteObject? objectById(List<NoteObject> objects, String id) {
    for (final o in objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// グループのメンバーの外接矩形を返す。
  Rect? groupFrameRect(GroupFrame frame, List<NoteObject> objects) {
    final members = objects.where((o) => frame.memberIds.contains(o.id));
    if (members.isEmpty) return null;

    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final m in members) {
      final r = m.rectInCanvas();
      left = min(left, r.left);
      top = min(top, r.top);
      right = max(right, r.right);
      bottom = max(bottom, r.bottom);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// グループ枠の外接矩形の面積を返す（ソート用）。
  ///
  /// ネストしたグループでは、面積の大きい（外側の）枠ほど先に描画し、
  /// 小さい（内側の）枠を手前に出すことで、内側グループがタップで
  /// 選択できるようにする。
  double groupFrameArea(GroupFrame frame, List<NoteObject> objects) {
    final rect = groupFrameRect(frame, objects);
    if (rect == null) return 0.0;
    return rect.width * rect.height;
  }

  /// [frame] が他のグループを内包している数を返す（ネスト深さ）。
  ///
  /// 内包するグループの外接矩形が、[frame] の外接矩形に完全に含まれる
  /// ものを「内包」とみなす。この値が大きいほど外側のグループであり、
  /// 境界線が重ならないようマージンを大きくする。
  int groupNestingDepth(
      GroupFrame frame, List<GroupFrame> frames, List<NoteObject> objects) {
    final outer = groupFrameRect(frame, objects);
    if (outer == null) return 0;
    var depth = 0;
    for (final other in frames) {
      if (other.id == frame.id) continue;
      final inner = groupFrameRect(other, objects);
      if (inner == null) continue;
      // 内側グループが外側グループに完全に含まれる場合のみ内包とみなす。
      if (inner.left >= outer.left &&
          inner.top >= outer.top &&
          inner.right <= outer.right &&
          inner.bottom <= outer.bottom) {
        depth++;
      }
    }
    return depth;
  }

  /// 接続モードでドラッグ終了。接続先オブジェクトへ接続線を追加する。
  /// 接続モードでドラッグが終了したときの処理。
  /// [sourceId] はドラッグ開始時のオブジェクト。ドラッグ先（dragEnd）に
  /// 重なっているオブジェクトを検出して接続線を作成する。
  void onConnectionEnd(String sourceId) {
    dragSourceId = null;

    // 終点に重なっているオブジェクトを検出する。
    final targetId = findTargetAt(dragEnd, excludeId: sourceId);
    if (targetId == null || targetId == sourceId) return;

    ref.read(canvasNotifierProvider.notifier).addConnection(
      sourceId: sourceId,
      targetId: targetId,
    );
  }

  /// 指定したキャンバス座標に重なっているオブジェクトのIDを返す。
  /// [excludeId] のオブジェクトは除外する。
  String? findTargetAt(Offset point, {String? excludeId}) {
    final state = ref.read(canvasNotifierProvider);
    // 前面（リスト末尾）から検索して、最前面のオブジェクトを優先する。
    for (var i = state.objects.length - 1; i >= 0; i--) {
      final obj = state.objects[i];
      if (obj.id == excludeId) continue;
      if (obj.rectInCanvas().contains(point)) return obj.id;
    }
    return null;
  }

  /// 接続モードでドラッグ中の処理。ドラッグ先を記録し、
  /// 終点オブジェクトを視覚的に強調する。
  void onConnectionDrag(String sourceId, Offset dragEnd) {
    dragSourceId = sourceId;
    this.dragEnd = dragEnd;
  }

  /// キャンバス座標の点が接続線から近いかどうかを判定する。
  bool isNearConnection(Connection connection, NoteObject source, NoteObject target, Offset point) {
    final painter = ConnectionPainter(
      connection: connection,
      sourceRect: source.rectInCanvas(),
      targetRect: target.rectInCanvas(),
    );
    final path = painter.buildPath();

    final scale = currentScale();
    final threshold = 45.0 / scale;

    // 1. 段階目: バウンディングボックスによる即時判定 (AABB Check)
    final bounds = path.getBounds().inflate(threshold);
    if (!bounds.contains(point)) {
      return false;
    }

    // 2. 段階目: パス上の細分化判定
    for (final metric in path.computeMetrics()) {
      // 固定ステップではなく、線の長さに応じた可変ステップ、または閾値の半分程度で走査
      final double step = (threshold / 2).clamp(2.0, 10.0);

      for (double d = 0.0; d <= metric.length; d += step) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null) {
          // squaredDistance（距離の2乗）で判定すると sqrt の計算コストを削減可能
          final dx = point.dx - tangent.position.dx;
          final dy = point.dy - tangent.position.dy;
          if ((dx * dx + dy * dy) < (threshold * threshold)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /// 現在のズーム率を取得する。
  double currentScale() {
    final m = transformationController.value;
    return (m.entry(0, 0) + m.entry(1, 1)) / 2;
  }

  /// キャンバス座標 [canvasPoint] がどの接続線に近いかを判定し、
  /// 該当する接続線を返す。該当しなければ null を返す。
  ///
  /// グループ枠の上でも接続線を選択できるように、
  /// [GroupFrameWidget] の onTapDown からも呼び出される。
  Connection? findConnectionAt(Offset canvasPoint) {
    final state = ref.read(canvasNotifierProvider);
    for (final connection in state.connections) {
      final source = objectById(state.objects, connection.sourceId);
      final target = objectById(state.objects, connection.targetId);
      if (source != null && target != null &&
          isNearConnection(connection, source, target, canvasPoint)) {
        return connection;
      }
    }
    return null;
  }

  /// 接続線のコンテキストメニューを表示する。
  ///
  /// 実装は [connection_menu_dialog.dart] の [showConnectionMenuDialog] にある。
  Future<void> showConnectionMenu(
    BuildContext context,
    Connection connection,
    Offset screenPos,
  ) async {
    await showConnectionMenuDialog(this, context, connection, screenPos);
  }

  /// 選択中の接続線を解除する（メニュー閉じ後に呼ばれる）。
  void clearSelectedConnection() {
    if (mounted) {
      setState(() {
        selectedConnectionId = null;
      });
    }
  }
}
