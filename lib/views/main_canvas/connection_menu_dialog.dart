import 'package:flutter/material.dart';

import '../../models/connection.dart';
import '../widgets/connection_menu.dart';
import 'connection_menu_positioner.dart';
import 'main_canvas_state.dart';

/// 接続線のコンテキストメニューを表示する。
///
/// [showDialog] は builder の結果を [Dialog]（内部に [Padding] を持つ）で
/// ラップするため、[Positioned] が [Stack] の直接の子にならず
/// 「Incorrect use of ParentDataWidget」例外が発生する。
/// そこで [DialogRoute] の [builder] を使い、画面全体を埋める
/// [Stack] の直接の子として [Positioned] を配置する。
///
/// [state] は [MainCanvasState] mixin を適用した state で、メニュー閉じ後の
/// 選択解除に [state.clearSelectedConnection] を使用する。
Future<void> showConnectionMenuDialog(
  MainCanvasState state,
  BuildContext context,
  Connection connection,
  Offset screenPos,
) async {
  final size = MediaQuery.of(context).size;

  // メニューの幅と、タップ位置（線が通る位置）からの余白。
  // 線との重なりを避けるため、十分な距離を取る。
  const menuWidth = 220.0;
  const margin = 40.0;
  // 高さの概算値（初回フレーム用の初期配置）。実際の高さは
  // ConnectionMenuPositioner がレイアウト後に計測して補正する。
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
        return ConnectionMenuPositioner(
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
  state.clearSelectedConnection();
}
