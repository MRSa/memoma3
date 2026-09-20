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
│  BackgroundPersistenceService                            │
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
├── size: Size
├── content: String                # 本文
├── label: String                  # ラベル（見出し）
├── detail: String                 # 説明
├── color: Color                   # 本体色
├── shape: NoteShape               # 形状
├── emphasis: Emphasis             # 強調レベル
├── labelColor: Color?             # ラベル色（null なら color）
├── descriptionColor: Color?       # 説明色（null なら color）
└── isSelected: bool
```

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

## 4. 状態管理（Riverpod）

### 4.1 Provider 一覧

| Provider | 型 | 役割 |
| --- | --- | --- |
| `canvasNotifierProvider` | `CanvasNotifier` → `CanvasState` | オブジェクト・接続線・グループ・選択・Undo/Redo の管理 |
| `canvasNameProvider` | `CanvasNameNotifier` → `String` | キャンバス名 |
| `backgroundConfigProvider` | `BackgroundConfigNotifier` → `BackgroundConfig` | 背景ガイド設定 |

### 4.2 CanvasNotifier の主なメソッド

| カテゴリ | メソッド |
| --- | --- |
| オブジェクト | `addObject`, `updatePosition`, `endDrag`, `setPosition`, `bringToFront`, `editObject`, `deleteObject`, `deleteSelected`, `deleteAllObjects`, `makeNewNote` |
| 選択 | `selectObject`, `toggleSelect`, `selectAll`, `clearSelection`, `_setAllSelected` |
| 整列 | `alignSelectedToStep`, `alignSelected` |
| 接続線 | `addConnection`, `connectSelected`, `updateConnection`, `deleteConnection` |
| グループ | `createGroup`, `addToGroup`, `updateGroup`, `deleteGroup`, `moveGroup`, `endGroupDrag`, `resetGroupDrafts` |
| Undo/Redo | `undo`, `redo` |
| 永続化 | `loadFromJson`, `exportToJson` |

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

## 6. 永続化

| 対象 | 方式 | 保存先 |
| --- | --- | --- |
| キャンバス状態（オブジェクト・接続線・グループ） | JSON ファイル | ユーザー選択のファイル（`file_picker`） |
| 背景ガイド設定 | `shared_preferences` | アプリ内部の永続化領域 |
| キャンバス名 | `shared_preferences`（予定） | アプリ内部の永続化領域 |

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
