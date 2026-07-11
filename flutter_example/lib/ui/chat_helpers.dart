import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/im_api.dart';
import 'app_theme.dart';
import 'circle/meeting_deep_link.dart';
import 'premium/contact_card.dart';
import 'premium/user_code_display.dart';

/// 从 WS 消息解析 AI 会话 ID（兼容 convId / sessionId / ext）
String aiConvIdFromWs(Map<String, dynamic> m) {
  final ext = m['ext'];
  return (m['convId'] ??
          m['sessionId'] ??
          m['sessionID'] ??
          (ext is Map ? ext['convId'] : null) ??
          '')
      .toString();
}

/// enterprise-gateway / qdbot_system AI 过程反馈（空包或阶段文案），非最终回复
bool isAgentProgressContent(String content) {
  final t = content.trim();
  if (t.isEmpty) return true;
  // ponytail: 财经/研报最终回复很长且含涨跌幅 %，不能当过程反馈
  if (t.length >= 240) return false;
  if (t.contains('█') && t.contains('░')) return true;
  // 短进度条百分比（非 Markdown 表格里的 2.50%）
  if (t.length < 120 && !t.contains('|') && RegExp(r'\d+\s*%').hasMatch(t)) return true;
  if (t.length < 200) {
    const progressEmojis = ['🎯', '🛠', '📋', '🏗', '📝', '💻', '⚙', '✅', '📦', '🔄'];
    for (final e in progressEmojis) {
      if (t.startsWith(e)) return true;
    }
    const stages = [
      '意图识别', '技能选择', '需求分析', '架构设计', '任务规划', '开发执行', '工具执行',
      '验证检查', '交付完成', 'Loop Engineering', 'QDBotClaw', '已收到您的请求', '移交 QDBotClaw',
      '正在调用', '获取实时数据', '正在处理',
    ];
    for (final s in stages) {
      if (t.contains(s)) return true;
    }
  }
  return false;
}

int aiMessageId(dynamic m) {
  if (m is! Map) return 0;
  final v = m['id'];
  if (v is int) return v;
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

int aiLastUserIndex(List<dynamic> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    if ((messages[i]['role'] ?? '').toString() == 'user') return i;
  }
  return -1;
}

String? aiLastUserContent(List<dynamic> messages) {
  final i = aiLastUserIndex(messages);
  if (i < 0) return null;
  return (messages[i]['content'] ?? '').toString();
}

/// ponytail: 乐观 user 消息尚未落库时，server 列表更短/含进度条会把它冲掉
List<dynamic> mergeAiMessagesWithPending(List<dynamic> local, List<dynamic> server) {
  if (aiServerCaughtUpWithLocal(local, server)) return List<dynamic>.from(server);
  final out = List<dynamic>.from(server);
  for (var i = server.length; i < local.length; i++) {
    out.add(local[i]);
  }
  final lu = aiLastUserContent(local);
  if (lu != null && aiLastUserContent(out) != lu) {
    for (var i = local.length - 1; i >= 0; i--) {
      final m = local[i];
      if (m is! Map || (m['role'] ?? '').toString() != 'user') continue;
      if ((m['content'] ?? '').toString() == lu && aiMessageId(m) <= 0) {
        out.add(Map<String, dynamic>.from(m));
        break;
      }
    }
  }
  return out;
}

/// server 尚未包含刚发送的 user 消息时，勿用旧 assistant 回复覆盖列表
bool aiServerCaughtUpWithLocal(List<dynamic> local, List<dynamic> server) {
  final localUser = aiLastUserContent(local);
  if (localUser == null) return true;
  return aiLastUserContent(server) == localUser;
}

bool hasMarkdown(String s) {
  if (s.length < 2) return false;
  for (final p in ['###', '## ', '# ', '**', '```', '- ', '1. ', '> ', '|', '|---']) {
    if (s.contains(p)) return true;
  }
  return s.contains('](');
}

