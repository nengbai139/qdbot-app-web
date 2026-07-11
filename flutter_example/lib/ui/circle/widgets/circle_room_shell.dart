import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'circle_ui.dart';
import 'meeting_prejoin_preview.dart';

/// 房间底栏（Zoom / 腾讯会议风格半透明条）
const kRoomControlBarBg = Color(0xE614141A);
const kRoomTopBarBg = Color(0x990A0A0F);

class CircleRoomLobbyView extends StatelessWidget {
  final bool meeting;
  final String title;
  final String message;
  final String? hostName;
  final String? roomId;
  final VoidCallback? onLeave;

  const CircleRoomLobbyView({
    super.key,
    required this.meeting,
    required this.title,
    required this.message,
    this.hostName,
    this.roomId,
    this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final accent = circleRoomAccent(meeting);
    return Scaffold(
      backgroundColor: meeting ? kMeetingScaffold : Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            if (onLeave != null)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: onLeave,
                ),
              ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.15),
                          border: Border.all(color: accent.withValues(alpha: 0.35)),
                        ),
                        child: Icon(Icons.hourglass_top_rounded, size: 32, color: accent),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14),
                      ),
                      if (hostName != null && hostName!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('主持人：$hostName', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
                      ],
                      if (roomId != null && roomId!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('会议号 $roomId', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: roomId!));
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制会议号')));
                                },
                                child: Icon(Icons.copy_rounded, size: 16, color: accent.withValues(alpha: 0.8)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 沉浸式顶栏：标题 + 副标题 + 右侧操作
class CircleRoomTopOverlay extends StatelessWidget {
  final bool meeting;
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget>? trailing;

  const CircleRoomTopOverlay({
    super.key,
    required this.meeting,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accent = circleRoomAccent(meeting);
    return Container(
      padding: EdgeInsets.fromLTRB(4, MediaQuery.paddingOf(context).top + 4, 8, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
              tooltip: '收起',
              onPressed: onBack,
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) ...trailing!,
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(5)),
            child: Text(meeting ? '会议' : '直播', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class CircleRoomControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;
  final bool enabled;
  final bool meeting;

  const CircleRoomControlBtn({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.danger = false,
    this.enabled = true,
    this.meeting = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = circleRoomAccent(meeting);
    Color bg;
    Color fg = Colors.white;
    if (!enabled) {
      bg = Colors.white.withValues(alpha: 0.06);
      fg = Colors.white38;
    } else if (danger) {
      bg = const Color(0xFFDC2626);
    } else if (active) {
      bg = accent;
    } else {
      bg = Colors.white.withValues(alpha: 0.14);
    }
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: bg,
            borderRadius: BorderRadius.circular(26),
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(26),
              child: SizedBox(width: 52, height: 52, child: Icon(icon, color: fg, size: 24)),
            ),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: enabled ? 0.75 : 0.35), fontSize: 11)),
        ],
      ),
    );
  }
}

class CircleRoomControlBar extends StatelessWidget {
  final List<Widget> children;

  const CircleRoomControlBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kRoomControlBarBg,
        border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// 视频格姓名条
class CircleRoomNameBadge extends StatelessWidget {
  final String name;
  final bool accent;
  final IconData? icon;

  const CircleRoomNameBadge({super.key, required this.name, this.accent = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: Colors.white70), const SizedBox(width: 4)],
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: accent ? kMeetingAccent : Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// 无视频时的头像占位
class CircleRoomAvatarPlaceholder extends StatelessWidget {
  final String name;
  final bool meeting;

  const CircleRoomAvatarPlaceholder({super.key, required this.name, this.meeting = true});

  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final accent = circleRoomAccent(meeting);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: accent.withValues(alpha: 0.25),
            child: Text(letter, style: TextStyle(color: accent, fontSize: 28, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          Text(name, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
        ],
      ),
    );
  }
}

/// 会议聊天面板（可嵌入 sheet 或内联）
class CircleRoomChatPanel extends StatelessWidget {
  final bool meeting;
  final TextEditingController controller;
  final VoidCallback onSend;
  final List<Widget> messageTiles;
  final Widget? headerExtra;
  final VoidCallback? onClose;
  final String emptyHint;

  const CircleRoomChatPanel({
    super.key,
    required this.meeting,
    required this.controller,
    required this.onSend,
    required this.messageTiles,
    this.headerExtra,
    this.onClose,
    this.emptyHint = '暂无消息',
  });

