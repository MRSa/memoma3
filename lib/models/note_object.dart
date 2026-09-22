import 'dart:ui';

/// NoteObject が描画される形状を表す列挙型。
/// 将来の形状追加に対応するため、JSON にはインデックス（int）で保存する。
///
/// 既存のインデックスは後方互換のため変更しない。
/// 新しい形状は末尾に追加する。
enum NoteShape {
  roundedRect,
  rectangle,
  ellipse,
  cloud,
  parallelogram,
  trapezoid,
  trapezium,
  hexagon,
  // 五角形（とがった方向を指定）。
  pentagonLeft,
  pentagonRight,
  pentagonUp,
  pentagonDown,
  // 円・正方形。
  circle,
  square,
}

/// ダイアログで表示する形状の一覧。
///
/// 「雲」は「円」「正方形」に、「台形（非対称）」は「五角形」に置き換えるため、
/// 置き換え対象（cloud / trapezium）は新規選択から除外する。
/// 既存データの後方互換のため enum 自体は残す。
const List<NoteShape> kDisplayShapes = [
  NoteShape.roundedRect,
  NoteShape.rectangle,
  NoteShape.ellipse,
  NoteShape.circle,
  NoteShape.square,
  NoteShape.parallelogram,
  NoteShape.trapezoid,
  NoteShape.hexagon,
  NoteShape.pentagonLeft,
  NoteShape.pentagonRight,
  NoteShape.pentagonUp,
  NoteShape.pentagonDown,
];

extension NoteShapeName on NoteShape {
  /// 形状の人間向けラベルを返す。
  String get displayName {
    switch (this) {
      case NoteShape.roundedRect:
        return '角丸四角';
      case NoteShape.rectangle:
        return '四角';
      case NoteShape.ellipse:
        return '楕円';
      case NoteShape.cloud:
        return '雲';
      case NoteShape.parallelogram:
        return '平行四角形';
      case NoteShape.trapezoid:
        return '台形（左右対称）';
      case NoteShape.trapezium:
        return '台形（非対称）';
      case NoteShape.hexagon:
        return '六角形';
      case NoteShape.pentagonLeft:
        return '五角形（左）';
      case NoteShape.pentagonRight:
        return '五角形（右）';
      case NoteShape.pentagonUp:
        return '五角形（上）';
      case NoteShape.pentagonDown:
        return '五角形（下）';
      case NoteShape.circle:
        return '円';
      case NoteShape.square:
        return '正方形';
    }
  }
}

/// オブジェクトの強調レベルを表す列挙型。
///
/// JSON にはインデックス（int）で保存する。
enum Emphasis {
  /// 標準。
  normal,

  /// 強調して目立たせる。
  strong,

  /// 弱めて目立たせない。
  weak,
}

extension EmphasisName on Emphasis {
  /// 強調レベルの人間向けラベルを返す。
  String get displayName {
    switch (this) {
      case Emphasis.normal:
        return '標準';
      case Emphasis.strong:
        return '強調';
      case Emphasis.weak:
        return '弱め';
    }
  }
}

/// オブジェクトのサイズ倍率。0.5 倍から 4 倍まで 0.5 刻み。
///
/// 既定は 1.0（変更なし）。描画・接続線・グループ・整列・エクスポートの
/// すべてに [rectInCanvas] 経由で反映される。
const List<double> kObjectScales = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0];

/// ラベル・説明の文字サイズレベル（1〜5）。
///
/// レベル 1 が最小、5 が最大。
const int kMinFontSizeLevel = 1;
const int kMaxFontSizeLevel = 5;
/// ラベルの既定の文字サイズレベル（標準）。
const int kDefaultLabelFontSizeLevel = 3;
/// 説明の既定の文字サイズレベル。
const int kDefaultDescriptionFontSizeLevel = 2;

/// 文字サイズレベル（1〜5）をフォントサイズ（px）に変換する。
double fontSizeForLevel(int level) {
  final clamped = level.clamp(kMinFontSizeLevel, kMaxFontSizeLevel);
  // レベル 1〜5 を 12px〜24px に線形マッピングする。
  return 12.0 + (clamped - kMinFontSizeLevel) * 3.0;
}

/// キャンバス上に配置されるオブジェクトのデータモデル。
/// 不変（immutable）に設計し、copyWith で複製を作成する。
class NoteObject {
  final String id;
  final Offset position;
  final Size size;
  final String content;
  final String label;
  final String detail;
  final Color color;
  final NoteShape shape;
  /// 強調レベル。標準は [Emphasis.normal]。
  final Emphasis emphasis;
  /// ラベル（見出し）テキストの色。未指定の場合は [color] を使用する。
  final Color? labelColor;
  /// 説明テキストの色。未指定の場合は [color] を使用する。
  final Color? descriptionColor;
  /// サイズ倍率（0.5〜4.0、0.5 刻み）。既定は 1.0。
  final double scale;
  /// ラベルの文字サイズレベル（1〜5）。既定は 3。
  final int labelFontSizeLevel;
  /// 説明の文字サイズレベル（1〜5）。既定は 3。
  final int descriptionFontSizeLevel;
  final bool isSelected;

