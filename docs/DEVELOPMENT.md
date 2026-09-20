# memoma3 開発手順

本ドキュメントは、ファイル構造、依存パッケージ、ビルド方法など、開発に必要な情報をまとめます。

## 1. 開発環境

| 項目 | バージョン / パス |
| --- | --- |
| OS | Windows |
| Dart SDK | `^3.13.2` |
| Flutter | `flutter.bat`（PATH に登録されていない場合、フルパスで実行） |
| Python（アイコン生成用） | `Spython.exe`（Python 3.14.x） |
| 依存管理 | `pub`（`pubspec.yaml`） |

> **注意**: `flutter.bat` は PATH に登録されていない場合があります。その場合はフルパスで実行してください。

## 2. ファイル構造

```text
memoma3/
├── pubspec.yaml                  # 依存パッケージ・アセット定義
├── analysis_options.yaml         # Lint 設定（flutter_lints）
├── README.md                     # プロジェクト概要
├── docs/                         # ドキュメント
│   ├── SPECIFICATION.md          # 機能仕様書
│   ├── ARCHITECTURE.md           # 概略設計書
│   ├── DETAILED_DESIGN.md        # 詳細設計書
│   ├── MANUAL.md                 # 操作説明書
│   ├── JSON.md                   # JSON 保存ファイル仕様
│   ├── CSV.md                    # CSV 出力仕様
│   └── DEVELOPMENT.md            # 本ドキュメント
├── images/
│   └── memoma3_icon.svg          # アプリアイコンの SVG ソース
├── tools/
│   └── convert_icon.py           # アイコン生成スクリプト（SVG → PNG/ICO）
├── lib/
│   ├── main.dart                 # エントリポイント（Memoma3App）
│   ├── models/                   # データ層
│   │   ├── note_object.dart      # NoteObject, NoteShape, Emphasis
│   │   ├── connection.dart       # Connection, GroupFrame, LineType, LineShape
│   │   └── background_config.dart# BackgroundConfig, GridType
│   ├── providers/                # 状態・ロジック層
│   │   ├── canvas_state.dart     # CanvasState
│   │   └── canvas_provider.dart  # CanvasNotifier, CanvasNameNotifier, BackgroundConfigNotifier, AlignMode
│   ├── services/                 # I/O・永続化層
│   │   ├── storage_service.dart          # JSON 保存・読み込み
│   │   ├── canvas_export_service.dart    # PNG / PDF エクスポート
│   │   └── background_persistence_service.dart # 背景設定の永続化
│   ├── views/                    # 画面層
│   │   ├── main_canvas_screen.dart       # メインキャンバス画面
│   │   ├── object_list_screen.dart       # オブジェクト一覧画面
│   │   └── widgets/              # 部品層
│   │       ├── top_action_bar.dart
│   │       ├── note_object_widget.dart
│   │       ├── note_shape_painter.dart
│   │       ├── object_edit_dialog.dart
│   │       ├── connection_painter.dart
│   │       ├── connection_preview_painter.dart
│   │       ├── connection_menu.dart
│   │       ├── group_frame_widget.dart
│   │       ├── group_frame_painter.dart
│   │       ├── group_edit_dialog.dart
│   │       ├── background_grid_painter.dart
│   │       └── background_settings_dialog.dart
│   └── widgets/                  # （共通ウィジェット）
├── test/
│   └── widget_test.dart          # ウィジェットテスト
├── web/                          # Web ビルド
│   ├── index.html
│   ├── manifest.json
│   └── icons/                    # Web アイコン（Icon-192/512, maskable, favicon）
├── windows/                      # Windows ビルド
│   ├── CMakeLists.txt
│   ├── runner/
│   │   └── resources/app_icon.ico
│   └── flutter/
└── android/                      # Android ビルド
    ├── app/src/main/res/mipmap-*/ic_launcher.png
    └── ...
```

## 3. 依存パッケージ

### 3.1 本番依存（`dependencies`）

