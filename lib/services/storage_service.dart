import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../providers/canvas_state.dart';

/// キャンバスの状態を JSON として保存・読み込みするサービスクラス。
///
/// プラットフォーム（Windows / Web / Android）の差分を吸収するため、
/// [file_picker] を介したファイル選択・保存・ダウンロードの枠組みを提供する。
class StorageService {
  /// 保存対象の拡張子
  static const String defaultExtension = 'json';

  /// キャンバスの全オブジェクトを JSON 文字列へ変換する。
  String encodeCanvas(CanvasState state) {
    return state.toJson();
  }

  /// JSON 文字列を解析し、CanvasState へ復元する。
  CanvasState decodeCanvas(String jsonString, {int maxHistory = 30}) {
    return CanvasState.fromJson(jsonString, maxHistory: maxHistory);
  }

  /// プラットフォームに応じたファイル保存ダイアログの表示有無を返す。
  bool get _shouldShowSaveDialog {
    // Web はブラウザダウンロードのためダイアログ不要、
    // デスクトップ/モバイルはネイティブダイアログを表示する。
    return !kIsWeb;
  }

  /// 現在のキャンバス状態をファイルに保存する。
  ///
  /// Web 環境ではブラウザ経由でダウンロードを行う。
  /// それ以外の環境では [file_picker] の [pickFiles] で保存先を選択する。
  ///
  /// [fileContent] はエンコード済みの JSON 文字列。
  /// 成功した場合は保存したファイルのパス（Web は null）を返す。
  Future<String?> saveCanvas({
    required String fileContent,
    String fileName = 'memoma3-canvas',
    String extension = defaultExtension,
  }) async {
    if (kIsWeb) {
      await _downloadOnWeb(fileContent: fileContent, fileName: fileName, extension: extension);
      return null;
    }

    final directory = await PlatformSelect.getDirectory();
    final fullFileName = '$fileName.$extension';
    final bytes = Uint8List.fromList(utf8.encode(fileContent));

    if (_shouldShowSaveDialog) {
      // file_picker 12.x の saveFile は Uint8List を受け取り Uri を返す。
      final uri = await FilePicker.saveFile(
        fileName: fullFileName,
        bytes: bytes,
        initialDirectory: directory,
      );
      final path = uri?.toFilePath();
      if (path == null) return null; // キャンセル

      return path;
    } else {
      // ダイアログを表示しない環境（簡易モード）
      final path = p.join(directory ?? '', fullFileName);
      await File(path).writeAsBytes(bytes);
      return path;
    }
  }

  /// 生バイト列（PNG / PDF 等）をファイルに保存する。
  ///
  /// [saveCanvas] と同様にプラットフォーム差分を吸収する。
  /// 成功した場合は保存したファイルのパス（Web は null）を返す。
  Future<String?> saveBytes({
    required Uint8List bytes,
    String fileName = 'memoma3-export',
    String extension = 'png',
  }) async {
    if (kIsWeb) {
      await FilePicker.saveFile(
        fileName: '$fileName.$extension',
        bytes: bytes,
      );
      return null;
    }

    final directory = await PlatformSelect.getDirectory();
    final fullFileName = '$fileName.$extension';

    if (_shouldShowSaveDialog) {
      final uri = await FilePicker.saveFile(
        fileName: fullFileName,
        bytes: bytes,
        initialDirectory: directory,
      );
      final path = uri?.toFilePath();
      if (path == null) return null; // キャンセル
      return path;
    } else {
      final path = p.join(directory ?? '', fullFileName);
      await File(path).writeAsBytes(bytes);
      return path;
    }
  }

  /// ユーザーが選択した JSON ファイルを読み込み、CanvasState へ復元する。
  ///
  /// Web 環境ではブラウザアップロード、それ以外では [file_picker] の
  /// [pickFiles] でファイルを選択する。
  /// 復元結果とファイル名を返す。キャンセルした場合は (null, null) を返す。
  ///
  /// 戻り値は `(state, fileName)` の record。
  /// [fileName] は拡張子を除いたファイル名（例: `my-canvas`）。
  Future<(CanvasState?, String?)> loadCanvas({int maxHistory = 30}) async {
    String? content;
    String? fileName;

    if (kIsWeb) {
      final result = await _readOnWeb();
      content = result.$1;
      fileName = result.$2;
    } else {
      // file_picker 12.x の pickFiles は PlatformFile のリストを返す。
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [defaultExtension],
      );
      final file = files.firstOrNull;
      final path = file?.path;
      if (path == null) return (null, null); // キャンセル

      fileName = p.basenameWithoutExtension(path);
      content = await File(path).readAsString();
    }

    if (content == null || content.isEmpty) return (null, null);

    return (decodeCanvas(content, maxHistory: maxHistory), fileName);
  }

  // ---------------------------------------------------------------------------
  // Web 用（ブラウザ ダウンロード / アップロード）
  // ---------------------------------------------------------------------------

  Future<void> _downloadOnWeb({
    required String fileContent,
    required String fileName,
    required String extension,
  }) async {
    // Web では browser download を行う。
    // file_picker 12.x の saveFile は Web でも対応しているため、
    // Web でも同様の経路を利用する（必要に応じて flutter_web_plugins を追加）。
    await FilePicker.saveFile(
      fileName: '$fileName.$extension',
      bytes: Uint8List.fromList(utf8.encode(fileContent)),
    );
  }

  Future<(String?, String?)> _readOnWeb() async {
    // file_picker 12.x の pickFiles は PlatformFile のリストを返す。
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [defaultExtension],
    );
    final file = files.firstOrNull;
    final path = file?.path;
    if (path == null) return (null, null);
    final fileName = p.basenameWithoutExtension(path);
    return (await File(path).readAsString(), fileName);
  }
}

/// プラットフォームごとの既定ディレクトリを返す。
class PlatformSelect {
  /// デスクトップ/モバイルの既定保存先ディレクトリを返す。
  /// Web では null を返す（[StorageService.saveCanvas] がダウンロード経路を使うため）。
  static Future<String?> getDirectory() async {
    if (kIsWeb) return null;

    if (Platform.isWindows) {
      // ユーザーディレクトリの直下（保証されない場合は Temp を使う）。
      final home = Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) return home;
      return null;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      // 実機では外部ストレージの書き込み権限が必要。
      return Directory.systemTemp.path;
    }

    // その他（macOS/Linux）
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return home;
    return null;
  }
}