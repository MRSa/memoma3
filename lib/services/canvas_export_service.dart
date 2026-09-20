import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

import '../models/background_config.dart';
import '../models/connection.dart';
import '../models/note_object.dart';
import '../providers/canvas_state.dart';
import '../views/widgets/connection_painter.dart';
import '../views/widgets/group_frame_painter.dart';
import '../views/widgets/note_shape_painter.dart';

/// キャンバスの状態（オブジェクト・接続線・グループ枠）を画像として書き出すサービス。
///
/// - 既存のペインター（[NoteShapePainter] / [ConnectionPainter] / [GroupFramePainter]）を
///   再利用して、オブジェクトの位置関係・色・形状・接続線を保ったまま描画する。
/// - ヘッダー部分にアプリのアイコンとキャンバス名称を表示する。
/// - 出力サイズは全オブジェクトの外接矩形に上下左右 25px のマージンを持たせた
///   必要最小限の大きさにする。
class CanvasExportService {
  /// 上下左右のマージン（px）。
  static const double _margin = 25.0;

  /// ヘッダーのアイコンサイズ（px）。
  static const double _iconSize = 48.0;

  /// ヘッダーの上下パディング（px）。
  static const double _headerPadding = 16.0;

  /// ヘッダーの最小幅（px）。内容が狭い場合でもヘッダーが崩れないよう確保する。
  static const double _minWidth = 240.0;

  /// オブジェクト・グループ枠の外接矩形（キャンバス座標）を計算する。
  /// オブジェクトが 1 つもなければ [Rect.zero] を返す。
  Rect _computeContentBounds(CanvasState state) {
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;

    void absorb(Rect r) {
      left = math.min(left, r.left);
      top = math.min(top, r.top);
      right = math.max(right, r.right);
      bottom = math.max(bottom, r.bottom);
    }

    for (final o in state.objects) {
      absorb(o.rectInCanvas());
    }
    for (final g in state.groupFrames) {
      final rect = _groupRect(g, state.objects);
      if (rect != Rect.zero) absorb(rect);
    }

    if (left == double.infinity) return Rect.zero;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// グループ枠の矩形を計算する（メンバーの外接矩形 + マージン）。
  /// [GroupFrameWidget] と同じ計算を行う。
  Rect _groupRect(GroupFrame g, List<NoteObject> objects) {
    final members = objects.where((o) => g.memberIds.contains(o.id));
    if (members.isEmpty) return Rect.zero;

    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;

    for (final m in members) {
      final r = m.rectInCanvas();
      left = math.min(left, r.left);
      top = math.min(top, r.top);
      right = math.max(right, r.right);
      bottom = math.max(bottom, r.bottom);
    }

    const margin = 24.0;
    return Rect.fromLTRB(
      left - margin,
      top - margin,
      right + margin,
      bottom + margin,
    );
  }

  /// キャンバス内容（ヘッダー除く、マージン込み）を [ui.Image] にレンダリングする。
  Future<ui.Image> _renderContent(
    CanvasState state,
    Rect bounds,
    BackgroundConfig background,
  ) async {
    // 出力サイズは整数ピクセルに丸める。背景の塗りつぶしと toImage のサイズを
    // 一致させることで、端（特に下側）に透明ピクセル（＝白く見える線）が
    // 残らないようにする。
    // 描画（Rect / Size）には double を使い、背景塗りつぶしと toImage のときだけ
    // 切り上げ整数（imgW / imgH）に揃える。
    final double width = bounds.width + _margin * 2;
    final double height = bounds.height + _margin * 2;
    final int imgW = width.ceil();
    final int imgH = height.ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 背景（黒）。背景色が設定されていない場合でも、接続線が見えるよう
    // 黒をベースにする。塗りつぶしは画像サイズ（imgW / imgH）に揃える。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
      Paint()..color = Colors.black,
    );

    // 背景（色 / 画像）はマージン領域も含めた出力全体に描画する。
    // 出力座標系（変換前）で、フルサイズ矩形に対して描画する。
    await _renderBackground(
      canvas,
      Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
      background,
    );

    // 内容座標系へ変換（マージン分だけ内側を原点に）。
    canvas.save();
    canvas.translate(_margin - bounds.left, _margin - bounds.top);

    final objectMap = <String, NoteObject>{};
    for (final o in state.objects) {
      objectMap[o.id] = o;
    }

    // 1. グループ枠（キャンバス座標で描画）
    for (final g in state.groupFrames) {
      final rect = _groupRect(g, state.objects);
      if (rect == Rect.zero) continue;
      final painter = GroupFramePainter(
        rect: rect,
        title: g.name,
        color: g.color,
      );
      painter.paint(canvas, Size(width, height));
    }

    // 2. 接続線（キャンバス座標で描画）
    for (final c in state.connections) {
      final source = objectMap[c.sourceId];
      final target = objectMap[c.targetId];
      if (source == null || target == null) continue;
      final painter = ConnectionPainter(
        connection: c,
        sourceRect: source.rectInCanvas(),
        targetRect: target.rectInCanvas(),
        color: c.color,
      );
      painter.paint(canvas, Size(width, height));
    }

    // 3. オブジェクト（形状 + テキスト）
    for (final o in state.objects) {
      canvas.save();
      canvas.translate(o.position.dx, o.position.dy);
      final shapePainter = NoteShapePainter(
        shape: o.shape,
        color: o.color,
        emphasis: o.emphasis,
      );
      shapePainter.paint(canvas, o.size);
      _drawObjectText(canvas, o);
      canvas.restore();
    }

    canvas.restore();

    final picture = recorder.endRecording();
    return picture.toImage(imgW, imgH);
  }

