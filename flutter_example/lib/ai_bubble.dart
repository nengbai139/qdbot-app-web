import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'ui/app_theme.dart';
import 'ui/chat_helpers.dart';
import 'ui/im_media.dart';
import 'util/media_url.dart';

class AiBubble extends StatelessWidget {
  final bool isUser, isMarkdown, isBot;
  final String content;
  final String? contentType;
  final String? createdAt;
  final String? skillUsed;
  final BuildContext context;
  final Set<String>? mentionMeNames;
  const AiBubble({
    super.key,
    required this.isUser,
    required this.isMarkdown,
    required this.content,
    this.contentType,
    this.createdAt,
    this.skillUsed,
    required this.context,
    this.isBot = false,
    this.mentionMeNames,
  });

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(msgDay).inDays;
      final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (diff == 0) return t;
      if (diff == 1) return '昨天 $t';
      if (diff < 7) return '${['周一', '周二', '周三', '周四', '周五', '周六', '周日'][dt.weekday - 1]} $t';
      return '${dt.month}/${dt.day} $t';
    } catch (_) {
      return '';
    }
  }

  String? _assistantModeLabel() {
    if (isUser) return null;
    final su = (skillUsed ?? '').trim();
    if (su.startsWith('user:')) return '专有 Skill';
    return '自由对话';
  }

  Widget _modeChip(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _quoteBar(String quote) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppTheme.brandBlue.withValues(alpha: 0.5), width: 3)),
      ),
      child: Text(quote, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade700)),
    );
  }

  Widget _bodyText(String text, {required Color color}) {
    // 气泡靠左/靠右由 ImMessageRow 控制；框内文字始终左对齐（多行可读）
    return Text(text, textAlign: TextAlign.left, style: TextStyle(color: color, fontSize: 15, height: 1.45));
  }

  Widget _markdown(String data, Brightness brightness) {
    final body = normalizeMarkdownContent(data);
    final onSurface = brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.87) : Colors.black87;
    final sheet = MarkdownStyleSheet(
      p: TextStyle(fontSize: 15, height: 1.55, color: onSurface),
      h1: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: onSurface),
      h2: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface),
      h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
      listBullet: TextStyle(fontSize: 15, height: 1.55, color: onSurface),
      blockquote: TextStyle(fontSize: 14, height: 1.5, color: onSurface.withValues(alpha: 0.75)),
      code: TextStyle(fontSize: 13, backgroundColor: brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100),
      codeblockDecoration: BoxDecoration(
        color: brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        color: brightness == Brightness.dark ? Colors.blue.withValues(alpha: 0.12) : Colors.blue.shade50,
        border: Border(left: BorderSide(color: Colors.blue.shade200, width: 3)),
      ),
      tableBorder: TableBorder.all(color: Colors.grey.withValues(alpha: brightness == Brightness.dark ? 0.35 : 0.3), width: 0.5),
      tableHead: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: onSurface),
      tableBody: TextStyle(fontSize: 12, height: 1.35, color: onSurface),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableScrollbarThumbVisibility: true,
      tablePadding: EdgeInsets.zero,
    );
    return MarkdownBody(
      data: body,
      extensionSet: md.ExtensionSet.gitHubWeb,
      selectable: true,
      shrinkWrap: true,
      fitContent: true,
      styleSheet: sheet,
    );
  }

  Widget _image(String url, BuildContext ctx) {
    final src = publicMediaUrl(url);
    return GestureDetector(
      onTap: () => showImageViewer(ctx, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          src,
          key: ValueKey(src),
          fit: BoxFit.cover,
          width: 200,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: 200,
              height: 120,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress.expectedTotalBytes == null
                      ? null
                      : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            width: 200,
            height: 80,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    final parsed = parseQuotedContent(content);
    final display = parsed.body;
    final brightness = Theme.of(ctx).brightness;
    final isImage = contentType == 'image' || (display.startsWith('http') && RegExp(r'\.(jpg|jpeg|png|gif|webp)(\?|$)', caseSensitive: false).hasMatch(display));
    final ts = _fmt(createdAt);
    final bg = isImage
        ? Colors.transparent
        : (isUser
            ? AppTheme.brandBlue
            : (isBot ? AppTheme.bubbleBotFor(brightness) : (isMarkdown ? Theme.of(ctx).colorScheme.surface : AppTheme.bubbleOtherFor(brightness))));
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
      bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBot)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy, size: 12, color: Colors.deepPurple.shade300),
                  const SizedBox(width: 4),
                  Text('AI 代答', style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade300)),
                ],
              ),
            )
          else if (_assistantModeLabel() case final label?)
            _modeChip(label, label == '专有 Skill' ? Colors.teal.shade600 : Colors.blueGrey.shade500),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.72),
            padding: isImage ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              boxShadow: isImage ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (parsed.quote != null) _quoteBar(parsed.quote!),
                if (isImage)
                  _image(display, ctx)
                else if (isUser)
                  mentionMeNames != null
                      ? plainTextWithMentions(display, align: TextAlign.left, color: Colors.white, meNames: mentionMeNames!)
                      : _bodyText(display, color: Colors.white)
                else if (isMarkdown)
                  _markdown(display, brightness)
                else
                  mentionMeNames != null
                      ? plainTextWithMentions(display, align: TextAlign.left, color: Theme.of(ctx).colorScheme.onSurface, meNames: mentionMeNames!)
                      : _bodyText(display, color: Theme.of(ctx).colorScheme.onSurface),
              ],
            ),
          ),
          if (!isImage && display.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ts.isNotEmpty)
                    Text(ts, style: TextStyle(fontSize: 10, color: Colors.grey[500], height: 1.2)),
                  if (ts.isNotEmpty) const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => copyMessageText(
                      ctx,
                      isMarkdown && !isUser ? normalizeMarkdownContent(display) : content,
                    ),
                    child: Icon(Icons.copy_rounded, size: 12, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