bool shouldRenderMarkdown(String content, {String contentType = 'text', bool isUser = false}) {
  if (isUser) return false;
  final ct = contentType.toLowerCase();
  if (ct == 'image' || ct == 'contact_card' || ct == 'user_card' || ct == 'revoked' || ct == 'file' || ct == 'voice' || ct == 'audio' || ct == 'video') return false;
  if (ct == 'markdown') return true;
  return hasMarkdown(content);
}

/// 修正服务端模板/LLM 输出中会破坏 GFM 解析的 Markdown 片段。
String normalizeMarkdownContent(String s) {
  var out = s.trim();
  if (out.isEmpty) return out;

  final fenced = RegExp(r'^```(?:markdown|md)?\s*\r?\n([\s\S]*?)\r?\n```\s*$');
  final fm = fenced.firstMatch(out);
  if (fm != null) out = fm.group(1)!.trim();

  // 未渲染的模板占位符
  out = out.replaceAll(RegExp(r'\{\{[^}]+\}\}'), '暂缺');

  // ponytail: finance 模板里单行 | ⏰ ... | 会让后续表格解析错乱
  out = out.replaceAllMapped(
    RegExp(r'^\|\s*⏰\s*(.+?)\s*\|\s*$', multiLine: true),
    (m) => '⏰ ${m.group(1)!.trim()}',
  );

  // 仅一列的伪表格行 → 普通文本
  out = out.replaceAllMapped(
    RegExp(r'^\|\s*([^|\n]+?)\s*\|\s*$', multiLine: true),
    (m) => m.group(1)!.trim(),
  );

  // ponytail: 指数表后的 orphan 全市场行 → 列表项
  out = out.replaceAllMapped(
    RegExp(r'^\|\s*\*\*全市场\*\*\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*—\s*\|\s*$', multiLine: true),
    (m) => '- **全市场**：${m.group(1)!.trim()} · ${m.group(2)!.trim()}',
  );

  out = _ensureBlankLineBeforeTables(out);
  out = _normalizeMarkdownTables(out);
  return out;
}

bool _isTableLine(String trimmed) =>
    trimmed.startsWith('|') && trimmed.indexOf('|', 1) > 0;

bool _isTableSeparatorLine(String trimmed) {
  if (!_isTableLine(trimmed)) return false;
  final cells = trimmed.split('|').where((c) => c.trim().isNotEmpty).toList();
  if (cells.isEmpty) return false;
  return cells.every((c) => RegExp(r'^[\s\-:]+$').hasMatch(c));
}

int _tableColumnCount(String trimmed) {
  final parts = trimmed.split('|');
  if (parts.length <= 2) return 0;
  return parts.length - 2;
}

String _makeTableSeparator(int columns) {
  if (columns <= 0) return '';
  return '| ${List.filled(columns, '---').join(' | ')} |';
}

String _normalizeSeparatorLine(String line) {
  final trimmed = line.trim();
  if (!_isTableSeparatorLine(trimmed)) return line;
  return _makeTableSeparator(_tableColumnCount(trimmed));
}

/// 去掉表格块内的空行，并补齐缺失的 GFM 分隔行。
String _normalizeMarkdownTables(String s) {
  final lines = s.split('\n');
  final out = <String>[];

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final trimmed = line.trimLeft();

    if (_isTableLine(trimmed)) {
      // ponytail: 模板缩进会让 GFM 无法识别表格，必须顶格 |
      line = _normalizeSeparatorLine(trimmed);
    } else if (line.trim().isEmpty) {
      final prevTable = out.isNotEmpty && _isTableLine(out.last);
      var nextTable = false;
      for (var j = i + 1; j < lines.length; j++) {
        final t = lines[j].trim();
        if (t.isEmpty) continue;
        nextTable = _isTableLine(t);
        break;
      }
      if (prevTable && nextTable) continue;
    }

    out.add(line);

    // 仅表头后缺分隔行时补齐（勿在每条数据行后插入）
    if (_isTableLine(trimmed) && !_isTableSeparatorLine(trimmed)) {
      final prevIsTable = out.length >= 2 && _isTableLine(out[out.length - 2]);
      if (!prevIsTable) {
        var j = i + 1;
        while (j < lines.length && lines[j].trim().isEmpty) {
          j++;
        }
        if (j < lines.length) {
          final next = lines[j].trimLeft();
          if (_isTableLine(next) && !_isTableSeparatorLine(next)) {
            out.add(_makeTableSeparator(_tableColumnCount(trimmed)));
          }
        }
      }
    }
  }

  return out.join('\n');
}

