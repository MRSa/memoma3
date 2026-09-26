# memoma3 概略設計書（アーキテクチャ）

## 1. 設計方針

- **状態管理**: Riverpod 3.x の `Notifier` / `NotifierProvider` パターン。全状態は不変（immutable）モデルで管理し、`copyWith` で複製を作成。
- **レイヤ構成**: `models`（データ）→ `providers`（状態・ロジック）→ `services`（I/O・永続化）→ `views` / `widgets`（UI）の 4 層。
- **描画**: オブジェクト形状・接続線・グループ枠・背景グリッドは `CustomPainter` で描画。
- **クロスプラットフォーム**: Windows / Web / Android で同一の Dart コードベースからビルド。ファイル入出力は `file_picker` でプラットフォーム差分を吸収。

## 2. レイヤ構成

```text
┌─────────────────────────────────────────────────────────┐
│  views / widgets  (UI 層)                                │
│  MainCanvasScreen, ObjectListScreen, TopActionBar,       │
│  NoteObjectWidget, ConnectionPainter, ...                │
├─────────────────────────────────────────────────────────┤
│  providers  (状態・ロジック層)                            │
│  CanvasNotifier, CanvasNameNotifier,                     │
│  BackgroundConfigNotifier, CanvasState                   │
├─────────────────────────────────────────────────────────┤
│  services  (I/O・永続化層)                                │
│  StorageService, CanvasExportService,                    │
│  BackgroundPersistenceService,                           │
│  CanvasPersistenceService,                               │
│  ActionBarPagePersistenceService                         │
├─────────────────────────────────────────────────────────┤
│  models  (データ層)                                       │
│  NoteObject, Connection, GroupFrame, BackgroundConfig    │
└─────────────────────────────────────────────────────────┘
```

### 依存関係

- `views` / `widgets` → `providers` / `services` / `models`
- `providers` → `models` / `services`
- `services` → `models`
- `models` → （外部依存なし、`dart:ui` のみ）

## 3. データ構造

### 3.1 エンティティ

```text
CanvasState
├── objects: List<NoteObject>      # 描画順 = Z 順（末尾が最前面）
├── connections: List<Connection>  # オブジェクト間の接続線
├── groupFrames: List<GroupFrame>  # グループ枠
├── selectedId: String?            # 現在選択中のオブジェクト ID
├── history: List<CanvasState>     # Undo 履歴スタック（最大 30 件）
├── redoStack: List<CanvasState>   # Redo スタック（最大 30 件）
└── maxHistory: int                # 履歴の最大件数（既定 30）
```

### 3.2 NoteObject

```text
NoteObject
├── id: String
├── position: Offset               # キャンバス座標
├── size: Size                     # 基準サイズ（scale 未反映）
├── content: String                # 本文
├── label: String                  # ラベル（見出し）
├── detail: String                 # 説明
├── color: Color                   # 本体色
├── shape: NoteShape               # 形状
├── emphasis: Emphasis             # 強調レベル
├── labelColor: Color?             # ラベル色（null なら color）
├── descriptionColor: Color?       # 説明色（null なら color）
├── scale: double                  # サイズ倍率（0.5〜4.0、既定 1.0）
├── labelFontSizeLevel: int        # ラベル文字サイズレベル（1〜5、既定 3）
├── descriptionFontSizeLevel: int  # 説明文字サイズレベル（1〜5、既定 2）
└── isSelected: bool

# メソッド
├── copyWith(...)                  # 一部フィールドを差し替えた複製
├── rectInCanvas() → Rect          # scale 反映済みのキャンバス矩形
└── toJson() / fromJson(...)       # JSON シリアライズ・デシリアライズ
```

> `rectInCanvas()` は `size × scale` の矩形を返し、接続線・グループ枠・整列・エクスポートのすべてがこれを基準に計算する。

### 3.3 Connection

```text
Connection
├── id: String
├── sourceId: String
├── targetId: String
├── lineType: LineType             # 線種
├── lineShape: LineShape           # 形状
└── color: Color                   # 線の色（既定: 白）
```

### 3.4 GroupFrame

```text
GroupFrame
├── id: String
├── memberIds: List<String>        # 含まれるオブジェクト ID
├── name: String
├── description: String
└── color: Color                   # 枠線の色
```

### 3.5 BackgroundConfig

```text
BackgroundConfig
├── gridType: GridType             # none / lines / dots
├── gridSpacing: double
├── gridColor: Color
├── gridOpacity: double
├── backgroundColor: Color
├── backgroundOpacity: double
├── backgroundImagePath: String?
└── backgroundImageOpacity: double
```

### 3.6 列挙型

