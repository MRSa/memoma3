import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/connection.dart';
import '../../models/note_object.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/canvas_state.dart';
import '../../services/canvas_persistence_service.dart';
import '../../services/storage_service.dart';
import 'widgets/background_grid_painter.dart';
import 'widgets/connection_menu.dart';
import 'widgets/connection_painter.dart';
import 'widgets/connection_preview_painter.dart';
import 'widgets/group_frame_widget.dart';
import 'widgets/note_object_widget.dart';
import 'widgets/top_action_bar.dart';

// ---------------------------------------------------------------------------
// MainCanvasScreen および関連ウィジェット
// ---------------------------------------------------------------------------

/// キャンバスのサイズ（px）。広大なキャンバスとして構成する。
const Size kCanvasSize = Size(50000, 50000);

/// キャンバスを表示するメイン画面。
class MainCanvasScreen extends ConsumerStatefulWidget {
  const MainCanvasScreen({super.key});

  @override
  ConsumerState<MainCanvasScreen> createState() => _MainCanvasScreenState();
}


class _MainCanvasScreenState extends ConsumerState<MainCanvasScreen>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver {
  final TransformationController _transformationController =
      TransformationController();

  final StorageService _storageService = StorageService();

  /// body の Stack を参照するためのキー（タップインジケーターの座標変換用）。
  final GlobalKey _bodyStackKey = GlobalKey();

  /// タップインジケーター（デバッグモードでタップ位置に円を表示）のアニメーション。
  late final AnimationController _tapIndicatorController;

  /// タップインジケーターを表示する位置（画面座標）。
  Offset _tapIndicatorPos = Offset.zero;

  Offset _cursorScreen = Offset.zero;
  Offset _tapScreen = Offset.zero;
  Offset _tapCanvas = Offset.zero;
  Offset _tapLocal = Offset.zero;
  Size _viewport = Size.zero;
  Rect _visibleCanvasBounds = Rect.zero;

  /// 接続モード中かどうか。true のとき、オブジェクトをドラッグして
  /// 別のオブジェクトへ接続線を引く。
  bool _connectionMode = false;

  /// 選択モード中かどうか。true のとき、オブジェクトをタップすると
  /// 選択がトグルされ、複数選択できる（キーボードのない環境向け）。
  bool _selectionMode = false;

  /// デバッグモード中かどうか。true のとき、右下パネルに
  /// カーソル・タップ・表示範囲の座標情報を表示する。
  bool _debugMode = false;

  /// 選択中の接続線（コンテキストメニュー表示用）。
  String? _selectedConnectionId;

  /// 接続モードでドラッグ中の情報。
  /// [dragSourceId] はドラッグ開始時のオブジェクト、
  /// [dragEnd] は現在のドラッグ先のキャンバス座標。
  String? _dragSourceId;
  Offset _dragEnd = Offset.zero;