  const NoteObject({
    required this.id,
    required this.position,
    required this.size,
    required this.content,
    required this.label,
    required this.detail,
    required this.color,
    required this.shape,
    this.emphasis = Emphasis.normal,
    this.labelColor,
    this.descriptionColor,
    this.scale = 1.0,
    this.labelFontSizeLevel = kDefaultLabelFontSizeLevel,
    this.descriptionFontSizeLevel = kDefaultDescriptionFontSizeLevel,
    this.isSelected = false,
  });

  /// デフォルト値を持つ新しいオブジェクトを生成する。
  NoteObject copyWith({
    String? id,
    Offset? position,
    Size? size,
    String? content,
    String? label,
    String? detail,
    Color? color,
    NoteShape? shape,
    Emphasis? emphasis,
    Color? labelColor,
    Color? descriptionColor,
    double? scale,
    int? labelFontSizeLevel,
    int? descriptionFontSizeLevel,
    bool? isSelected,
  }) {
    return NoteObject(
      id: id ?? this.id,
      position: position ?? this.position,
      size: size ?? this.size,
      content: content ?? this.content,
      label: label ?? this.label,
      detail: detail ?? this.detail,
      color: color ?? this.color,
      shape: shape ?? this.shape,
      emphasis: emphasis ?? this.emphasis,
      labelColor: labelColor ?? this.labelColor,
      descriptionColor: descriptionColor ?? this.descriptionColor,
      scale: scale ?? this.scale,
      labelFontSizeLevel: labelFontSizeLevel ?? this.labelFontSizeLevel,
      descriptionFontSizeLevel: descriptionFontSizeLevel ?? this.descriptionFontSizeLevel,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  /// このオブジェクトのキャンバス座標での矩形を返す（サイズ倍率を反映）。
  ///
  /// 接続線・グループ枠・整列・エクスポートのすべてが、このスケール済み
  /// 矩形を基準に計算するため、サイズ変更と整合する。
  Rect rectInCanvas() {
    return Rect.fromLTWH(
      position.dx,
      position.dy,
      size.width * scale,
      size.height * scale,
    );
  }

  /// Offset を JSON 化可能な形 ({x, y}) に変換する。
  Map<String, double> _offsetToJson(Offset offset) {
    return {'x': offset.dx, 'y': offset.dy};
  }

  /// Size を JSON 化可能な形 ({width, height}) に変換する。
  Map<String, double> _sizeToJson(Size size) {
    return {'width': size.width, 'height': size.height};
  }

  /// Color を 0xAARRGGBB 形式の int に変換する。
  int _colorToJson(Color color) {
    return color.toARGB32();
  }

  /// このオブジェクトを Map 形式（JSON 直前）に変換する。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'position': _offsetToJson(position),
      'size': _sizeToJson(size),
      'content': content,
      'label': label,
      'detail': detail,
      'color': _colorToJson(color),
      'shape': shape.index,
      'emphasis': emphasis.index,
      if (labelColor != null) 'labelColor': labelColor!.toARGB32(),
      if (descriptionColor != null) 'descriptionColor': descriptionColor!.toARGB32(),
      'scale': scale,
      'labelFontSizeLevel': labelFontSizeLevel,
      'descriptionFontSizeLevel': descriptionFontSizeLevel,
      'isSelected': isSelected,
    };
  }

  /// Map 形式（JSON 直後）から NoteObject を再生成する。
  factory NoteObject.fromJson(Map<String, dynamic> json) {
    final positionJson = json['position'] as Map<String, dynamic>;
    final sizeJson = json['size'] as Map<String, dynamic>;
    final shapeIndex = json['shape'] as int;

    return NoteObject(
      id: json['id'] as String,
      position: Offset(
        (positionJson['x'] as num).toDouble(),
        (positionJson['y'] as num).toDouble(),
      ),
      size: Size(
        (sizeJson['width'] as num).toDouble(),
        (sizeJson['height'] as num).toDouble(),
      ),
      content: json['content'] as String,
      label: json['label'] as String,
      detail: json['detail'] as String,
      color: Color(json['color'] as int),
      shape: NoteShape.values[shapeIndex],
      emphasis: json['emphasis'] != null
          ? Emphasis.values[json['emphasis'] as int]
          : Emphasis.normal,
      labelColor: json['labelColor'] != null
          ? Color(json['labelColor'] as int)
          : null,
      descriptionColor: json['descriptionColor'] != null
          ? Color(json['descriptionColor'] as int)
          : null,
      // 旧形式（これらのキーがない）は既定値で後方互換。
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      labelFontSizeLevel: (json['labelFontSizeLevel'] as num?)?.toInt() ??
          kDefaultLabelFontSizeLevel,
      descriptionFontSizeLevel:
          (json['descriptionFontSizeLevel'] as num?)?.toInt() ??
              kDefaultDescriptionFontSizeLevel,
      isSelected: json['isSelected'] as bool? ?? false,
    );
  }
}