  /// 背景（色 / 画像）を [bounds]（キャンバス座標）に描画する。
  ///
  /// メインキャンバス（[MainCanvasScreen]）と同じ順序・スタイルで描画する：
  /// 背景色 → 背景画像。グリッドはエクスポート時に出力しない。
  Future<void> _renderBackground(
    Canvas canvas,
    Rect bounds,
    BackgroundConfig background,
  ) async {
    // 1. 背景色
    if (background.hasBackground) {
      canvas.drawRect(
        bounds,
        Paint()
          ..color = background.backgroundColor
              .withValues(alpha: background.backgroundOpacity),
      );
    }

    // 2. 背景画像（BoxFit.cover 相当で [bounds] に配置）
    if (background.hasImage) {
      final image = await _loadImageFile(background.backgroundImagePath);
      if (image != null) {
        final dst = _coverRect(bounds, image.width.toDouble(), image.height.toDouble());
        canvas.save();
        canvas.clipRect(bounds);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          dst,
          Paint()
            ..filterQuality = ui.FilterQuality.high
            ..color = Color.fromARGB(
              (background.backgroundImageOpacity * 255).round(),
              255,
              255,
              255,
            ),
        );
        canvas.restore();
      }
    }
  }

  /// [BoxFit.cover] 相当の矩形を計算する（[bounds] を覆う最小の矩形）。
  Rect _coverRect(Rect bounds, double imgW, double imgH) {
    if (imgW <= 0 || imgH <= 0) return bounds;
    final scale = math.max(bounds.width / imgW, bounds.height / imgH);
    final w = imgW * scale;
    final h = imgH * scale;
    final left = bounds.left + (bounds.width - w) / 2;
    final top = bounds.top + (bounds.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  /// ローカル画像ファイルを [ui.Image] として読み込む。失敗時は null を返す。
  Future<ui.Image?> _loadImageFile(String? path) async {
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// オブジェクトのラベル・説明テキストを描画する。
  /// [NoteObjectWidget._buildNoteContent] と同じスタイル（影付き）を再現する。
  void _drawObjectText(Canvas canvas, NoteObject o) {
    const padding = 8.0;
    const shadow = [
      ui.Shadow(color: Color(0x66000000), offset: Offset(1, 1), blurRadius: 3),
    ];
    var y = padding;

    if (o.label.isNotEmpty) {
      final span = TextSpan(
        text: o.label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: o.labelColor ?? o.color,
          shadows: shadow,
        ),
      );
      final tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: o.size.width - padding * 2);
      tp.paint(canvas, Offset(padding, y));
      y += tp.height + 4;
    }

    if (o.detail.isNotEmpty) {
      final span = TextSpan(
        text: o.detail,
        style: TextStyle(
          fontSize: 14,
          fontWeight: o.emphasis == Emphasis.strong ? FontWeight.bold : null,
          color: o.descriptionColor ?? o.color,
          shadows: shadow,
        ),
      );
      final tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: o.size.width - padding * 2);
      tp.paint(canvas, Offset(padding, y));
    }
  }

  /// アプリのアイコンを読み込む。失敗した場合は null を返す。
  Future<ui.Image?> _loadIcon() async {
    try {
      final data = await rootBundle.load('web/icons/Icon-512.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// ヘッダー（アイコン + キャンバス名）と内容を含む完全な出力を [ui.Image] にレンダリングする。
  Future<ui.Image> _renderFull(
    CanvasState state,
    String canvasName,
    BackgroundConfig background,
  ) async {
    final bounds = _computeContentBounds(state);

    // オブジェクトがない場合は、ヘッダー + 小さな空白領域のみ出力する。
    final contentImage = bounds == Rect.zero
        ? await _renderEmptyContent()
        : await _renderContent(state, bounds, background);

    final contentWidth = contentImage.width.toDouble();
    final contentHeight = contentImage.height.toDouble();

    final headerHeight = _iconSize + _headerPadding * 2;
    final double totalWidth = math.max(contentWidth, _minWidth);
    final double totalHeight = headerHeight + contentHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 背景（白）
    canvas.drawRect(
      Rect.fromLTWH(0, 0, totalWidth, totalHeight),
      Paint()..color = Colors.white,
    );

    // ヘッダー：アイコン
    final icon = await _loadIcon();
    if (icon != null) {
      final src = Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble());
      final dst = Rect.fromLTWH(
        _headerPadding,
        _headerPadding,
        _iconSize,
        _iconSize,
      );
      canvas.drawImageRect(
        icon,
        src,
        dst,
        Paint()..filterQuality = ui.FilterQuality.high,
      );
    }

    // ヘッダー：キャンバス名
    final nameSpan = TextSpan(
      text: canvasName,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Color(0xFF222222),
      ),
    );
    final nameTp = TextPainter(
      text: nameSpan,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: totalWidth - _headerPadding * 2 - _iconSize - 12);
    final nameY = _headerPadding + (_iconSize - nameTp.height) / 2;
    nameTp.paint(canvas, Offset(_headerPadding + _iconSize + 12, nameY));

    // ヘッダー下の区切り線
    final linePaint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, headerHeight),
      Offset(totalWidth, headerHeight),
      linePaint,
    );

    // 内容（水平中央揃え）
    final contentOffset = Offset((totalWidth - contentWidth) / 2, headerHeight);
    canvas.drawImage(contentImage, contentOffset, Paint());

    final picture = recorder.endRecording();
    return picture.toImage(totalWidth.round(), totalHeight.round());
  }

  /// オブジェクトがない場合の小さな内容領域（メッセージ付き）を描画する。
  Future<ui.Image> _renderEmptyContent() async {
    const width = _minWidth;
    const height = 120.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );
    final span = TextSpan(
      text: 'オブジェクトがありません',
      style: const TextStyle(fontSize: 16, color: Color(0xFF888888)),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((width - tp.width) / 2, (height - tp.height) / 2));
    final picture = recorder.endRecording();
    return picture.toImage(width.round(), height.round());
  }

  /// キャンバス状態を PNG バイト列として生成する。
  Future<Uint8List> exportPng(
    CanvasState state,
    String canvasName, {
    BackgroundConfig background = const BackgroundConfig(),
  }) async {
    final image = await _renderFull(state, canvasName, background);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// キャンバス状態を PDF バイト列として生成する。
  ///
  /// 出力画像のサイズに合わせた 1 ページの PDF を生成し、
  /// 画像をページ全体に配置する。
  Future<Uint8List> exportPdf(
    CanvasState state,
    String canvasName, {
    BackgroundConfig background = const BackgroundConfig(),
  }) async {
    final image = await _renderFull(state, canvasName, background);
    final pngBytes =
        (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();

    final pageWidth = image.width.toDouble();
    final pageHeight = image.height.toDouble();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pdf.PdfPageFormat(pageWidth, pageHeight),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Container(
          width: pageWidth,
          height: pageHeight,
          child: pw.Image(
            pw.MemoryImage(pngBytes),
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );
    return doc.save();
  }
}
