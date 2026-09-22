# memoma3 詳細設計書（各クラスの役割）

本ドキュメントは、`lib/` 配下の各クラス・ウィジェットが担う役割と、主要なプロパティ・メソッドをまとめた詳細設計書です。

## 1. models（データ層）

### 1.1 `NoteObject`（`models/note_object.dart`）

- **役割**: キャンバス上の 1 つのオブジェクト（メモ）を表す不変データクラス。
- **プロパティ**: `id`, `position`, `size`, `content`, `label`, `detail`, `color`, `shape`, `emphasis`, `labelColor?`, `descriptionColor?`, `scale`（0.5〜4.0、既定 1.0）, `labelFontSizeLevel`（1〜5、既定 3）, `descriptionFontSizeLevel`（1〜5、既定 2）, `isSelected`。
- **主要メソッド**:
  - `copyWith(...)`: 一部フィールドを差し替えた複製を生成。
  - `rectInCanvas()`: `size × scale` のキャンバス矩形を返す。接続線・グループ枠・整列・エクスポートの基準になる。
  - `toJson()` / `fromJson(...)`: JSON へのシリアライズ・デシリアライズ（`scale` / `labelFontSizeLevel` / `descriptionFontSizeLevel` は旧データにキーがない場合既定値でフォールバック）。
- **関連定数**: `kDisplayShapes`（新規作成時に選択可能な形状のリスト。cloud / trapezium を除く）、`kObjectScales`（サイズ倍率 0.5〜4.0）、`kMinFontSizeLevel` / `kMaxFontSizeLevel`（1〜5）、`fontSizeForLevel(int)`（レベル→px 変換、12〜24px）。

### 1.2 `NoteShape`（`models/note_object.dart`）

- **役割**: オブジェクトの形状を列挙。
- **値**: `roundedRect`, `rectangle`, `ellipse`, `cloud`, `parallelogram`, `trapezoid`, `trapezium`, `hexagon`, `pentagonLeft`, `pentagonRight`, `pentagonUp`, `pentagonDown`, `circle`, `square`。
- **プロパティ**: `displayName`（日本語表示名）。

### 1.3 `Emphasis`（`models/note_object.dart`）

- **役割**: 強調レベルを列挙。
- **値**: `normal`（標準）, `strong`（強調）, `weak`（弱め）。
- **プロパティ**: `displayName`。

### 1.4 `Connection`（`models/connection.dart`）

- **役割**: 2 つのオブジェクトを結ぶ接続線を表す不変データクラス。
- **プロパティ**: `id`, `sourceId`, `targetId`, `lineType`, `lineShape`, `color`。
- **主要メソッド**: `copyWith(...)`, `toJson()` / `fromJson(...)`。

### 1.5 `LineType` / `LineShape`（`models/connection.dart`）

- **役割**: 接続線の線種・形状を列挙。
- **`LineType`**: `normal`, `thick`, `dotted`, `dashDot`。
- **`LineShape`**: `arrow`, `straight`, `elbow`, `curve`, `doubleArrow`, `reverseArrow`。
- **プロパティ**: `displayName`。

### 1.6 `GroupFrame`（`models/connection.dart`）

- **役割**: 複数のオブジェクトをまとめるグループ枠を表す不変データクラス。
- **プロパティ**: `id`, `memberIds`, `name`, `description`, `color`。
- **主要メソッド**: `copyWith(...)`, `toJson()` / `fromJson(...)`。

### 1.7 `BackgroundConfig`（`models/background_config.dart`）

- **役割**: 背景ガイド（グリッド・背景色・背景画像）の設定を表す不変データクラス。
- **プロパティ**: `gridType`, `gridSpacing`, `gridColor`, `gridOpacity`, `backgroundColor`, `backgroundOpacity`, `backgroundImagePath?`, `backgroundImageOpacity`。
- **主要メソッド**: `copyWith(...)`, `toJson()` / `fromJson(...)`。

### 1.8 `GridType`（`models/background_config.dart`）

- **役割**: グリッドの種類を列挙。
- **値**: `none`（なし）, `lines`（罫線）, `dots`（ドット）。
- **プロパティ**: `displayName`。

## 2. providers（状態・ロジック層）

### 2.1 `CanvasState`（`providers/canvas_state.dart`）