String _ensureBlankLineBeforeTables(String s) {
  final lines = s.split('\n');
  final out = <String>[];
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (_isTableLine(trimmed) && out.isNotEmpty) {
      final prev = out.last.trim();
      if (prev.isNotEmpty && !_isTableLine(prev)) out.add('');
    }
    out.add(line);
  }
  return out.join('\n');
}

/// IM 通知/列表预览文案（图片、语音等非文本消息）
String imNotifyPreview(Map<String, dynamic> msg) {
  final ct = (msg['contentType'] ?? msg['ext']?['contentType'] ?? 'text').toString();
  final content = (msg['content'] ?? msg['ext']?['content'] ?? '').toString();
  switch (ct) {
    case 'image':
      return '[图片]';
    case 'file':
      return content.isNotEmpty ? '[文件] $content' : '[文件]';
    case 'audio':
    case 'voice':
      return '[语音]';
    case 'video':
      return '[视频]';
    case 'revoked':
      return '[消息已撤回]';
    case 'meeting_invite':
      final invite = tryParseMeetingInvite(content, contentType: ct);
      if (invite != null) return meetingInvitePreviewLabel(invite);
      return '[会议邀请]';
    case 'contact_card':
    case 'user_card':
      final card = tryParseContactCard(content, contentType: ct);
      if (card != null) return contactCardPreviewLabel(card);
      return '[名片]';
    default:
      final invite = tryParseMeetingInvite(content);
      if (invite != null) return meetingInvitePreviewLabel(invite);
      final card = tryParseContactCard(content);
      if (card != null) return contactCardPreviewLabel(card);
      if (content.isEmpty) return '收到一条消息';
      return content.length > 80 ? '${content.substring(0, 80)}…' : content;
  }
}

String? messageDayKey(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month}-${dt.day}';
  } catch (_) {
    return null;
  }
}

String formatDaySeparator(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) {
      const w = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return w[dt.weekday - 1];
    }
    return '${dt.year}年${dt.month}月${dt.day}日';
  } catch (_) {
    return '';
  }
}

Widget chatDateChip(String label) {
  if (label.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ),
    ),
  );
}

/// ponytail: regex @token scan; good enough for IM display
Widget plainTextWithMentions(
  String text, {
  required TextAlign align,
  required Color color,
  Set<String> meNames = const {},
  Color? onDarkMentionColor,
}) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'@[^\s@\n]+');
  var i = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > i) {
      spans.add(TextSpan(text: text.substring(i, m.start), style: TextStyle(color: color, fontSize: 15, height: 1.45)));
    }
    final token = m.group(0)!;
    final name = token.substring(1);
    final isAll = name == '所有人';
    final isMe = isAll || meNames.contains(name);
    final mentionColor = color == Colors.white
        ? (onDarkMentionColor ?? Colors.amber.shade100)
        : (isMe ? Colors.red.shade700 : AppTheme.brandBlue);
    spans.add(TextSpan(
      text: token,
      style: TextStyle(color: mentionColor, fontWeight: FontWeight.w600, fontSize: 15, height: 1.45),
    ));
    i = m.end;
  }
  if (i < text.length) {
    spans.add(TextSpan(text: text.substring(i), style: TextStyle(color: color, fontSize: 15, height: 1.45)));
  }
  if (spans.isEmpty) {
    return Text(text, textAlign: align, style: TextStyle(color: color, fontSize: 15, height: 1.45));
  }
  return RichText(textAlign: align, text: TextSpan(children: spans));
}

