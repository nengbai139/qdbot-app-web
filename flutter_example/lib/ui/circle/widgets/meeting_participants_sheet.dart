import 'package:flutter/material.dart';

import '../circle_models.dart';
import 'circle_ui.dart';

void showMeetingParticipantsSheet(
  BuildContext context, {
  required List<LiveParticipant> participants,
  required bool isHost,
  List<LiveParticipant> lobby = const [],
  VoidCallback? onAcceptHand,
  VoidCallback? onRejectHand,
  Future<void> Function(String userId)? onAdmitLobby,
  Future<void> Function(String userId)? onRemoveParticipant,
  bool muteAllActive = false,
  Future<void> Function({bool allowUnmute})? onMuteAll,
  Future<void> Function()? onUnmuteAll,
  LiveCohost? speakRequest,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: kMeetingSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      final pendingSpeak = speakRequest != null && speakRequest.isPending ? speakRequest : null;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_outlined, color: kMeetingAccent, size: 20),
                  const SizedBox(width: 8),
                  Text('参会成员 (${participants.length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              if (isHost && (onMuteAll != null || onUnmuteAll != null)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: muteAllActive
                            ? null
                            : () async {
                                await onMuteAll?.call(allowUnmute: false);
                              },
                        icon: const Icon(Icons.mic_off, size: 18),
                        label: const Text('全员静音'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: kMeetingAccent),
                        onPressed: muteAllActive
                            ? () async {
                                await onUnmuteAll?.call();
                              }
                            : null,
                        icon: const Icon(Icons.mic, size: 18),
                        label: const Text('允许发言'),
                      ),
                    ),
                  ],
                ),
              ],
              if (isHost && lobby.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('等候室 (${lobby.length})', style: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...lobby.map((p) => _LobbyTile(
                      participant: p,
                      onAdmit: onAdmitLobby == null
                          ? null
                          : () async {
                              await onAdmitLobby(p.userId);
                            },
                    )),
                const SizedBox(height: 8),
              ],
              if (isHost && pendingSpeak != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kMeetingAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kMeetingAccent.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${pendingSpeak.userName} 申请发言', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onRejectHand == null
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      onRejectHand();
                                    },
                              child: const Text('拒绝'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: kMeetingAccent),
                              onPressed: onAcceptHand == null
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      onAcceptHand();
                                    },
                              child: const Text('同意发言'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: participants.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('暂无在线成员', style: TextStyle(color: Colors.white54))),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: participants.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                        itemBuilder: (_, i) {
                          final p = participants[i];
                          final speakPending = pendingSpeak != null && p.userId == pendingSpeak.userId;
                          final speakActive = speakRequest != null && speakRequest.isActive && p.userId == speakRequest.userId;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: kMeetingAccent.withValues(alpha: 0.25),
                              child: Text(
                                p.userName.isNotEmpty ? p.userName[0] : '?',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ),
                            title: Text(p.userName, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: p.isHost
                                ? const Text('主持人', style: TextStyle(color: kMeetingAccent, fontSize: 12))
                                : speakActive || p.speaking
                                    ? const Text('发言中', style: TextStyle(color: Color(0xFF34D399), fontSize: 12))
                                    : speakPending || p.handRaised
                                        ? const Text('举手待批', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 12))
                                        : null,
                            trailing: _ParticipantTrailing(
                              participant: p,
                              isHost: isHost,
                              speakPending: speakPending,
                              speakActive: speakActive,
                              onRemoveParticipant: onRemoveParticipant,
                              onAcceptHand: onAcceptHand,
                              onRejectHand: onRejectHand,
                              onCloseSheet: () => Navigator.pop(ctx),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ParticipantTrailing extends StatelessWidget {
  const _ParticipantTrailing({
    required this.participant,
    required this.isHost,
    required this.speakPending,
    required this.speakActive,
    this.onRemoveParticipant,
    this.onAcceptHand,
    this.onRejectHand,
    this.onCloseSheet,
  });

  final LiveParticipant participant;
  final bool isHost;
  final bool speakPending;
  final bool speakActive;
  final Future<void> Function(String userId)? onRemoveParticipant;
  final VoidCallback? onAcceptHand;
  final VoidCallback? onRejectHand;
  final VoidCallback? onCloseSheet;

  @override
  Widget build(BuildContext context) {
    if (participant.isHost) {
      return const Icon(Icons.star, color: kMeetingAccent, size: 18);
    }
    if (isHost && speakPending && onAcceptHand != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () {
              onCloseSheet?.call();
              onRejectHand?.call();
            },
            child: const Text('拒绝', style: TextStyle(fontSize: 12)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kMeetingAccent,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: () {
              onCloseSheet?.call();
              onAcceptHand?.call();
            },
            child: const Text('同意', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }
    if (isHost && onRemoveParticipant != null) {
      return IconButton(
        icon: const Icon(Icons.person_remove_outlined, color: Colors.redAccent, size: 20),
        tooltip: '移出会议',
        onPressed: () async {
          await onRemoveParticipant!(participant.userId);
        },
      );
    }
    if (speakActive || participant.speaking) {
      return const Icon(Icons.mic, color: Color(0xFF34D399), size: 18);
    }
    if (speakPending || participant.handRaised) {
      return const Icon(Icons.front_hand, color: Color(0xFFFBBF24), size: 18);
    }
    return const Icon(Icons.person_outline, color: Colors.white38, size: 18);
  }
}

class _LobbyTile extends StatelessWidget {
  const _LobbyTile({required this.participant, this.onAdmit});

  final LiveParticipant participant;
  final VoidCallback? onAdmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: kMeetingAccent.withValues(alpha: 0.25),
            child: Text(
              participant.userName.isNotEmpty ? participant.userName[0] : '?',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(participant.userName, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          if (onAdmit != null)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: kMeetingAccent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: onAdmit,
              child: const Text('准入', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