  bool _isCentered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transformationController.addListener(_onTransformationChanged);
    _tapIndicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // キーボードショートカット（Ctrl+D で複製）を登録する。
    HardwareKeyboard.instance.addHandler(_onKey);
    // 起動時に保存済みの背景ガイド設定を読み込む。
    ref.read(backgroundConfigProvider.notifier).load();
    // 起動時に保存済みのキャンバス状態・キャンバス名を復元する。
    _restoreCanvas();
  }

  /// キーボードショートカットのハンドラ。
  ///
  /// - Ctrl+D: 選択中のオブジェクトを複製する。
  bool _onKey(KeyEvent event) {
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
  Future<void> _restoreCanvas() async {
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

  void _onTransformationChanged() {
    if (!mounted) return;
    setState(() => _updateVisibleCanvasBounds(_viewport));
  }

  /// タップ位置にインジケーター（円）を表示する。
  /// デバッグモードのときのみ有効。
  void _showTapIndicator(Offset screenPos) {
    if (!_debugMode) return;
    setState(() => _tapIndicatorPos = screenPos);
    _tapIndicatorController.forward(from: 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    _tapIndicatorController.dispose();
    super.dispose();
  }

  /// ウィンドウ（global）座標を、body の Stack（[InteractiveViewer] の
  /// ローカル座標系）に変換する。
  ///
  /// キャンバスは Scaffold の body 内にあり、appBar（TopActionBar）の高さ分
  /// だけ下にある。[InteractiveViewer] の行列は「body 内ローカル座標 →
  /// キャンバス座標」の変換なので、global 座標をそのまま渡すと appBar の
  /// 高さ分だけずれる。そこでまず body Stack 基準に変換する。
  Offset _globalToBodyLocal(Offset globalPoint) {
    final box = _bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return globalPoint;
    return box.globalToLocal(globalPoint);
  }

  Offset _screenToCanvas(Offset screenPoint) {
    // global 座標 → body Stack（InteractiveViewer）ローカル座標。
    final localPoint = _globalToBodyLocal(screenPoint);

    final matrix = _transformationController.value;
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

  Offset _screenToLocal(Offset screenPoint) {
    // global 座標 → body Stack（InteractiveViewer）ローカル座標。
    final localPoint = _globalToBodyLocal(screenPoint);

    final matrix = _transformationController.value;
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

  void _updateVisibleCanvasBounds(Size viewport) {
    final matrix = _transformationController.value;
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) {
      _visibleCanvasBounds = Rect.zero;
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
    _visibleCanvasBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Future<void> _addNoteAt(Offset screenPoint) async {
    final canvasPoint = _screenToCanvas(screenPoint);
    final notifier = ref.read(canvasNotifierProvider.notifier);
    final centerPoint = canvasPoint - const Offset(180, 120) / 2;
    final newNote = notifier.makeNewNote(centerPoint);
    notifier.addObject(newNote);
  }

  void _toggleConnectionMode() {
    setState(() {
      _connectionMode = !_connectionMode;
      _selectedConnectionId = null;
      // 接続モードと選択モードは排他。接続モード中は選択モードを解除する。
      if (_connectionMode) _selectionMode = false;
    });
  }

  /// 選択モードをトグルする。
  ///
  /// 選択モード中は、オブジェクトをタップすると選択がトグルされ、
  /// キーボードのない環境（Android 等）でも複数選択できる。
  /// 選択モードを終了するときは、選択状態は保持する（「完了」で終了）。
  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      // 選択モードと接続モードは排他。選択モード中は接続モードを解除する。
      if (_selectionMode) _connectionMode = false;
    });
  }

  /// 選択モードを終了する（選択状態は保持）。
  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
    });
  }

  /// ID からオブジェクトを検索する。
  NoteObject? _objectById(List<NoteObject> objects, String id) {
    for (final o in objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// グループのメンバーの外接矩形を返す。
  Rect? _groupFrameRect(GroupFrame frame, List<NoteObject> objects) {
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
  double _groupFrameArea(GroupFrame frame, List<NoteObject> objects) {
    final rect = _groupFrameRect(frame, objects);
    if (rect == null) return 0.0;
    return rect.width * rect.height;
  }

  /// [frame] が他のグループを内包している数を返す（ネスト深さ）。
  ///
  /// 内包するグループの外接矩形が、[frame] の外接矩形に完全に含まれる
  /// ものを「内包」とみなす。この値が大きいほど外側のグループであり、
  /// 境界線が重ならないようマージンを大きくする。
  int _groupNestingDepth(
      GroupFrame frame, List<GroupFrame> frames, List<NoteObject> objects) {
    final outer = _groupFrameRect(frame, objects);
    if (outer == null) return 0;
    var depth = 0;
    for (final other in frames) {
      if (other.id == frame.id) continue;
      final inner = _groupFrameRect(other, objects);
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
  /// [sourceId] はドラッグ開始時のオブジェクト。ドラッグ先（_dragEnd）に
  /// 重なっているオブジェクトを検出して接続線を作成する。
  void _onConnectionEnd(String sourceId) {
    _dragSourceId = null;

    // 終点に重なっているオブジェクトを検出する。
    final targetId = _findTargetAt(_dragEnd, excludeId: sourceId);
    if (targetId == null || targetId == sourceId) return;

    ref.read(canvasNotifierProvider.notifier).addConnection(
      sourceId: sourceId,
      targetId: targetId,
    );
  }

  /// 指定したキャンバス座標に重なっているオブジェクトのIDを返す。
  /// [excludeId] のオブジェクトは除外する。
  String? _findTargetAt(Offset point, {String? excludeId}) {
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
  void _onConnectionDrag(String sourceId, Offset dragEnd) {
    _dragSourceId = sourceId;
    _dragEnd = dragEnd;
  }

  /// キャンバス座標の点が接続線から近いかどうかを判定する。
  bool _isNearConnection(Connection connection, NoteObject source, NoteObject target, Offset point) {
  final painter = ConnectionPainter(
    connection: connection,
    sourceRect: source.rectInCanvas(),
    targetRect: target.rectInCanvas(),
  );
  final path = painter.buildPath();

  final scale = _currentScale();
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
  double _currentScale() {
    final m = _transformationController.value;
    return (m.entry(0, 0) + m.entry(1, 1)) / 2;
  }

  /// キャンバス座標 [canvasPoint] がどの接続線に近いかを判定し、
  /// 該当する接続線を返す。該当しなければ null を返す。
  ///
  /// グループ枠の上でも接続線を選択できるように、
  /// [GroupFrameWidget] の onTapDown からも呼び出される。
  Connection? _findConnectionAt(Offset canvasPoint) {
    final state = ref.read(canvasNotifierProvider);
    for (final connection in state.connections) {
      final source = _objectById(state.objects, connection.sourceId);
      final target = _objectById(state.objects, connection.targetId);
      if (source != null && target != null &&
          _isNearConnection(connection, source, target, canvasPoint)) {
        return connection;
      }
    }
    return null;
  }

  /// 接続線のコンテキストメニューを表示する。
  ///
  /// [showDialog] は builder の結果を [Dialog]（内部に [Padding] を持つ）で
  /// ラップするため、[Positioned] が [Stack] の直接の子にならず
  /// 「Incorrect use of ParentDataWidget」例外が発生する。
  /// そこで [DialogRoute] の [builder] を使い、画面全体を埋める
  /// [Stack] の直接の子として [Positioned] を配置する。
  Future<void> _showConnectionMenu(BuildContext context, Connection connection, Offset screenPos) async {
    final size = MediaQuery.of(context).size;

    // メニューの幅と、タップ位置（線が通る位置）からの余白。
    // 線との重なりを避けるため、十分な距離を取る。
    const menuWidth = 220.0;
    const margin = 40.0;
    // 高さの概算値（初回フレーム用の初期配置）。実際の高さは
    // _ConnectionMenuPositioner がレイアウト後に計測して補正する。
    const estimatedHeight = 320.0;

    // デフォルトはタップ位置の右下に配置する。
    double left = screenPos.dx + margin;
    double top = screenPos.dy + margin;

    // 画面からはみ出す場合は、タップ位置の左上側に反転させる。
    if (left + menuWidth > size.width) {
      left = screenPos.dx - margin - menuWidth;
    }
    if (top + estimatedHeight > size.height) {
      top = screenPos.dy - margin - estimatedHeight;
    }

    // 最終的に画面内に収める。
    left = left.clamp(0.0, size.width - menuWidth).toDouble();
    top = top.clamp(0.0, size.height - estimatedHeight).toDouble();

    // メニューを閉じた後、選択状態を解除して線の色を元に戻す。
    await Navigator.of(context).push(
      DialogRoute<void>(
        context: context,
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        builder: (dialogContext) {
          return _ConnectionMenuPositioner(
            screenPos: screenPos,
            menuWidth: menuWidth,
            margin: margin,
            initialLeft: left,
            initialTop: top,
            child: ConnectionContextMenu(
              connection: connection,
              anchor: screenPos,
            ),
          );
        },
      ),
    );

    // メニューが閉じられたら選択を解除する。
    if (mounted) {
      setState(() {
        _selectedConnectionId = null;
      });
    }
  }

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
            storageService: _storageService,
            onConnectionModeToggle: _toggleConnectionMode,
            connectionMode: _connectionMode,
            onSelectionModeToggle: _toggleSelectionMode,
            selectionMode: _selectionMode,
            onSelectionDone: _exitSelectionMode,
          ),
        ),
      ),
      body: Stack(
        key: _bodyStackKey,
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
                transformationController: _transformationController,
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
              if (!_isCentered && viewport.width > 0 && viewport.height > 0) {
                _isCentered = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final translateX = (viewport.width - kCanvasSize.width) / 2;
                  final translateY = (viewport.height - kCanvasSize.height) / 2;
                  _transformationController.value =
                      Matrix4.translationValues(translateX, translateY, 0);
                });
              }

              if (_viewport != viewport) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _viewport = viewport;
                      _updateVisibleCanvasBounds(viewport);
                    });
                  }
                });
              }
              return MouseRegion(
                onHover: (event) {
                  if (!mounted) return;
                  setState(() => _cursorScreen = event.position);
                },
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(100000), // キャンバス用の有限な大マージン
                  minScale: 0.1,
                  maxScale: 5.0,
                  panEnabled: !_connectionMode,
                  scaleEnabled: !_connectionMode,
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
                              _showTapIndicator(details.globalPosition);
                              setState(() {
                                _tapScreen = details.globalPosition;
                                _tapCanvas = _screenToCanvas(details.globalPosition);
                                _tapLocal = _screenToLocal(details.globalPosition);
                              });
                              
                              // 接続線のタップを検出する
                              final canvasPoint = _screenToCanvas(details.globalPosition);
                              final connection = _findConnectionAt(canvasPoint);
                              if (connection != null) {
                                setState(() => _selectedConnectionId = connection.id);
                                _showConnectionMenu(context, connection, details.globalPosition);
                                return;
                              }
                              // 選択モード：空き領域タップで全選択を解除する。
                              if (_selectionMode) {
                                ref.read(canvasNotifierProvider.notifier).clearSelection();
                              }
                            },
                            onDoubleTapDown: (details) {
                              // 選択モード中は新規作成しない（誤操作防止）。
                              if (_selectionMode) return;
                              _addNoteAt(details.globalPosition);
                            },
                            onLongPressStart: (details) {
                              // 選択モード中は新規作成しない（誤操作防止）。
                              if (_selectionMode) return;
                              _addNoteAt(details.globalPosition);
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
                              ..sort((a, b) => _groupFrameArea(b, state.objects)
                                  .compareTo(_groupFrameArea(a, state.objects))))
                            GroupFrameWidget(
                              key: ValueKey(frame.id),
                              frame: frame,
                              objects: state.objects,
                              transformationController: _transformationController,
                              margin: 24.0 +
                                  _groupNestingDepth(
                                          frame, state.groupFrames, state.objects) *
                                      20.0,
                              onTapDown: (globalPos) {
                                // グループ枠の上でも接続線を選択できるようにする。
                                final canvasPoint = _screenToCanvas(globalPos);
                                final connection = _findConnectionAt(canvasPoint);
                                if (connection != null) {
                                  setState(() => _selectedConnectionId = connection.id);
                                  _showConnectionMenu(context, connection, globalPos);
                                  return true;
                                }
                                return false;
                              },
                            ),
                        ],
                        // 接続線を描画する（オブジェクトの後ろに描画）。
                        ...state.connections.map(
                          (connection) {
                            final source = _objectById(state.objects, connection.sourceId);
                            final target = _objectById(state.objects, connection.targetId);
                            if (source == null || target == null) return const SizedBox.shrink();
                            return Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: ConnectionPainter(
                                    connection: connection,
                                    sourceRect: source.rectInCanvas(),
                                    targetRect: target.rectInCanvas(),
                                    color: connection.color,
                                    isSelected: _selectedConnectionId == connection.id,
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
                            transformationController: _transformationController,
                            connectionMode: _connectionMode,
                            selectionMode: _selectionMode,
                            onConnectionDrag: (dragEnd) {
                              if (!mounted) return;
                              _onConnectionDrag(note.id, dragEnd);
                            },
                            onConnectionDragEnd: () {
                              if (!mounted) return;
                              _onConnectionEnd(note.id);
                            },
                          ),
                        ),
                        // 接続モードでドラッグ中にプレビュー線を描画する。
                        if (_connectionMode && _dragSourceId != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: ConnectionPreviewPainter(
                                  start: _dragSourceId != null
                                      ? (_objectById(state.objects, _dragSourceId!)!.position +
                                          _objectById(state.objects, _dragSourceId!)!.size.center(Offset.zero))
                                      : Offset.zero,
                                  end: _dragEnd,
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
          if (_debugMode)
            AnimatedBuilder(
              animation: _tapIndicatorController,
              builder: (context, _) {
                final box = _bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null) return const SizedBox.shrink();
                
                final localPos = box.globalToLocal(_tapIndicatorPos);
                final t = _tapIndicatorController.value;
                
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
            child: _BuildHintCard(
              debugMode: _debugMode,
              onTap: () => setState(() => _debugMode = !_debugMode),
              cursorScreen: _cursorScreen,
              tapScreen: _tapScreen,
              tapLocal: _tapLocal,
              tapCanvas: _tapCanvas,
              visibleCanvasBounds: _visibleCanvasBounds,
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: _ZoomControlPanel(
              transformationController: _transformationController,
            ),
          ),
        ],
      ),
    );
  }
}

