# memoma3 JSON 仕様

本ファイルは、memoma3 が保存・読み込みする JSON ファイルの仕様を定義します。

## 概要

memoma3 の JSON ファイルは、キャンバス上の全オブジェクト（`NoteObject`）、接続線（`Connection`）、グループ枠（`GroupFrame`）の 3 つの配列を含むオブジェクトとして表現されます。

```json
{
  "objects": [
    {
      "id": "1725631200000123",
      "position": { "x": 100.0, "y": 200.0 },
      "size": { "width": 180.0, "height": 120.0 },
      "content": "メモ",
      "label": "ラベル",
      "detail": "説明テキスト",
      "color": 4283833716,
      "shape": 1,
      "emphasis": 0,
      "labelColor": 4278190080,
      "descriptionColor": 4278233720,
      "isSelected": false
    }
  ],
  "connections": [
    {
      "id": "conn-1725631200000123-1725631200000456",
      "sourceId": "1725631200000123",
      "targetId": "1725631200000456",
      "lineType": 0,
      "lineShape": 1,
      "color": 4294967295
    }
  ],
  "groups": [
    {
      "id": "group-1725631200000789",
      "memberIds": ["1725631200000123", "1725631200000456"],
      "name": "グループ名",
      "description": "グループの説明",
      "color": 1694498217
    }
  ]
}
```

## 全体構造

- **ルート**: `{ "objects": [...], "connections": [...], "groups": [...] }` の 3 つの配列を持つオブジェクト
- 各配列はそれぞれ 1 つのエンティティのリストに対応
- JSON は `JsonEncoder.withIndent('  ')` により 2 インデントでフォーマットされる

## 後方互換性

- 旧形式（ルートがオブジェクトの配列 `[...]` のみ）のファイルも読み込み可能です。この場合、`connections` と `groups` は空として扱われます。
- オブジェクトの `emphasis`、接続線の `color`、グループの `name` / `description` / `color` は、旧データにキーがない場合、既定値でフォールバックします。

## NoteObject フィールド一覧

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | String | はい | オブジェクトを一意に特定する ID。`microsecondsSinceEpoch` とカウンタの組み合わせ。 |
| `position` | Object | はい | オブジェクトのキャンバス上の位置。`x`, `y` を持つ。 |
| `position.x` | Number (double) | はい | X 座標（px）。 |
| `position.y` | Number (double) | はい | Y 座標（px）。 |
| `size` | Object | はい | オブジェクトのサイズ。`width`, `height` を持つ。 |
| `size.width` | Number (double) | はい | 幅（px）。 |
| `size.height` | Number (double) | はい | 高さ（px）。 |
| `content` | String | はい | オブジェクトの本文テキスト。 |
| `label` | String | はい | オブジェクトのラベル（見出し）テキスト。 |
| `detail` | String | はい | オブジェクトの説明テキスト。 |
| `color` | Integer | はい | オブジェクトの背景色。`0xAARRGGBB` 形式の整数。 |
| `shape` | Integer | はい | 形状のインデックス（`NoteShape` 列挙型の `index`）。 |
| `emphasis` | Integer | いいえ | 強調レベルのインデックス（`Emphasis` 列挙型の `index`）。未指定の場合は `0`（標準）。 |
| `labelColor` | Integer | いいえ | ラベル（見出し）テキストの色。`0xAARRGGBB` 形式。未指定の場合は `color` を使用。 |
| `descriptionColor` | Integer | いいえ | 説明テキストの色。`0xAARRGGBB` 形式。未指定の場合は `color` を使用。 |
| `isSelected` | Boolean | はい | 選択中かどうか。 |

## shape の値（NoteShape 列挙型）

`shape` フィールドには、`NoteShape` 列挙型のインデックス（整数）が保存されます。

