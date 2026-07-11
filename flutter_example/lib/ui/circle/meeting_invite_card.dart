import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'meeting_deep_link.dart';

class MeetingInvitePreview extends StatelessWidget {
  final MeetingInviteData invite;
  final bool compact;
  final VoidCallback? onJoin;

  const MeetingInvitePreview({
    super.key,
    required this.invite,
    this.compact = false,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppTheme.brandBlue.withValues(alpha: 0.35);
    final body = Container(
      width: compact ? double.infinity : 280,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('视频会议邀请', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              const Spacer(),
              Icon(Icons.videocam_outlined, size: 16, color: AppTheme.brandBlue),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          Text(
            invite.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compact ? 16 : 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text('会议号 ${invite.roomId}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, letterSpacing: 0.4)),
          if (invite.passcode != null && invite.passcode!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('入会密码 ${invite.passcode}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
          if (onJoin != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onJoin,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandBlue,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: const Text('加入会议'),
              ),
            ),
          ],
        ],
      ),
    );
    if (onJoin == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onJoin, borderRadius: BorderRadius.circular(14), child: body),
    );
  }
}

class MeetingInviteBubble extends StatelessWidget {
  final MeetingInviteData invite;
  final bool isMe;
  final VoidCallback? onJoin;

  const MeetingInviteBubble({
    super.key,
    required this.invite,
    this.isMe = false,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return MeetingInvitePreview(invite: invite, compact: true, onJoin: onJoin);
  }
}