/// ズーム（拡大/縮小）とリセットを行うボタンパネル。
class _ZoomControlPanel extends StatelessWidget {
  final TransformationController transformationController;

  const _ZoomControlPanel({required this.transformationController});

  double _currentScale() {
    final m = transformationController.value;
    return (m.entry(0, 0) + m.entry(1, 1)) / 2;
  }

  void _zoom(double factor, BuildContext context) {
    final current = _currentScale();
    final next = (current * factor).clamp(0.1, 5.0);

    // 画面中央をズームの中心にする
    final viewport = MediaQuery.of(context).size;
    final center = Offset(viewport.width / 2, viewport.height / 2);

    final m = transformationController.value;
    final tx = m.entry(0, 3);
    final ty = m.entry(1, 3);

    // 画面中央のキャンバス座標を計算
    final canvasX = (center.dx - tx) / current;
    final canvasY = (center.dy - ty) / current;

    // 画面中央が同じキャンバス座標に来るように並進を調整
    final newTx = center.dx - next * canvasX;
    final newTy = center.dy - next * canvasY;

    final newMatrix = Matrix4.identity()
      ..setEntry(0, 0, next)
      ..setEntry(1, 1, next)
      ..setEntry(0, 3, newTx)
      ..setEntry(1, 3, newTy);
    transformationController.value = newMatrix;
  }