| インデックス | 形状 | 人間向けラベル |
| --- | --- | --- |
| 0 | `roundedRect` | 角丸四角 |
| 1 | `rectangle` | 四角 |
| 2 | `ellipse` | 楕円 |
| 3 | `cloud` | 雲 |
| 4 | `parallelogram` | 平行四角形 |
| 5 | `trapezoid` | 台形（左右対称） |
| 6 | `trapezium` | 台形（非対称） |
| 7 | `hexagon` | 六角形 |
| 8 | `pentagonLeft` | 五角形（左） |
| 9 | `pentagonRight` | 五角形（右） |
| 10 | `pentagonUp` | 五角形（上） |
| 11 | `pentagonDown` | 五角形（下） |
| 12 | `circle` | 円 |
| 13 | `square` | 正方形 |

> 注: 新規選択から除外されている形状（`cloud` / `trapezium`）は、既存データの後方互換のため enum に残っています。新規オブジェクトの形状選択には `kDisplayShapes`（cloud / trapezium を除く）が使用されます。

## emphasis の値（Emphasis 列挙型）

`emphasis` フィールドには、`Emphasis` 列挙型のインデックス（整数）が保存されます。

| インデックス | 強調 | 人間向けラベル |
| --- | --- | --- |
| 0 | `normal` | 標準 |
| 1 | `strong` | 強調 |
| 2 | `weak` | 弱め |

## color / labelColor / descriptionColor の形式

`color`, `labelColor`, `descriptionColor` は、`0xAARRGGBB` 形式の 32bit 整数として保存されます。

- `AA`: アルファチャンネル（不透明度）
- `RR`: 赤
- `GG`: 緑
- `BB`: 青

例:
- 不透明な白: `0xFFFFFFFF` → `4294967295`
- 不透明な黒: `0xFF000000` → `4278190080`
- 不透明な赤: `0xFFFF0000` → `4278190335`

## 補足

- `labelColor` と `descriptionColor` は省略可能です。省略された場合は、それぞれ `color` の値が使用されます。
- `emphasis` は省略可能です。省略された場合は `0`（標準）が使用されます。
- 既存のファイルとの後方互換性のため、`labelColor` と `descriptionColor` は値が `null` の場合は JSON に出力されません。

## Connection フィールド一覧（接続線）

2 つのオブジェクトを接続する線です。

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | String | はい | 接続線を一意に特定する ID。`conn-` プレフィックス付き。 |
| `sourceId` | String | はい | 接続元のオブジェクト ID。 |
| `targetId` | String | はい | 接続先オブジェクト ID。 |
| `lineType` | Integer | はい | 線種（`LineType` 列挙型の `index`）。 |
| `lineShape` | Integer | はい | 形状（`LineShape` 列挙型の `index`）。 |
| `color` | Integer | いいえ | 接続線の色。`0xAARRGGBB` 形式。未指定の場合は白（`0xFFFFFFFF`）。 |

## lineType の値（LineType 列挙型）

| インデックス | 線種 | 人間向けラベル |
| --- | --- | --- |
| 0 | `normal` | 通常の線 |
| 1 | `thick` | 太線 |
| 2 | `dotted` | 点線 |
| 3 | `dashDot` | 一点鎖線 |

## lineShape の値（LineShape 列挙型）

| インデックス | 形状 | 人間向けラベル |
| --- | --- | --- |
| 0 | `arrow` | 矢印 |
| 1 | `straight` | 直線 |
| 2 | `elbow` | カギ線 |
| 3 | `curve` | 曲線（三次ベジェ曲線） |
| 4 | `doubleArrow` | 両方向矢印 |
| 5 | `reverseArrow` | 逆矢印 |

## GroupFrame フィールド一覧（グループ枠）

複数のオブジェクトを囲むグループ枠です。

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `id` | String | はい | グループ枠を一意に特定する ID。`group-` プレフィックス付き。 |
| `memberIds` | Array of String | はい | グループに含めるオブジェクトの ID 一覧。 |
| `name` | String | いいえ | グループ名称。未指定の場合は空文字列。 |
| `description` | String | いいえ | グループの説明。未指定の場合は空文字列。 |
| `color` | Integer | いいえ | 枠線の色。`0xAARRGGBB` 形式。未指定の場合は既定色（`0x664A90D9`）。 |