| パッケージ | バージョン | 用途 |
| --- | --- | --- |
| `flutter` | sdk | Flutter フレームワーク |
| `cupertino_icons` | `^1.0.8` | Cupertino アイコンフォント |
| `flutter_riverpod` | `^3.0.0` | 状態管理（Notifier / NotifierProvider） |
| `file_picker` | `^13.1.0` | クロスプラットフォームのファイル選択（保存・読み込み・エクスポート） |
| `path` | `^1.9.1` | パス操作 |
| `vector_math` | `^2.4.0` | `Matrix4` / `Vector4`（InteractiveViewer の変換行列演算） |
| `flex_color_picker` | `^4.0.0` | 色ピッカー（オブジェクト・接続線・背景の色設定） |
| `url_launcher` | `^6.3.0` | http(s) リンクをブラウザで開く |
| `pdf` | `^3.10.8` | キャンバス状態の PDF エクスポート |
| `shared_preferences` | `^2.5.3` | 背景ガイド設定の永続化 |
| `hive_ce` | `^2.20.0` | （予約）ローカルデータストア。現時点では `lib/` 内で未使用 |

### 3.2 開発依存（`dev_dependencies`）

| パッケージ | バージョン | 用途 |
| --- | --- | --- |
| `flutter_test` | sdk | ウィジェットテスト |
| `flutter_lints` | `^6.0.0` | Lint ルールセット |

> **注**: `hive_ce` は `pubspec.yaml` に宣言されていますが、現時点では `lib/` 内で使用されていません。将来のローカルデータストア用途で予約されています。

### 3.3 アセット

- `web/icons/Icon-512.png`: アプリのアイコン（エクスポート画像のヘッダーに表示）。`pubspec.yaml` の `assets` に登録されています。

## 4. ビルド方法

### 4.1 依存パッケージの取得

```powershell
flutter.bat pub get
```

### 4.2 静的解析（Lint）

```powershell
flutter.bat analyze
```

- 正常時は `No issues found!` が表示されます。

### 4.3 テスト

```powershell
flutter.bat test
```

### 4.4 実行（開発）

```powershell
# Windows デスクトップ
flutter.bat run -d windows

# Web（Chrome）
flutter.bat run -d chrome
```

### 4.5 本番ビルド

```powershell
# Windows
flutter.bat build windows

# Web
flutter.bat build web

# Android（APK）
flutter.bat build apk
```

## 5. アイコンの再生成

アプリアイコンは `images/memoma3_icon.svg` をソースとして、`tools/convert_icon.py` で生成します。

### 5.1 前提

- Python 3.14.x
- `Pillow`（`pip install Pillow`）
- Chrome または Edge（ヘッドレスレンダリング用）

### 5.2 実行

```powershell
spython.exe tools/convert_icon.py
```

### 5.3 生成物

| ファイル | 用途 | 背景 |
| --- | --- | --- |
| `web/icons/Icon-192.png` | Web アイコン | 白 |
| `web/icons/Icon-512.png` | Web アイコン | 白 |
| `web/icons/Icon-maskable-192.png` | Web マスク可能アイコン（中央 80% セーフゾーン） | 白 |
| `web/icons/Icon-maskable-512.png` | Web マスク可能アイコン（中央 80% セーフゾーン） | 白 |
| `web/favicon.png` | Web ファビコン（64px） | 白 |
| `windows/runner/resources/app_icon.ico` | Windows アイコン（16〜256px） | 透過 |
| `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` | Android ランチャーアイコン | 透過 |

> **注**: Windows / Android のアイコンは背景を透過（`transparent`）で生成します。Web のアイコンは背景を白（`#ffffff`）で生成します。

## 6. 開発時の注意事項

- **Flutter のフルパス**: `flutter.bat` が PATH にない場合は、インストールした絶対パスを使用してください。
- **ターミナルの一時的なエラー**: `flutter.bat` や PowerShell コマンドが「CommandNotFoundException」を一時的に返すことがあります。その場合は再実行してください。
- **SVG → PNG 変換**: `cairosvg` や `svglib` は Windows でネイティブライブラリ（cairo / rlPyCairo）を必要とするため失敗します。`tools/convert_icon.py` はヘッドレスブラウザ（Chrome / Edge）のスクリーンショット方式で変換します。
- **Lint**: コード変更後は必ず `flutter analyze` を実行し、`No issues found!` を確認してください。
