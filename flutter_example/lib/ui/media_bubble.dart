import 'package:flutter/material.dart';

import '../util/audio_playback.dart';
import '../util/media_url.dart';
import '../util/voice_transcribe.dart';
import '../util/voice_waveform.dart';
import 'app_theme.dart';
import 'media_message.dart';

export 'video_message_bubble.dart';

class VoiceMessageBubble extends StatefulWidget {
  final MediaAttachment media;
  final bool isMe;
  final String token;

  const VoiceMessageBubble({
    super.key,
    required this.media,
    required this.isMe,
    required this.token,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  String? _transcript;
  bool _transcribing = false;

  @override
  void initState() {
    super.initState();
    AudioPlaybackHub.addListener(_onPlayback);
    _transcript = VoiceTranscriptCache.get(widget.media.url);
  }

  @override
  void dispose() {
    AudioPlaybackHub.removeListener(_onPlayback);
    super.dispose();
  }

  void _onPlayback() {
    if (mounted) setState(() {});
  }

  void _reloadTranscript() {
    setState(() => _transcript = VoiceTranscriptCache.get(widget.media.url));
  }

  bool get _playing => AudioPlaybackHub.playingUrl == publicMediaUrl(widget.media.url);

  Future<void> _play() async {
    if (widget.media.url.isEmpty) return;
    try {
      await AudioPlaybackHub.toggle(widget.media.url, filename: widget.media.name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法播放语音: $e')));
    }
  }

  Future<void> _transcribe() async {
    if (_transcribing || widget.media.url.isEmpty) return;
    setState(() => _transcribing = true);
    try {
      final text = await transcribeVoiceUrl(widget.token, widget.media.url);
      if (!mounted) return;
      setState(() {
        _transcript = text;
        _transcribing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _transcribing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dur = formatDurationMs(widget.media.durationMs);
    final bubbleColor = widget.isMe ? AppTheme.brandBlue : AppTheme.bubbleOtherFor(Theme.of(context).brightness);
    final fg = widget.isMe ? Colors.white : Colors.black87;
    final waveColor = widget.isMe ? Colors.white.withValues(alpha: 0.92) : AppTheme.brandBlue.withValues(alpha: 0.85);
    final waveWidth = voiceWaveAreaWidth(widget.media.durationMs);
    final waveform = widget.media.waveform?.isNotEmpty == true
        ? widget.media.waveform!
        : fallbackWaveform(durationMs: widget.media.durationMs, seed: widget.media.url);

    return Column(
      crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.media.url.isEmpty ? null : _play,
            onLongPress: widget.media.url.isEmpty
                ? null
                : () {
                    if (_transcript != null && _transcript!.isNotEmpty) return;
                    _transcribe();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _playing ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                    color: widget.isMe ? Colors.white : AppTheme.brandBlue,
                    size: 22,
                  ),
                  const SizedBox(width: 6),
                  VoiceWaveBars(levels: waveform, color: waveColor, width: waveWidth),
                  const SizedBox(width: 8),
                  Text(dur, style: TextStyle(color: fg, fontSize: 13)),
                  if (_transcribing) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg.withValues(alpha: 0.85)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_transcript != null && _transcript!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Material(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onLongPress: () => showVoiceActionSheet(
                    context,
                    url: widget.media.url,
                    name: widget.media.name ?? 'voice.webm',
                    token: widget.token,
                    onTranscriptReady: _reloadTranscript,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(_transcript!, style: const TextStyle(fontSize: 14, height: 1.4)),
                  ),
                ),
              ),
            ),
          )
        else if (!_transcribing)
          GestureDetector(
            onTap: () => showVoiceActionSheet(
              context,
              url: widget.media.url,
              name: widget.media.name ?? 'voice.webm',
              token: widget.token,
              onTranscriptReady: _reloadTranscript,
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '长按转文字 · 更多',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
          ),
      ],
    );
  }
}