| 列挙型 | 値 |
| --- | --- |
| `NoteShape` | roundedRect, rectangle, ellipse, cloud, parallelogram, trapezoid, trapezium, hexagon, pentagonLeft/Right/Up/Down, circle, square |
| `Emphasis` | normal, strong, weak |
| `LineType` | normal, thick, dotted, dashDot |
| `LineShape` | arrow, straight, elbow, curve, doubleArrow, reverseArrow |
| `GridType` | none, lines, dots |
| `AlignMode` | left, right, top, bottom, distributeHorizontal, distributeVertical |

### 3.7 定数・ヘルパー（`models/note_object.dart`）

| 名前 | 値 | 説明 |
| --- | --- | --- |
| `kObjectScales` | `[0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]` | 選択可能なサイズ倍率 |
| `kMinFontSizeLevel` / `kMaxFontSizeLevel` | `1` / `5` | 文字サイズレベルの範囲 |
| `kDefaultLabelFontSizeLevel` | `3` | ラベルの既定レベル（18px） |
| `kDefaultDescriptionFontSizeLevel` | `2` | 説明の既定レベル（15px） |
| `fontSizeForLevel(int)` | `12 + (level-1) * 3` px | レベル→px 変換（12〜24px） |

## 4. 状態管理（Riverpod）

### 4.1 Provider 一覧

| Provider | 型 | 役割 |
| --- | --- | --- |
| `canvasNotifierProvider` | `CanvasNotifier` → `CanvasState` | オブジェクト・接続線・グループ・選択・Undo/Redo の管理 |
| `canvasNameProvider` | `CanvasNameNotifier` → `String` | キャンバス名 |
| `backgroundConfigProvider` | `BackgroundConfigNotifier` → `BackgroundConfig` | 背景ガイド設定 |

### 4.2 CanvasNotifier の主なメソッド

`CanvasNotifier`（`providers/canvas_provider.dart`）は薄いシェルで、実装は 7 つの mixin に分離されている。

| カテゴリ | mixin（ファイル） | メソッド |
| --- | --- | --- |
| オブジェクト（基本） | `CanvasObjectCore`（`canvas_object_core.dart`） | `addObject`, `editObject`, `bringToFront`, `deleteSelected`, `deleteAllObjects`, `duplicateSelected`, `duplicateObject`, `deleteObject`, `updateLastShape` |
| オブジェクト（ドラッグ） | `CanvasObjectDrag`（`canvas_object_drag.dart`） | `updatePosition`, `endDrag`, `setPosition`, `cancelDrag`, `resetDraft`, `resetGroupDrafts`, `clearLocalDrafts` |
| 選択 | `CanvasObjectSelection`（`canvas_object_selection.dart`） | `selectObject`, `toggleSelect`, `selectedCount`, `selectAll`, `clearSelection` |
| 整列 | `CanvasObjectAlign`（`canvas_object_align.dart`） | `alignSelectedToStep`, `alignSelected`（+ `AlignMode` 列挙型） |
| 接続線 | `CanvasConnectionOps`（`canvas_connection_ops.dart`） | `addConnection`, `connectSelected`, `updateConnection`, `deleteConnection` |
| グループ | `CanvasGroupOps`（`canvas_group_ops.dart`） | `createGroup`, `addToGroup`, `updateGroup`, `deleteGroup`, `moveGroup`, `endGroupDrag` |
| Undo/Redo | `CanvasHistoryOps`（`canvas_history_ops.dart`） | `undo`, `redo` |
| 永続化 | `CanvasHistoryOps`（`canvas_history_ops.dart`） | `loadFromJson`, `exportToJson`, `makeNewNote` |

- **ID 生成**: `providers/canvas_id.dart` の `generateId` / `generateConnectionId` / `generateGroupId`。

### 4.3 ドラッグ中の状態管理

- `localDraftPositions`: ドラッグ中の表示用ローカル座標（キー = オブジェクト ID）。
- `dragStartPositions`: ドラッグ開始時の位置（Undo 履歴に正しく積むため）。
- `dragStartCanvas`: ドラッグ開始地点のキャンバス座標。
- `lastAddedId`: 直近に追加したオブジェクト ID。
- `lastShape`: 最後に設定した形状（新規作成時のデフォルト）。

## 5. 描画アーキテクチャ

### 5.1 描画順序（Z 順）

`MainCanvasScreen` の `Stack` 内で以下の順序で描画される（下から上へ）:

1. 背景色（キャンバス座標 0,0 に固定）
2. 背景画像（ビューポート固定）
3. グリッド（ビューポート固定）
4. グループ枠（`GroupFrameWidget`）
5. 接続線（`ConnectionPainter`）
6. オブジェクト（`NoteObjectWidget` + `NoteShapePainter`）

### 5.2 CustomPainter 一覧

