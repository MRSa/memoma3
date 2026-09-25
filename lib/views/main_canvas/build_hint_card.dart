import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 右下に表示される操作説明カード（デバッグ情報付き）。
///
/// カード自体をタップするとデバッグモードがトグルされる。
class BuildHintCard extends StatelessWidget {
  /// デバッグモードの有効状態。true のとき座標情報を表示する。
  final bool debugMode;

  /// カードをタップしたときに呼び出される（デバッグモードのトグル）。
  final VoidCallback onTap;

  final Offset cursorScreen;
  final Offset tapScreen;
  final Offset tapLocal;
  final Offset tapCanvas;
  final Rect visibleCanvasBounds;

  const BuildHintCard({
    super.key,
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

  Future<String> _getAppVersion() async {
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
