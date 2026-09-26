import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'main_canvas/main_canvas_state.dart';
import 'main_canvas/main_canvas_ui.dart';

/// キャンバスのサイズ（px）。広大なキャンバスとして構成する。
const Size kCanvasSize = Size(50000, 50000);

/// キャンバスを表示するメイン画面。
///
/// ロジック（フィールド / ライフサイクル / 座標変換 / モード切替 /
/// グループ枠 / 接続線）は [MainCanvasState]、UI（[build]）は [MainCanvasUi]
/// に分離されている。
class MainCanvasScreen extends ConsumerStatefulWidget {
  const MainCanvasScreen({super.key});

  @override
  ConsumerState<MainCanvasScreen> createState() => _MainCanvasScreenState();
}

class _MainCanvasScreenState extends ConsumerState<MainCanvasScreen>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        MainCanvasState,
        MainCanvasUi {}