/// 消息列表 + 日期分隔（messages[0] 为最新，配合 ListView reverse）
List<Object> buildMessageListWithDates(List<dynamic> messages) {
  final items = <Object>[];
  for (var i = 0; i < messages.length; i++) {
    items.add(messages[i]);
    if (i + 1 < messages.length) {
      final tsA = (messages[i]['createdAt'] ?? messages[i]['created_at'])?.toString();
      final tsB = (messages[i + 1]['createdAt'] ?? messages[i + 1]['created_at'])?.toString();
      if (messageDayKey(tsA) != messageDayKey(tsB)) {
        items.add(formatDaySeparator(tsB));
      }
    }
  }
  return items;
}

void copyMessageText(BuildContext context, String text) {
  final t = text.trim();
  if (t.isEmpty) return;
  Clipboard.setData(ClipboardData(text: t));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating, width: 100),
  );
}

void showMessageActionSheet(
  BuildContext context, {
  required String content,
  VoidCallback? onReply,
  VoidCallback? onRevoke,
  VoidCallback? onForward,
}) {
  showModalBottomSheet(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onReply != null)
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('引用回复'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onReply();
              },
            ),
          if (onForward != null)
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('转发到 IM'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onForward();
              },
            ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制'),
            onTap: () {
              Navigator.pop(sheetCtx);
              copyMessageText(context, content);
            },
          ),
          if (onRevoke != null)
            ListTile(
              leading: const Icon(Icons.undo, color: Colors.red),
              title: const Text('撤回', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetCtx);
                onRevoke();
              },
            ),
        ],
      ),
    ),
  );
}

Widget replyPreviewBar({required String quote, required VoidCallback onCancel}) {
  return Material(
    color: Colors.blue.shade50,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(quote, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onCancel, visualDensity: VisualDensity.compact),
        ],
      ),
    ),
  );
}

String applyReplyQuote(String content, Map<String, dynamic>? replyTo) {
  if (replyTo == null) return content;
  final quote = (replyTo['content'] ?? '').toString();
  if (quote.isEmpty) return content;
  return '> $quote\n$content';
}

class ParsedMessage {
  final String? quote;
  final String body;
  const ParsedMessage({this.quote, required this.body});
}

/// 解析 `> 引用\n正文` 格式
ParsedMessage parseQuotedContent(String raw) {
  if (!raw.startsWith('> ')) return ParsedMessage(body: raw);
  final lines = raw.split('\n');
  final quoteLines = <String>[];
  var i = 0;
  while (i < lines.length && lines[i].startsWith('> ')) {
    quoteLines.add(lines[i].substring(2));
    i++;
  }
  if (i < lines.length && lines[i].isEmpty) i++;
  final body = lines.skip(i).join('\n');
  if (quoteLines.isEmpty) return ParsedMessage(body: raw);
  return ParsedMessage(quote: quoteLines.join('\n'), body: body.isEmpty ? raw : body);
}

String formatSessionTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    final hm = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return hm;
    if (diff == 1) return '昨天';
    if (diff < 7) return ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][dt.weekday - 1];
    return '${dt.month}/${dt.day}';
  } catch (_) {
    return '';
  }
}

int sessionTimeMs(dynamic item, {bool group = false}) {
  final iso = group
      ? (item['updatedAt'] ?? item['lastMsgTime'] ?? item['createdAt'])
      : (item['lastMsgTime'] ?? item['updatedAt'] ?? item['createdAt']);
  if (iso == null || iso.toString().isEmpty) return 0;
  try {
    return DateTime.parse(iso.toString()).millisecondsSinceEpoch;
  } catch (_) {
    return 0;
  }
}

