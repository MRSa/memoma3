import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 説明・詳細を表示するセル。
///
/// - 複数行のテキストは最大 5 行まで表示し、超過分は省略記号（…）で切る。
/// - 含まれる `http://` / `https://` リンクは下線付きで表示し、タップすると
///   ブラウザで開く。
/// - リンク以外の部分（またはセル全体）をタップすると [onEdit] が呼ばれ、
///   編集ダイアログが開く。
class LinkTextCell extends StatelessWidget {
  final String text;
  final VoidCallback onEdit;

  /// 表示する最大行数。
  final int maxLines;

  const LinkTextCell({
    super.key,
    required this.text,
    required this.onEdit,
    this.maxLines = 12,
  });

  /// http(s) リンクをトークン化して [TextSpan] のリストを構築する。
  ///
  /// リンクは [TextSpan.onTap] でブラウザを開き、それ以外は通常テキスト。
  List<InlineSpan> _buildSpans(BuildContext context) {
    final spans = <InlineSpan>[];
    if (text.isEmpty) {
      return [
        const TextSpan(
          text: '-',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ];
    }

    // 行間（height）を 1.5 に設定し、固定行高に収まるようにする。
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      fontSize: 12,
      height: 1.5,
    );
    final normalStyle = const TextStyle(fontSize: 12, height: 1.5);

    final regex = RegExp(r'https?://[^\s]+');
    var last = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start), style: normalStyle));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: linkStyle,
          recognizer: _UrlTapGestureRecognizer(url),
        ),
      );
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: normalStyle));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          // 上下 4px + 左右 5px（隣接セルとの間隔）のマージンを取る。
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Text.rich(
            TextSpan(children: _buildSpans(context)),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// http(s) リンクをタップした際にブラウザで開く [TapGestureRecognizer]。
class _UrlTapGestureRecognizer extends TapGestureRecognizer {
  final String url;

  _UrlTapGestureRecognizer(this.url) {
    onTap = _open;
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // 起動できない環境（Web 未対応等）では何もしない。
    }
  }
}