- **役割**: キャンバスの全状態（オブジェクト・接続線・グループ・選択・履歴）を保持する不変データクラス。
- **プロパティ**: `objects`, `connections`, `groupFrames`, `selectedId`, `history`, `redoStack`, `maxHistory`。
- **主要メソッド**:
  - `copyWith(...)`: 状態の複製。
  - `pushHistory(state)`: 操作前の状態を履歴にプッシュ（同一状態の連続プッシュを省略、新しい操作で Redo スタックをクリア）。
  - `toJson()` / `fromJson(...)`: JSON へのシリアライズ・デシリアライズ。

### 2.2 `CanvasNotifier`（`providers/canvas_provider.dart`）

- **役割**: キャンバス状態を管理する `Notifier`。オブジェクト・接続線・グループの CRUD、選択、整列、Undo/Redo、ドラッグ中のローカル状態を担当。
- **ドラッグ関連フィールド**: `localDraftPositions`, `dragStartPositions`, `dragStartCanvas`, `lastAddedId`, `lastShape`。
- **主要メソッド**:
  - **オブジェクト**: `addObject`, `updatePosition`, `endDrag`, `setPosition`, `cancelDrag`, `resetDraft`, `clearLocalDrafts`, `bringToFront`, `editObject`, `deleteObject`, `deleteSelected`, `deleteAllObjects`, `makeNewNote`, `updateLastShape`, `duplicateSelected`（選択分複製、右下 20px ずらし・接続線/グループ非引き継ぎ）, `duplicateObject`（単一オブジェクト複製、一覧行用）。
  - **選択**: `selectObject`, `toggleSelect`, `selectAll`, `clearSelection`, `_setAllSelected`。
  - **整列**: `alignSelectedToStep`, `alignSelected`。
  - **接続線**: `addConnection`, `connectSelected`, `updateConnection`, `deleteConnection`。
  - **グループ**: `createGroup`, `addToGroup`, `updateGroup`, `deleteGroup`, `moveGroup`, `endGroupDrag`, `resetGroupDrafts`。
  - **Undo/Redo**: `undo`, `redo`。
  - **永続化**: `loadFromJson`, `exportToJson`, `_deduplicateConnectionIds`, `_deduplicateGroupIds`。
  - **内部**: `_snap`（位置の丸め）。

### 2.3 `CanvasNameNotifier`（`providers/canvas_provider.dart`）

- **役割**: キャンバス名を管理する `Notifier`。
- **状態**: `String`（キャンバス名）。

### 2.4 `BackgroundConfigNotifier`（`providers/canvas_provider.dart`）

- **役割**: 背景ガイド設定を管理する `Notifier`。`shared_preferences` への永続化と復元を担当。
- **状態**: `BackgroundConfig`。

### 2.5 `AlignMode`（`providers/canvas_provider.dart`）

- **役割**: 整列モードを列挙。
- **値**: `left`, `right`, `top`, `bottom`, `distributeHorizontal`, `distributeVertical`。

## 3. services（I/O・永続化層）

### 3.1 `StorageService`（`services/storage_service.dart`）

- **役割**: キャンバス状態の JSON 保存・読み込みを担当。`file_picker` を用いてプラットフォーム差を吸収。
- **主要メソッド**: 保存（ファイル選択 → JSON 書き出し）、読み込み（ファイル選択 → JSON 読み込み → `CanvasState` 復元）。

### 3.2 `CanvasExportService`（`services/canvas_export_service.dart`）

- **役割**: キャンバスを PNG / PDF にエクスポート。
- **要点**: 描画サイズは `ceil()` で整数化し、背景塗りつぶしと `toImage` のサイズを一致させることで、エクスポート画像下端の白い線（透明ピクセル）を防止。

### 3.3 `BackgroundPersistenceService`（`services/background_persistence_service.dart`）

- **役割**: 背景ガイド設定の `shared_preferences` への永続化・復元。
- **キー**: `memoma3.background_config`。

### 3.4 `CanvasPersistenceService`（`services/canvas_persistence_service.dart`）