| Painter | 役割 |
| --- | --- |
| `NoteShapePainter` | オブジェクト形状の背景描画。選択時は四隅の枠線で強調。 |
| `ConnectionPainter` | 接続線の描画（線種・形状・色）。オブジェクトの境界間を結ぶパスを構築。 |
| `ConnectionPreviewPainter` | 接続モード中のドラッグプレビュー線。 |
| `GroupFramePainter` | グループ枠（矩形枠）の描画。 |
| `BackgroundGridPainter` | 背景グリッド（罫線 / ドット）の描画。 |

### 5.3 カラーピッカー（`MyCustomColorPicker`）

- `lib/views/widgets/my_custom_color_picker.dart` の `MyCustomColorPicker` が、`flex_color_picker` の `ColorPicker` をラップする共通ウィジェット。
- `showAsDialog(context, initialColor:, title:)` でダイアログ表示し、OK で選択色を `Future<Color?>` として返す（キャンセルは `null`）。
- 有効化: カラーホイール・シェード選択・カラーコード表示・コピー＆ペースト・OK/キャンセルボタン。
- 全 5 箇所の `_pickColor`（オブジェクト一覧・背景設定・接続線メニュー・グループ編集・オブジェクト編集）がこれを使用。
- **注意**: `flex_color_picker` 4.0.0 は `material_ui` パッケージ（material ライブラリのフォーク）に依存し、`showPickerDialog` が `material_ui` 版の `MaterialLocalizations` を要求する。そのため `main.dart` の `localizationsDelegates` に `material_ui.GlobalMaterialLocalizations.delegate` を追加している。

## 6. 永続化

| 対象 | 方式 | 保存先 |
| --- | --- | --- |
| キャンバス状態（オブジェクト・接続線・グループ） | `hive_ce`（自動・逐次） | アプリ内部の永続化領域（`memoma3_canvas` box） |
| キャンバス状態（エクスポート用） | JSON ファイル | ユーザー選択のファイル（`file_picker`） |
| キャンバス名 | `hive_ce`（自動） | アプリ内部の永続化領域（`memoma3_canvas` box） |
| 背景ガイド設定 | `shared_preferences` | アプリ内部の永続化領域 |
| アクションバーの表示ページ（左 / 右） | `shared_preferences` | アプリ内部の永続化領域（`memoma3.action_bar_page`） |

### 6.1 自動永続化（`hive_ce`）

- **サービス**: `CanvasPersistenceService`（`services/canvas_persistence_service.dart`）。`hive_ce` の box（`memoma3_canvas`）にキャンバス状態の JSON とキャンバス名を保存する。
- **逐次記録**: `MainCanvasScreen` が `ref.listen(canvasNotifierProvider, ...)` で状態変更を検知し、`scheduleSaveState` を呼ぶ。書き込みは **400ms のデバウンス** でまとめ、高頻度のドラッグ更新でも I/O を抑制する。
- **確実な書き込み**: アプリがバックグラウンドに移る（`AppLifecycleState.paused` / `hidden`）タイミングで `flush()` を呼び、デバウンス待ちのデータを必ずディスクへ反映する。
- **復元**: 起動時（`initState`）に `loadName` / `loadState` を読み、`CanvasNameNotifier.set` と `CanvasNotifier.loadFromJson` で前回の状態を復元する。保存データがない（初回起動）場合は初期状態のまま。
- **初期化**: `main.dart` で `Hive.init` を実行。Web は IndexedDB を使うためパス不要、それ以外（Windows / Android 等）は `path_provider` のアプリケーションサポートディレクトリをホームディレクトリに指定する。

## 7. 座標系

- **キャンバス座標**: 50000×50000 px の絶対座標系。オブジェクトの `position` はこの座標系。
- **ビューポート座標**: 画面（ウィンドウ）座標。
- **変換**: `TransformationController` の行列（`Matrix4`）で「ビューポート → キャンバス」の変換を行う。
- **ズーム補正**: ドラッグの移動量は現在の拡大率で割られるため、ズーム状態に関係なく自然に追従。

## 8. Undo / Redo 機構

- `CanvasState.history`: Undo 履歴スタック（操作**前**の状態を保持）。
- `CanvasState.redoStack`: Redo スタック（Undo で退避した状態を保持）。
- `pushHistory(state)`: 操作前の状態を履歴にプッシュ。同一状態の連続プッシュは省略。新しい操作で Redo スタックはクリア。
- `undo()`: 履歴の末尾の状態を復元し、現在の状態を Redo スタックに積む。
- `redo()`: Redo スタックの末尾の状態を復元し、現在の状態を履歴に戻す。
- ドラッグ操作は `PanEnd` 時にのみ履歴へ保存（ドラッグ中は履歴に積まない）。