int parseCount(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

int sessionUnread(dynamic item, {bool group = false}) {
  final u = group ? item['unreadCount'] : (item['unreadCount'] ?? item['unread']);
  return parseCount(u);
}

bool lastMsgMentionsMe(String last, Set<String> myNames) {
  if (last.isEmpty) return false;
  if (last.contains('@所有人')) return true;
  for (final n in myNames) {
    if (n.isNotEmpty && last.contains('@$n')) return true;
  }
  return false;
}

/// 置顶 → @我未读 → 未读多 → 最近活跃
int compareImSessions(
  dynamic a,
  dynamic b, {
  required bool group,
  required int Function(String key) pinRank,
  required String Function(dynamic item) pinKeyOf,
  int Function(dynamic item)? mentionRank,
}) {
  final pr = pinRank(pinKeyOf(a)).compareTo(pinRank(pinKeyOf(b)));
  if (pr != 0) return pr;
  if (mentionRank != null) {
    final mr = mentionRank(a).compareTo(mentionRank(b));
    if (mr != 0) return mr;
  }
  final ur = sessionUnread(b, group: group).compareTo(sessionUnread(a, group: group));
  if (ur != 0) return ur;
  return sessionTimeMs(b, group: group).compareTo(sessionTimeMs(a, group: group));
}

/// 会话列表 lastMsg → 可读预览（兼容旧数据 URL / 无 contentType）
String sessionLastPreview(dynamic session) {
  final last = (session['lastMsg'] ?? '').toString();
  if (last.isEmpty) return last;
  if (last.startsWith('[')) return last;
  final ct = (session['lastMsgType'] ?? session['lastContentType'] ?? '').toString();
  if (ct.isNotEmpty) {
    return imNotifyPreview({'content': last, 'contentType': ct});
  }
  final lower = last.toLowerCase();
  if (lower.startsWith('http') && RegExp(r'\.(jpg|jpeg|png|gif|webp)(\?|$)', caseSensitive: false).hasMatch(lower)) {
    return '[图片]';
  }
  return last;
}

/// 用户记录可搜字段（通讯录 API / 会话 enrichment）
String userRecordSearchBlob(dynamic u) {
  if (u is! Map) return u.toString();
  final parts = [
    u['nickname'],
    u['displayName'],
    u['peerName'],
    u['peerNickname'],
    u['userCode'],
    u['peerUserCode'],
    u['userId'],
    u['peerUserId'],
    u['email'],
    u['phone'],
  ];
  return parts.map((v) => (v ?? '').toString()).where((s) => s.isNotEmpty).join(' ');
}

/// 会话列表本地搜索字段（昵称、UserCode、群名、最后消息摘要；不含历史消息全文）
String sessionSearchBlob(dynamic session, {bool group = false}) {
  if (group) {
    final name = (session['groupName'] ?? session['name'] ?? '').toString();
    final rawLast = (session['lastMsg'] ?? '').toString();
    final preview = sessionLastPreview(session);
    final notice = (session['notice'] ?? '').toString();
    final members = (session['members'] as List<dynamic>?) ?? [];
    final memberText = members
        .map((m) => '${m['nickname'] ?? ''} ${m['displayName'] ?? ''} ${m['userCode'] ?? ''} ${m['userId'] ?? ''} ${m['alias'] ?? ''}')
        .join(' ');
    return '$name $rawLast $preview $notice $memberText';
  }
  final peerId = (session['peerUserId'] ?? session['peerId'] ?? session['userId'] ?? '').toString();
  final peerName = (session['peerName'] ?? '').toString();
  final peerCode = (session['peerUserCode'] ?? session['userCode'] ?? '').toString();
  final rawLast = (session['lastMsg'] ?? '').toString();
  final preview = sessionLastPreview(session);
  final profile = userRecordSearchBlob(session);
  return '$peerName $peerId $peerCode $rawLast $preview $profile';
}

bool sessionMatchesQuery(dynamic session, String query, {bool group = false}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return sessionSearchBlob(session, group: group).toLowerCase().contains(q);
}

bool userRecordMatchesQuery(dynamic user, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return userRecordSearchBlob(user).toLowerCase().contains(q);
}

String sessionListPreview(
  dynamic session, {
  bool pinned = false,
  bool muted = false,
  bool mentionUnread = false,
  bool newNotice = false,
}) {
  return buildSessionPreview(
    last: sessionLastPreview(session),
    pinned: pinned,
    muted: muted,
    mentionUnread: mentionUnread,
    newNotice: newNotice,
  );
}

/// 会话列表预览：状态用 [标签] 文字前缀，避免 title 堆图标
String buildSessionPreview({
  required String last,
  bool pinned = false,
  bool muted = false,
  bool mentionUnread = false,
  bool newNotice = false,
}) {
  final tags = <String>[];
  if (pinned) tags.add('置顶');
  if (muted) tags.add('免打扰');
  if (mentionUnread) tags.add('@我');
  if (newNotice) tags.add('公告');
  final prefix = tags.isEmpty ? '' : '[${tags.join('·')}] ';
  final body = last.isEmpty ? '暂无消息' : last;
  return '$prefix$body';
}

/// 微信式消息行：左他人右自己，头像 + 气泡对齐
class ImMessageRow extends StatelessWidget {
  final bool isMe;
  final String avatarLabel;
  final String? senderName;
  final String? senderUserCode;
  final String? senderLevelName;
  final VoidCallback? onSenderTap;
  final bool mentioned;
  final Widget bubble;

  const ImMessageRow({
    super.key,
    required this.isMe,
    required this.avatarLabel,
    required this.bubble,
    this.senderName,
    this.senderUserCode,
    this.senderLevelName,
    this.onSenderTap,
    this.mentioned = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor: isMe ? AppTheme.brandBlue.withValues(alpha: 0.15) : Colors.grey.shade300,
      child: Text(
        avatarLabel.isNotEmpty ? avatarLabel[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isMe ? AppTheme.brandBlue : Colors.grey.shade700,
        ),
      ),
    );

    final content = Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isMe && (senderName ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: GestureDetector(
              onTap: onSenderTap,
              behavior: HitTestBehavior.opaque,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  Text(senderName!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  if ((senderUserCode ?? '').isNotEmpty)
                    Text(senderUserCode!, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  if ((senderLevelName ?? '').isNotEmpty && senderLevelName != '普通')
                    PremiumLevelChip(levelName: senderLevelName!, compact: true),
                ],
              ),
            ),
          ),
        if (mentioned && !isMe)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('@我', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
            ),
          ),
        bubble,
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isMe
            ? [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: content,
                  ),
                ),
                const SizedBox(width: 8),
                avatar,
              ]
            : [
                avatar,
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: content,
                  ),
                ),
              ],
      ),
    );
  }
}

