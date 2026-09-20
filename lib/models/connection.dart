import 'dart:ui';

/// 接続線の描画形状（矢印・直線・カギ・曲線）を表す列挙型。
/// 将来の形状追加に対応するため、JSON にはインデックス（int）で保存する。
enum LineShape {
  arrow,
  straight,
  elbow,
  curve,
  doubleArrow,
  reverseArrow,
}

extension LineShapeName on LineShape {
  /// 形状の人間向けラベルを返す。
  String get displayName {
    switch (this) {
      case LineShape.arrow:
        return '矢印';
      case LineShape.straight:
        return '直線';
      case LineShape.elbow:
        return 'カギ線';
      case LineShape.curve:
        return '曲線';
      case LineShape.doubleArrow:
        return '両方向矢印';
      case LineShape.reverseArrow:
        return '逆矢印';
    }
  }
}

/// 接続線の描画スタイル（線種）を表す列挙型。
/// 将来の線種追加に対応するため、JSON にはインデックス（int）で保存する。
enum LineType {
  normal,
  thick,
  dotted,
  dashDot,
}

extension LineTypeName on LineType {
  /// 線種の人間向けラベルを返す。
  String get displayName {
    switch (this) {
      case LineType.normal:
        return '通常の線';
      case LineType.thick:
        return '太線';
      case LineType.dotted:
        return '点線';
      case LineType.dashDot:
        return '一点鎖線';
    }
  }
}

/// 2つのオブジェクトを接続する線のデータモデル。
/// 不変（immutable）に設計し、copyWith で複製を作成する。
class Connection {
  final String id;
  final String sourceId;
  final String targetId;
  final LineType lineType;
  final LineShape lineShape;

  /// 接続線の色。デフォルトは白。
  final Color color;

  const Connection({
    required this.id,
    required this.sourceId,
    required this.targetId,
    this.lineType = LineType.normal,
    this.lineShape = LineShape.straight,
    this.color = const Color(0xFFFFFFFF),
  });

  Connection copyWith({
    String? id,
    String? sourceId,
    String? targetId,
    LineType? lineType,
    LineShape? lineShape,
    Color? color,
  }) {
    return Connection(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      targetId: targetId ?? this.targetId,
      lineType: lineType ?? this.lineType,
      lineShape: lineShape ?? this.lineShape,
      color: color ?? this.color,
    );
  }

  /// Connection を JSON 直前の Map 形式に変換する。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceId': sourceId,
      'targetId': targetId,
      'lineType': lineType.index,
      'lineShape': lineShape.index,
      'color': color.toARGB32(),
    };
  }

  /// Map 形式（JSON 直後）から Connection を再生成する。
  /// 旧データ（color キーなし）には後方互換性を持つ（既定は白）。
  factory Connection.fromJson(Map<String, dynamic> json) {
    return Connection(
      id: json['id'] as String,
      sourceId: json['sourceId'] as String,
      targetId: json['targetId'] as String,
      lineType: LineType.values[json['lineType'] as int],
      lineShape: LineShape.values[json['lineShape'] as int],
      color: json['color'] != null
          ? Color(json['color'] as int)
          : const Color(0xFFFFFFFF),
    );
  }
}

/// グループ枠（複数オブジェクトを囲む矩形枠）のデータモデル。
/// 不変（immutable）に設計し、copyWith で複製を作成する。
class GroupFrame {
  final String id;
  /// グループに含めるオブジェクトの ID 一覧。
  final List<String> memberIds;

  /// グループ名称。
  final String name;

  /// グループの説明（description）。
  final String description;

  /// 枠線の色。
  final Color color;

  const GroupFrame({
    required this.id,
    required this.memberIds,
    this.name = '',
    this.description = '',
    this.color = const Color(0x664A90D9),
  });

  GroupFrame copyWith({
    String? id,
    List<String>? memberIds,
    String? name,
    String? description,
    Color? color,
  }) {
    return GroupFrame(
      id: id ?? this.id,
      memberIds: memberIds ?? this.memberIds,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
    );
  }

  /// GroupFrame を JSON 直前の Map 形式に変換する。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'memberIds': memberIds,
      'name': name,
      'description': description,
      'color': color.toARGB32(),
    };
  }

  /// Map 形式（JSON 直後）から GroupFrame を再生成する。
  /// 旧形式（name / description / color が無い）にも後方互換性を持つ。
  factory GroupFrame.fromJson(Map<String, dynamic> json) {
    final members = (json['memberIds'] as List).map((e) => e as String).toList();
    return GroupFrame(
      id: json['id'] as String,
      memberIds: members,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      color: json['color'] != null ? Color(json['color'] as int) : const Color(0x664A90D9),
    );
  }
}