  @override
  Widget build(BuildContext context) {
    final accent = circleRoomAccent(meeting);
    return Material(
      color: meeting ? kMeetingChatBg : kLiveChatBg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                Text(meeting ? '聊天' : '弹幕', style: TextStyle(color: accent, fontSize: 14, fontWeight: FontWeight.w600)),
                if (headerExtra != null) ...[const SizedBox(width: 8), headerExtra!],
                const Spacer(),
                if (onClose != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x18FFFFFF)),
          Expanded(
            child: messageTiles.isEmpty
                ? Center(child: Text(emptyHint, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13)))
                : ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 8), children: messageTiles),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '发送消息…',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: accent, minimumSize: const Size(44, 44)),
                  onPressed: onSend,
                  icon: const Icon(Icons.send_rounded, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void showCircleRoomMoreSheet(
  BuildContext context, {
  required bool meeting,
  required List<({IconData icon, String label, VoidCallback? onTap})> actions,
}) {
  final accent = circleRoomAccent(meeting);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: meeting ? kMeetingSurface : const Color(0xFF1A1A1A),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('更多', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...actions.map((a) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(a.icon, color: a.onTap == null ? Colors.white24 : accent),
                title: Text(a.label, style: TextStyle(color: a.onTap == null ? Colors.white38 : Colors.white, fontSize: 15)),
                onTap: a.onTap == null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        a.onTap!();
                      },
              );
            }),
          ],
        ),
      ),
    ),
  );
}

/// 入会/开播前设备预览（Zoom 风格）
class MeetingPreJoinScreen extends StatelessWidget {
  final bool meeting;
  final String title;
  final String? subtitle;
  final String? roomId;
  final String? inviteLink;
  final String joinLabel;
  final String? hint;
  final bool micOn;
  final bool camOn;
  final bool joining;
  final VoidCallback onMicToggle;
  final VoidCallback onCamToggle;
  final VoidCallback onJoin;
  final VoidCallback onCancel;

  const MeetingPreJoinScreen({
    super.key,
    this.meeting = true,
    required this.title,
    this.subtitle,
    this.roomId,
    this.inviteLink,
    this.joinLabel = '加入会议',
    this.hint,
    required this.micOn,
    required this.camOn,
    this.joining = false,
    required this.onMicToggle,
    required this.onCamToggle,
    required this.onJoin,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final accent = circleRoomAccent(meeting);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Scaffold(
      backgroundColor: meeting ? kMeetingScaffold : Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: joining ? null : onCancel,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: _previewPane(accent)),
                          const SizedBox(width: 32),
                          Expanded(child: _sidePane(context, accent)),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: _previewPane(accent)),
                          const SizedBox(height: 24),
                          _sidePane(context, accent),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _previewPane(Color accent) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: MeetingPreJoinPreview(camOn: camOn, meeting: meeting),
    );
  }

  Widget _sidePane(BuildContext context, Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
        ],
        if (roomId != null && roomId!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(meeting ? '会议号' : '房间号', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                      const SizedBox(height: 2),
                      Text(roomId!, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1.1)),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '复制',
                  icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 20),
                  onPressed: joining
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: roomId!));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制${meeting ? '会议号' : '房间号'}')));
                        },
                ),
              ],
            ),
          ),
        ],
        if (inviteLink != null && inviteLink!.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: joining
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: inviteLink!));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制邀请链接')));
                  },
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text('复制邀请链接'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: accent.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _deviceBtn(
              accent: accent,
              icon: micOn ? Icons.mic : Icons.mic_off,
              label: micOn ? '麦克风开' : '麦克风关',
              active: micOn,
              onTap: joining ? null : onMicToggle,
            ),
            const SizedBox(width: 20),
            _deviceBtn(
              accent: accent,
              icon: camOn ? Icons.videocam : Icons.videocam_off,
              label: camOn ? '摄像头开' : '摄像头关',
              active: camOn,
              onTap: joining ? null : onCamToggle,
            ),
          ],
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: joining ? null : onJoin,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: joining
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(joinLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        if (hint != null && hint!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _deviceBtn({required Color accent, required IconData icon, required String label, required bool active, VoidCallback? onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? accent : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(width: 56, height: 56, child: Icon(icon, color: Colors.white, size: 26)),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11)),
      ],
    );
  }
}

/// 会议/直播入口大按钮（Zoom 风格）
class CircleRoomEntryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool primary;
  final bool loading;
  final bool meeting;

  const CircleRoomEntryButton({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.primary = false,
    this.loading = false,
    this.meeting = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = circleRoomAccent(meeting);
    return Material(
      color: primary ? accent : Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: primary ? 18 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: primary ? null : Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: loading
              ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primary ? Colors.white.withValues(alpha: 0.2) : accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: TextStyle(color: Colors.white, fontSize: primary ? 18 : 16, fontWeight: FontWeight.w600)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13)),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.35)),
                  ],
                ),
        ),
      ),
    );
  }
}
