import 'dart:ui';

/// キャンバス背景に描画するグリッドの種類。
///
/// JSON にはインデックス（int）で保存する。既存のインデックスは
/// 後方互換のため変更しない。
enum GridType {
  /// グリッドを描画しない。
  none,

  /// 罫線（縦横の線）で示すグリッド。
  lines,

  /// ドット（点）で示すグリッド。
  dots,
}

extension GridTypeName on GridType {
  /// グリッド種類の人間向けラベルを返す。
  String get displayName {
    switch (this) {
      case GridType.none:
        return 'なし';
      case GridType.lines:
        return '罫線';
      case GridType.dots:
        return 'ドット';
    }
  }
}

/// メインキャンバスの背景ガイド設定。
///
/// オブジェクトの配置をアシストするため、背景に「罫線 / ドットのグリッド」、
/// 「背景色」、または「ローカル画像」を表示できる。各要素は独立して
/// 有効/無効化でき、透明度を個別に調整できる。
///
/// 不変（immutable）に設計し、[copyWith] で複製を作成する。
/// [toJson] / [fromJson] で JSON 直列化し、アプリ再起動後も設定を
/// 維持できるようにする。
class BackgroundConfig {
  /// 描画するグリッドの種類。
  final GridType gridType;

  /// グリッドの間隔（キャンバス座標 px）。
  final double gridSpacing;

  /// グリッド（罫線・ドット）の色。
  final Color gridColor;

  /// グリッドの透明度（0.0〜1.0）。
  final double gridOpacity;

  /// 背景色。
  final Color backgroundColor;

  /// 背景色の透明度（0.0〜1.0）。
  final double backgroundOpacity;

  /// 背景画像のローカルパス。未設定なら null。
  final String? backgroundImagePath;

  /// 背景画像の透明度（0.0〜1.0）。
  final double backgroundImageOpacity;

  const BackgroundConfig({
    this.gridType = GridType.none,
    this.gridSpacing = 20.0,
    this.gridColor = const Color(0xFFB0BEC5),
    this.gridOpacity = 0.5,
    this.backgroundColor = const Color(0xFF000000),
    this.backgroundOpacity = 0.0,
    this.backgroundImagePath,
    this.backgroundImageOpacity = 0.5,
  });

  /// 初期値（リセット時の既定値）。
  ///
  /// 背景色は「無効」（透明度 0）、グリッドは「なし」、画像は未設定。
  static const BackgroundConfig initial = BackgroundConfig();

  /// 背景色を有効にしているか（透明度が 0 より大きい）。
  bool get hasBackground => backgroundOpacity > 0.0;

  /// 背景画像を有効にしているか。
  bool get hasImage => backgroundImagePath != null && backgroundImageOpacity > 0.0;

  /// グリッドを有効にしているか。
  bool get hasGrid => gridType != GridType.none && gridOpacity > 0.0;

  /// 何らかの背景ガイドが有効か。
  bool get hasAnyGuide => hasBackground || hasImage || hasGrid;

  BackgroundConfig copyWith({
    GridType? gridType,
    double? gridSpacing,
    Color? gridColor,
    double? gridOpacity,
    Color? backgroundColor,
    double? backgroundOpacity,
    String? backgroundImagePath,
    bool clearImage = false,
    double? backgroundImageOpacity,
  }) {
    return BackgroundConfig(
      gridType: gridType ?? this.gridType,
      gridSpacing: gridSpacing ?? this.gridSpacing,
      gridColor: gridColor ?? this.gridColor,
      gridOpacity: gridOpacity ?? this.gridOpacity,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      backgroundImagePath: clearImage
          ? null
          : (backgroundImagePath ?? this.backgroundImagePath),
      backgroundImageOpacity:
          backgroundImageOpacity ?? this.backgroundImageOpacity,
    );
  }

  /// JSON 直前の変換。
  Map<String, dynamic> toJson() {
    return {
      'gridType': gridType.index,
      'gridSpacing': gridSpacing,
      'gridColor': gridColor.toARGB32(),
      'gridOpacity': gridOpacity,
      'backgroundColor': backgroundColor.toARGB32(),
      'backgroundOpacity': backgroundOpacity,
      if (backgroundImagePath != null) 'backgroundImagePath': backgroundImagePath,
      'backgroundImageOpacity': backgroundImageOpacity,
    };
  }

  /// JSON 直後から再生成する。欠損キーは初期値で補完する。
  factory BackgroundConfig.fromJson(Map<String, dynamic> json) {
    return BackgroundConfig(
      gridType: GridType.values[json['gridType'] as int? ?? GridType.none.index],
      gridSpacing: (json['gridSpacing'] as num? ?? 20.0).toDouble(),
      gridColor: Color(json['gridColor'] as int? ?? const Color(0xFFB0BEC5).toARGB32()),
      gridOpacity: (json['gridOpacity'] as num? ?? 0.5).toDouble(),
      backgroundColor: Color(json['backgroundColor'] as int? ?? const Color(0xFF000000).toARGB32()),
      backgroundOpacity: (json['backgroundOpacity'] as num? ?? 0.0).toDouble(),
      backgroundImagePath: json['backgroundImagePath'] as String?,
      backgroundImageOpacity: (json['backgroundImageOpacity'] as num? ?? 0.5).toDouble(),
    );
  }
}