Future<void> markIncomingRead(
  ImApi im,
  List<dynamic> messages,
  bool Function(dynamic) isMe, {
  VoidCallback? onUpdated,
}) async {
  final ids = <String>[];
  for (final m in messages) {
    final id = (m['msgId'] ?? '').toString();
    if (id.isEmpty || id.startsWith('local_') || isMe(m)) continue;
    if (messageIsRead(m)) continue;
    ids.add(id);
  }
  // ponytail: cap server round-trips; UI marks all incoming read while viewing
  for (final id in ids.take(20)) {
    try {
      await im.markRead(id);
    } catch (_) {}
  }
  for (final m in messages) {
    if (m is Map && !isMe(m)) m['status'] = 'read';
  }
  onUpdated?.call();
}

bool messageIsRead(dynamic m) => (m['status'] ?? '').toString() == 'read';

Widget messageReadBadge(dynamic m, {required bool isMe, bool enabled = true}) {
  if (!enabled) return const SizedBox.shrink();
  final id = (m['msgId'] ?? '').toString();
  if (id.isEmpty || id.startsWith('local_')) return const SizedBox.shrink();
  if ((m['contentType'] ?? '').toString() == 'revoked') return const SizedBox.shrink();
  final read = messageIsRead(m);
  // 收到的消息：仅未读时提示；发出的消息：始终显示已读/未读
  if (!isMe && read) return const SizedBox.shrink();
  return Padding(
    padding: EdgeInsets.only(top: 2, left: isMe ? 0 : 4, right: isMe ? 58 : 4, bottom: 2),
    child: Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        read ? '已读' : '未读',
        style: TextStyle(
          fontSize: 10,
          color: read ? Colors.grey.shade500 : Colors.orange.shade700,
          fontWeight: read ? FontWeight.normal : FontWeight.w500,
        ),
      ),
    ),
  );
}

