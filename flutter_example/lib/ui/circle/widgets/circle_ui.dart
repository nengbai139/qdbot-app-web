import 'package:flutter/material.dart';

import '../../app_theme.dart';
import 'live_gift_honor.dart';

/// 会议 vs 直播界面识别色（全站统一）
const kMeetingAccent = Color(0xFF6366F1);
const kMeetingSurface = Color(0xFF14141F);
const kMeetingScaffold = Color(0xFF0F0F18);
const kMeetingChatBg = Color(0xFF16162A);
const kLiveAccent = Color(0xFFE5484D);
const kLiveSurface = Color(0xDE000000);
const kLiveChatBg = Color(0xFF1A1A1A);

Color circleRoomAccent(bool meeting) => meeting ? kMeetingAccent : kLiveAccent;

Color circleRoomAppBarBg(bool meeting) => meeting ? kMeetingSurface : kLiveSurface;

Color circleRoomScaffoldBg(bool meeting) => meeting ? kMeetingScaffold : Colors.black;

PreferredSizeWidget circleSubAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget>? actions,
  Color? backgroundColor,
  Color? foregroundColor,
  bool? meetingMode,
  PreferredSizeWidget? bottom,
}) {
  final scheme = Theme.of(context).colorScheme;
  final fg = foregroundColor ?? scheme.onSurface;
  final strip = meetingMode == null
      ? bottom
      : PreferredSize(
          preferredSize: Size.fromHeight(3 + (bottom == null ? 0 : bottom.preferredSize.height)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              circleModeStrip(meeting: meetingMode),
              if (bottom != null) bottom,
            ],
          ),
        );
  return AppBar(
    elevation: 0,
    scrolledUnderElevation: 0.5,
    backgroundColor: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
    foregroundColor: fg,
    title: subtitle == null
        ? Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.65), fontWeight: FontWeight.normal)),
            ],
          ),
    actions: actions,
    bottom: strip,
  );
}

Widget circleModeStrip({required bool meeting}) {
  return Container(
    height: 3,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: meeting
            ? [kMeetingAccent, const Color(0xFF818CF8)]
            : [kLiveAccent, const Color(0xFFFF6B6B)],
      ),
    ),
  );
}

/// 观众/主持房间顶栏：模式图标 + 标签 + 标题
Widget circleRoomTitleHeader({
  required bool meeting,
  required String title,
  String? subtitle,
  Color? titleColor,
  Color? subtitleColor,
  VoidCallback? onSubtitleTap,
}) {
  final accent = circleRoomAccent(meeting);
  final tc = titleColor ?? Colors.white;
  final sc = subtitleColor ?? Colors.white70;
  Widget? sub;
  if (subtitle != null && subtitle.isNotEmpty) {
    sub = Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: sc));
    if (onSubtitleTap != null) {
      sub = GestureDetector(
        onTap: onSubtitleTap,
        child: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: sc, decoration: TextDecoration.underline, decorationColor: Colors.white38),
        ),
      );
    }
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(meeting ? Icons.groups_rounded : Icons.live_tv_rounded, size: 20, color: accent),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              meeting ? '视频会议' : '直播间',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent, letterSpacing: 0.4),
            ),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: tc)),
            if (sub != null) sub,
          ],
        ),
      ),
    ],
  );
}

BoxDecoration circleRoomVideoFrameDecoration(bool meeting) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: circleRoomAccent(meeting).withValues(alpha: meeting ? 0.55 : 0.35), width: meeting ? 2 : 1),
    boxShadow: meeting
        ? [BoxShadow(color: kMeetingAccent.withValues(alpha: 0.15), blurRadius: 12, spreadRadius: 0)]
        : [BoxShadow(color: kLiveAccent.withValues(alpha: 0.08), blurRadius: 8)],
  );
}

class CircleEmptyBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;
  final bool onDark;

  const CircleEmptyBox({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.iconColor,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconC = iconColor ?? (onDark ? Colors.white38 : scheme.outline);
    final titleColor = onDark ? Colors.white : null;
    final subColor = onDark ? Colors.white60 : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: iconC),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: subColor),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// 列表式动态分隔（与圈子首页一致）
