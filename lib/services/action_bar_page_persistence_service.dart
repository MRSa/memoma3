import 'package:shared_preferences/shared_preferences.dart';

/// トップアクションバーの表示ページ（左 / 右）をアプリ内で記憶するサービス。
///
/// [shared_preferences] を用いてページをキー/値で保存し、次回起動時にも
/// そのページが維持されるようにする。[BackgroundPersistenceService] と同様の
/// パターンで実装する。
class ActionBarPagePersistenceService {
  /// 保存キー。
  static const String _key = 'memoma3.action_bar_page';

  /// 左ページの値。
  static const String pageLeft = 'left';

  /// 右ページの値。
  static const String pageRight = 'right';

  /// 現在の表示ページを読み込む。未設定（初回起動）または破損データの場合は
  /// [pageLeft] を返す。
  Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == pageRight) return pageRight;
    return pageLeft;
  }

  /// 表示ページを保存する。[page] は [pageLeft] または [pageRight]。
  Future<void> save(String page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, page);
  }
}