- **役割**: キャンバス状態（オブジェクト・接続線・グループ）とキャンバス名を `hive_ce` に自動・逐次で永続化・復元する。
- **box / キー**: box 名 `memoma3_canvas`、キー `state`（状態 JSON）と `name`（キャンバス名）。
- **主要メソッド**:
  - `saveState(CanvasState)` / `loadState()` — 状態 JSON の書き込み・読み出し。
  - `saveName(String)` / `loadName()` — キャンバス名の書き込み・読み出し。
  - `scheduleSaveState(CanvasState)` — **400ms デバウンス**付きの非同期保存。高頻度の状態変更（ドラッグ等）をまとめて書き込む。
  - `flush()` — デバウンス待ちのデータを即座に書き込む（アプリ終了時）。
  - `clear()` — box の全消去。
- **接続**: `MainCanvasScreen` が `ref.listen(canvasNotifierProvider, ...)` で状態変更を検知し `scheduleSaveState` を呼ぶ。`didChangeAppLifecycleState` で `paused` / `hidden` 時に `flush()`。起動時 `initState` で `loadName` / `loadState` を復元。
- **初期化**: `main.dart` で `Hive.init`（Web はパス不要、それ以外は `path_provider` のアプリケーションサポートディレクトリ）。

## 4. views（画面層）

### 4.1 `MainCanvasScreen`（`views/main_canvas_screen.dart`）

- **役割**: アプリのメイン画面。キャンバスの描画、パン・ズーム、オブジェクト操作、接続モード、整列、エクスポート、背景設定の入口。
- **定数**: `kCanvasSize = Size(50000, 50000)`。
- **描画順序（Z 順）**: 背景色 → 背景画像 → グリッド → グループ枠 → 接続線 → オブジェクト。
- **内部ウィジェット**: `_ZoomControlPanel`（ズーム操作パネル）。

### 4.2 `ObjectListScreen`（`views/object_list_screen.dart`）

- **役割**: オブジェクト一覧画面。全オブジェクトの属性を表示・編集し、CSV エクスポートを提供。
- **列**: No. / 名称（左固定）+ 説明 / 詳細 / グループ / 形状 / 強調 / 色 / 接続(from/to) / X / Y / サイズ / 中心 / 複製 / 削除（右スクロール）。
- **フィルタ**: 名称（テキスト）、形状（複数選択）、強調（複数選択）。
- **ソート**: 列ヘッダクリックで昇降順切替（サイズ列もソート対象）。
- **複製**: 行の「複製」ボタンで `duplicateObject(id)` を呼び、そのオブジェクトを複製（右下 20px ずらし）。
- **CSV**: `_buildCsv`（UTF-8 BOM 付き、`_csvEscape` でエスケープ、`_colorToHex` で #RRGGBB、サイズ列は `1.0倍` 形式）。

## 5. widgets（部品層）

### 5.1 `TopActionBar`（`widgets/top_action_bar.dart`）

- **役割**: 上部アクションバー。操作カテゴリごとに区切り線で分類し、以下の順で配置: 読み込み / 保存 / 画像・PDF エクスポート | Undo / Redo | オブジェクト数 / 操作数 | キャンバス名 | 整列 / 接続 / 編集 | 削除 / 全削除 | グループ化 / 接続モード / 選択モード / 全選択 | オブジェクト一覧 / 背景ガイド設定。
- **選択モード**: 「選択モード」ボタンでキーボードのない環境向けの複数選択モードを切替。「全選択」ボタンは常時表示され、選択モード中かつオブジェクトがあるときのみ有効。

### 5.2 `NoteObjectWidget`（`widgets/note_object_widget.dart`）

- **役割**: 1 つのオブジェクトを描画するウィジェット。ドラッグ・選択・ダブルタップ（編集ダイアログ）を担当。
- **選択モード**: `selectionMode` が true のとき、タップ/ダブルタップ/長押しで選択をトグル（複数選択）、ドラッグ移動・編集ダイアログは行わない。キーボードのない環境（Android 等）で Ctrl+タップに代わる操作。
- **描画**: `NoteShapePainter` で形状背景を描画し、テキスト（ラベル・本文・説明）を配置。

### 5.3 `NoteShapePainter`（`widgets/note_shape_painter.dart`）

- **役割**: オブジェクト形状の背景を描画する `CustomPainter`。選択時は四隅の枠線で強調表示。

### 5.4 `ObjectEditDialog`（`widgets/object_edit_dialog.dart`）

