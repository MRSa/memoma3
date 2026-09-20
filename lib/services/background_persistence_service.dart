import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/background_config.dart';

/// 背景ガイド設定をアプリ内で記憶するサービス。
///
/// [shared_preferences] を用いて設定をキー/値で保存し、次回起動時にも
/// その設定が維持されるようにする。保存形式は [BackgroundConfig] の
/// JSON 文字列（単一キー）で、後方互換性を持たせる。
class BackgroundPersistenceService {
  /// 背景設定を保存するキー。
  static const String _key = 'memoma3.background_config';

  /// 現在の背景設定を読み込む。未設定（初回起動）の場合は
  /// [BackgroundConfig.initial] を返す。
  Future<BackgroundConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return BackgroundConfig.initial;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return BackgroundConfig.fromJson(decoded);
    } catch (_) {
      // 破損データは初期値で安全にフォールバックする。
      return BackgroundConfig.initial;
    }
  }

  /// 背景設定を保存する。
  Future<void> save(BackgroundConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }

  /// 背景設定を初期値（リセット）に戻す。
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