  void _reset(BuildContext context) {
    // キャンバスの中心を画面中央に移動する
    final viewport = MediaQuery.of(context).size;
    final translateX = (viewport.width - kCanvasSize.width) / 2;
    final translateY = (viewport.height - kCanvasSize.height) / 2;
    transformationController.value = Matrix4.translationValues(translateX, translateY, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '縮小',
              icon: const Icon(Icons.remove),
              onPressed: () => _zoom(0.8, context),
            ),
            IconButton(
              tooltip: '拡大',
              icon: const Icon(Icons.add),
              onPressed: () => _zoom(1.25, context),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'リセット',
              icon: const Icon(Icons.center_focus_strong),
              onPressed: () => _reset(context),
            ),
            const SizedBox(width: 4),
            // ズーム率をリアルタイム表示
            AnimatedBuilder(
              animation: transformationController,
              builder: (context, _) {
                final scale = _currentScale();
                return Text(
                  '${(scale * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 右下に表示される操作説明カード（デバッグ情報付き）。
///
/// カード自体をタップするとデバッグモードがトグルされる。
class _BuildHintCard extends StatelessWidget {
  /// デバッグモードの有効状態。true のとき座標情報を表示する。
  final bool debugMode;

  /// カードをタップしたときに呼び出される（デバッグモードのトグル）。
  final VoidCallback onTap;

  final Offset cursorScreen;
  final Offset tapScreen;
  final Offset tapLocal;
  final Offset tapCanvas;
  final Rect visibleCanvasBounds;

  const _BuildHintCard({
    required this.debugMode,
    required this.onTap,
    required this.cursorScreen,
    required this.tapScreen,
    required this.tapLocal,
    required this.tapCanvas,
    required this.visibleCanvasBounds,
  });

  String _fmt(Offset offset) {
    return '(${offset.dx.round()}, ${offset.dy.round()})';
  }

  Future<String> _getAppVersion() async
  {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ダブルタップ: 追加\n長押し: 追加\nピンチ: ズーム\nドラッグ: パン',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
            // デバッグモードのときだけ座標情報を表示する。
            if (debugMode) ...[
              const SizedBox(height: 8),
              Text(
                'カーソル: ${_fmt(cursorScreen)}',
                style: const TextStyle(color: Colors.yellow, fontSize: 11),
              ),
              Text(
                'タップ(画面): ${_fmt(tapScreen)}',
                style: const TextStyle(color: Colors.green, fontSize: 11),
              ),
              Text(
                'タップ(ローカル): ${_fmt(tapLocal)}',
                style: const TextStyle(color: Colors.green, fontSize: 11),
              ),
              Text(
                'タップ(キャンバス): ${_fmt(tapCanvas)}',
                style: const TextStyle(color: Colors.green, fontSize: 11),
              ),
              Text(
                '表示範囲(左上): ${_fmt(Offset(visibleCanvasBounds.left, visibleCanvasBounds.top))}',
                style: const TextStyle(color: Colors.cyan, fontSize: 11),
              ),
              Text(
                '表示範囲(右下): ${_fmt(Offset(visibleCanvasBounds.right, visibleCanvasBounds.bottom))}',
                style: const TextStyle(color: Colors.cyan, fontSize: 11),
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white24, height: 6),
              // コピーライトの表示。コピーライトをタップすると showLicensePage() を表示する。
              const SizedBox(height: 2),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final appVersion = await _getAppVersion();
                  // BuildContextがまだ有効かチェック
                  if (!context.mounted) return;
                  showLicensePage(
                    context: context,
                    applicationIcon: Image.asset('assets/icons/memoma3_icon.png', width: 48, height: 48),
                    applicationVersion: appVersion,
                    applicationLegalese: '©2026- GOKIGEN Project.'
                  );
                },
                child: const Text(
                  '©2026- GOKIGEN Project.',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

/// 接続線のコンテキストメニューを、**実際の高さを計測して**画面内に収める位置へ配置する。
///
/// 従来の実装はメニュー高さを推測値（260px）でハードコードしており、
/// 実際の高さ（約 320px）より小さかったため、画面下部で開いた際に
/// 「接続線を解除」が画面外にはみ出してタップできない問題があった。
///
/// 本ウィジェットは、子メニューのレイアウト後に [GlobalKey] で実際の高さを
/// 取得し、タップ位置（[screenPos]）の右下を基本に、画面からはみ出す場合は
/// 左上側に反転させて、最終的に画面内に収まるよう位置を補正する。
class _ConnectionMenuPositioner extends StatefulWidget {
  final Offset screenPos;
  final double menuWidth;
  final double margin;
  final double initialLeft;
  final double initialTop;
  final Widget child;

  const _ConnectionMenuPositioner({
    required this.screenPos,
    required this.menuWidth,
    required this.margin,
    required this.initialLeft,
    required this.initialTop,
    required this.child,
  });

  @override
  State<_ConnectionMenuPositioner> createState() =>
      _ConnectionMenuPositionerState();
}

class _ConnectionMenuPositionerState extends State<_ConnectionMenuPositioner> {
  final GlobalKey _menuKey = GlobalKey();
  double? _measuredHeight;

  /// 実際の高さ（未計測時は推測値）を返す。
  double get _height => _measuredHeight ?? 320.0;

  /// 画面内に収まるよう、タップ位置の右下 / 左上を切り替えて位置を計算する。
  (double left, double top) _computePosition(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = widget.menuWidth;
    final h = _height;
    final m = widget.margin;
    final sx = widget.screenPos.dx;
    final sy = widget.screenPos.dy;

    // デフォルトはタップ位置の右下。
    double left = sx + m;
    double top = sy + m;

    // 右端からはみ出す場合は左側に、下端からはみ出す場合は上側に反転。
    if (left + w > size.width) {
      left = sx - m - w;
    }
    if (top + h > size.height) {
      top = sy - m - h;
    }

    // 最終的に画面内に収める（負の方向にはみ出す場合も補正）。
    left = left.clamp(0.0, (size.width - w).clamp(0.0, double.infinity)).toDouble();
    top = top.clamp(0.0, (size.height - h).clamp(0.0, double.infinity)).toDouble();

    return (left, top);
  }

  @override
  Widget build(BuildContext context) {
    // 初回フレームでは実際の高さが未計測のため、推測値で配置する。
    // レイアウト後に _measureHeight が呼ばれ、実際の高さで再配置される。
    final (left, top) = _computePosition(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          top: top,
          child: RepaintBoundary(
            key: _menuKey,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  /// メニューの実際の高さを計測し、必要なら位置を補正して再描画する。
  void _measureHeight() {
    final renderBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final actualHeight = renderBox.size.height;
    if (_measuredHeight == null ||
        (_measuredHeight! - actualHeight).abs() > 0.5) {
      setState(() {
        _measuredHeight = actualHeight;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // レイアウトが確定した後に高さを計測する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureHeight();
    });
  }
}
