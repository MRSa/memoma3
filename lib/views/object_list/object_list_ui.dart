import '../../models/note_object.dart';

/// 一覧テーブルのソート対象カラム。
enum SortColumn {
  number,
  name,
  shape,
  color,
  emphasis,
  group,
  connection,
  x,
  y,
  scale,
}

/// 一覧テーブルのソート方向。
enum SortDirection {
  ascending,
  descending,
}

/// 固定カラム（No. / 名称）の幅。
const double kNoWidth = 56.0;
const double kNameWidth = 180.0;

/// ヘッダ行の高さ。
const double kHeaderHeight = 56.0;

/// データ行の高さ（説明・詳細の複数行表示に合わせる）。
const double kRowHeight = 90.0;

/// セル間の左右パディング。
const double kCellGap = 12.0;

/// 右パネル各カラムの固定幅（ヘッダとデータセルで揃える）。
const double kDetailWidth = 220.0;
const double kContentWidth = 220.0;
const double kShapeWidth = 90.0;
const double kColorWidth = 110.0;
const double kEmphasisWidth = 90.0;
const double kGroupWidth = 160.0;
const double kConnectionWidth = 220.0;
const double kXWidth = 80.0;
const double kYWidth = 80.0;
const double kScaleWidth = 70.0;
const double kCenterWidth = 56.0;
const double kDuplicateWidth = 56.0;
const double kDeleteWidth = 56.0;

/// 1 行分の表示データをまとめる。
class RowData {
  final NoteObject object;
  final int number;
  final List<String> groupsFor;
  final List<String> from;
  final List<String> to;

  const RowData({
    required this.object,
    required this.number,
    required this.groupsFor,
    required this.from,
    required this.to,
  });
}