- **役割**: オブジェクトの編集ダイアログ。上段に「強調 / 色 / フォントサイズ」の 3 カラム、下段に「サイズ」、その後に形状・ラベル・説明・詳細を配置。
- **フォントサイズ**: ラベル・説明それぞれ `DropdownButton` で 1〜5 段階を選択（選択肢に px 表示、例: `3 (18px)`）。
- **サイズ**: 0.5 倍〜4.0 倍のチップボタン（`kObjectScales`）。
- **色**: `MyCustomColorPicker.showAsDialog` で本体色・ラベル色・説明色を選択。

### 5.5 `ConnectionPainter`（`widgets/connection_painter.dart`）

- **役割**: 接続線を描画する `CustomPainter`。オブジェクトの境界間を結ぶパスを構築し、線種・形状・色を反映。

### 5.6 `ConnectionPreviewPainter`（`widgets/connection_preview_painter.dart`）

- **役割**: 接続モード中のドラッグプレビュー線を描画する `CustomPainter`。

### 5.7 `ConnectionContextMenu`（`widgets/connection_menu.dart`）

- **役割**: 接続線のコンテキストメニュー。線種・形状・色の設定、削除を提供。

### 5.8 `GroupFrameWidget`（`widgets/group_frame_widget.dart`）

- **役割**: グループ枠を描画・操作するウィジェット。ドラッグで移動、メンバーの追加・削除を担当。
- **描画**: `GroupFramePainter` で矩形枠を描画。
- **ネスト対応**: `margin` パラメータ（既定 24px）で枠の内側余白を制御。ネストしたグループは外側ほど margin を大きくし（`24 + nestingDepth * 20` px）、境界線が重ならないようにする。

### 5.9 `GroupFramePainter`（`widgets/group_frame_painter.dart`）

- **役割**: グループ枠（矩形枠）を描画する `CustomPainter`。

### 5.10 `GroupEditDialog`（`widgets/group_edit_dialog.dart`）

- **役割**: グループの編集ダイアログ。名称・説明・枠線の色を設定。

### 5.11 `BackgroundGridOverlay`（`widgets/background_grid_painter.dart`）

- **役割**: 背景グリッド（罫線 / ドット）を描画するオーバーレイ。ビューポート固定で描画。
- **描画**: `BackgroundGridPainter`（`CustomPainter`）。

### 5.12 `BackgroundSettingsDialog`（`widgets/background_settings_dialog.dart`）

- **役割**: 背景ガイド設定ダイアログ。グリッド種類・間隔・色・不透明度、背景色・不透明度、背景画像・不透明度を設定。
- **色**: `MyCustomColorPicker.showAsDialog` で背景色・背景画像色を選択。
- **Slider**: Flutter バグ #190357 の回避のため `Overlay.wrap(alwaysSizeToContent: true, clipBehavior: Clip.none, ...)` でラップ。

### 5.13 `MyCustomColorPicker`（`views/widgets/my_custom_color_picker.dart`）

- **役割**: `flex_color_picker` の `ColorPicker` をラップする共通カラーピッカー。
- **API**: `MyCustomColorPicker.showAsDialog(context, initialColor:, title:)` → `Future<Color?>`（OK で選択色、キャンセルで `null`）。
- **有効化**: カラーホイール・シェード選択・カラーコード表示（編集可）・コピー＆ペースト・OK/キャンセルボタン。
- **使用箇所**: オブジェクト一覧・背景設定ダイアログ・接続線コンテキストメニュー・グループ編集ダイアログ・オブジェクト編集ダイアログの 5 箇所の `_pickColor`。
- **注意**: `flex_color_picker` 4.0.0 は `material_ui` パッケージに依存するため、`main.dart` の `localizationsDelegates` に `material_ui.GlobalMaterialLocalizations.delegate` を追加している。

## 6. 依存関係のまとめ

```text
MainCanvasScreen
├── TopActionBar
├── NoteObjectWidget ── NoteShapePainter
├── GroupFrameWidget ── GroupFramePainter
├── ConnectionPainter
├── ConnectionPreviewPainter
├── BackgroundGridOverlay ── BackgroundGridPainter
├── ObjectEditDialog
├── GroupEditDialog
├── BackgroundSettingsDialog
└── ConnectionContextMenu

ObjectListScreen
└── (CSV エクスポートロジック)

CanvasNotifier ── CanvasState
├── StorageService
├── CanvasExportService
└── BackgroundPersistenceService
```