class ChatComposerAction {
  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ChatComposerAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

Future<void> showChatComposerMoreSheet(BuildContext context, {required List<ChatComposerAction> actions}) {
  if (actions.isEmpty) return Future.value();
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 4,
          childAspectRatio: 0.82,
          children: [
            for (final a in actions)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.pop(ctx);
                  a.onTap();
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Icon(a.icon, size: 26, color: theme.colorScheme.onSurface),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(a.label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.75)), maxLines: 1),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// 顶部/AppBar 与输入栏统一的「+」按钮（文字渲染，避免 Web 上 MaterialIcons 错位）
Widget toolbarPlusButton(BuildContext context, {required VoidCallback onPressed, String tooltip = '更多'}) {
  final theme = Theme.of(context);
  return IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Text(
      '+',
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w300,
        height: 1,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
      ),
    ),
  );
}

Widget composerPlusButton(BuildContext context, {required VoidCallback onPressed}) {
  final theme = Theme.of(context);
  return IconButton(
    tooltip: '更多',
    onPressed: onPressed,
    padding: const EdgeInsets.all(8),
    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    icon: Text(
      '+',
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w300,
        height: 1,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
      ),
    ),
  );
}

Widget chatComposer({
  required BuildContext context,
  required TextEditingController controller,
  required VoidCallback onSend,
  String hint = '输入消息…',
  Widget? leading,
  VoidCallback? onPickImage,
  VoidCallback? onPickFile,
  VoidCallback? onPickDrive,
  VoidCallback? onPickVoice,
  VoidCallback? onPickVideo,
  List<ChatComposerAction>? moreActions,
  ValueChanged<String>? onChanged,
  bool enterToSend = true,
}) {
  final theme = Theme.of(context);
  final attachActions = <ChatComposerAction>[
    if (onPickImage != null)
      ChatComposerAction(id: 'image', icon: Icons.image_outlined, label: '图片', onTap: onPickImage),
    if (onPickFile != null)
      ChatComposerAction(id: 'file', icon: Icons.insert_drive_file_outlined, label: '文件', onTap: onPickFile),
    if (onPickDrive != null)
      ChatComposerAction(id: 'drive', icon: Icons.cloud_outlined, label: '云盘', onTap: onPickDrive),
    if (onPickVoice != null)
      ChatComposerAction(id: 'voice', icon: Icons.mic_none_outlined, label: '语音', onTap: onPickVoice),
    if (onPickVideo != null)
      ChatComposerAction(id: 'video', icon: Icons.videocam_outlined, label: '视频', onTap: onPickVideo),
    ...?moreActions,
  ];
  final hasMore = attachActions.isNotEmpty;

  void openMoreSheet() => showChatComposerMoreSheet(context, actions: attachActions);

  return Material(
    elevation: 4,
    color: theme.colorScheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(leading == null ? 12 : 4, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (leading != null) leading,
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                enableInteractiveSelection: true,
                textInputAction: enterToSend ? TextInputAction.send : TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: hint,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
                onSubmitted: enterToSend ? (_) => onSend() : null,
                onChanged: onChanged,
              ),
            ),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded, size: 20),
              style: IconButton.styleFrom(minimumSize: const Size(44, 44), backgroundColor: AppTheme.brandBlue),
            ),
            if (hasMore) composerPlusButton(context, onPressed: openMoreSheet),
          ],
        ),
      ),
    ),
  );
}