Widget circleFeedDivider(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Divider(
    height: 1,
    indent: 68,
    endIndent: 16,
    color: scheme.outlineVariant.withValues(alpha: 0.35),
  );
}

Widget circleMeetingBadge({bool compact = false}) {
  return Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
    decoration: BoxDecoration(
      color: kMeetingAccent,
      borderRadius: BorderRadius.circular(compact ? 4 : 6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.groups_rounded, size: compact ? 10 : 11, color: Colors.white),
        SizedBox(width: compact ? 3 : 4),
        Text(
          '会议',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}

Widget circleLiveBadge({bool compact = false}) {
  return Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 3),
    decoration: BoxDecoration(
      color: kLiveAccent,
      borderRadius: BorderRadius.circular(compact ? 4 : 6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 5 : 6,
          height: compact ? 5 : 6,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
        SizedBox(width: compact ? 4 : 5),
        Text(
          'LIVE',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}

Widget circleIconAction({
  required IconData icon,
  required VoidCallback onTap,
  String? tooltip,
  Color? color,
}) {
  return Material(
    color: (color ?? AppTheme.brandBlue).withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Tooltip(
        message: tooltip ?? '',
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: color ?? AppTheme.brandBlue),
        ),
      ),
    ),
  );
}

PreferredSizeWidget circleComposeAppBar(
  BuildContext context, {
  required String title,
  required VoidCallback? onPublish,
  String publishLabel = '发布',
}) {
  return circleSubAppBar(
    context,
    title: title,
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: FilledButton(
          onPressed: onPublish,
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: Text(publishLabel),
        ),
      ),
    ],
  );
}

Widget circleSheetHandle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.outlineVariant.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

enum CircleBannerKind { info, success, warning }

class CircleStatusBanner extends StatelessWidget {
  final String text;
  final CircleBannerKind kind;

  const CircleStatusBanner({super.key, required this.text, this.kind = CircleBannerKind.info});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      CircleBannerKind.success => (Colors.green.shade50, Colors.green.shade800, Colors.green.shade200),
      CircleBannerKind.warning => (Colors.orange.shade50, Colors.orange.shade900, Colors.orange.shade200),
      CircleBannerKind.info => (AppTheme.brandBlue.withValues(alpha: 0.08), AppTheme.brandBlue, AppTheme.brandBlue.withValues(alpha: 0.2)),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, height: 1.45, color: fg)),
    );
  }
}

class CircleCopyTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const CircleCopyTile({super.key, required this.label, required this.value, this.onCopy});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          if (onCopy != null && value.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_outlined, size: 20),
              onPressed: onCopy,
              tooltip: '复制',
            ),
        ],
      ),
    );
  }
}

Widget circleSectionTitle(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
  );
}

Widget circleVisibilitySegments({
  required String value,
  required ValueChanged<String>? onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'public', label: Text('公开')),
          ButtonSegment(value: 'friends', label: Text('好友')),
          ButtonSegment(value: 'private', label: Text('私密')),
        ],
        selected: {value},
        onSelectionChanged: onChanged == null ? null : (s) => onChanged(s.first),
      ),
      const SizedBox(height: 8),
      Text(
        circleVisibilityHint(value),
        style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey.shade600),
      ),
    ],
  );
}

String circleVisibilityHint(String value) {
  switch (value) {
    case 'public':
      return '所有人可见';
    case 'private':
      return '仅自己可见';
    default:
      return '与你聊过天的 IM 好友、以及圈子互相关注的人可见';
  }
}

String circleVisibilityLabel(String value) {
  switch (value) {
    case 'public':
      return '公开';
    case 'private':
      return '私密';
    default:
      return '好友可见';
  }
}

/// 直播间打赏飘条（观众/主播共用）
class LiveGiftBanner extends LiveGiftHonorBanner {
  const LiveGiftBanner({super.key, required super.gift, super.compact = false});
}

bool liveMessageIsGift(String text) => text.startsWith('送出 ');
