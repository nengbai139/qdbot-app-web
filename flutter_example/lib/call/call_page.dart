import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_remote_audio_platform.dart';
import 'call_service.dart';
import 'call_signal.dart';
import 'call_ui.dart';

class CallPage extends StatefulWidget {
  const CallPage({super.key});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final _coord = CallCoordinator.instance;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;

  @override
  void initState() {
    super.initState();
    _coord.addListener(_onCoord);
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    final remote = RTCVideoRenderer();
    await remote.initialize();
    remote.srcObject = _coord.remoteStream;
    RTCVideoRenderer? local;
    if (_coord.media == CallMedia.video) {
      local = RTCVideoRenderer();
      await local.initialize();
      local.srcObject = _coord.localStream;
    }
    if (mounted) {
      setState(() {
        _remoteRenderer = remote;
        _localRenderer = local;
      });
    }
  }

  void _onCoord() {
    if (!mounted) return;
    _localRenderer?.srcObject = _coord.localStream;
    _remoteRenderer?.srcObject = _coord.remoteStream;
    if (kIsWeb) _remoteRenderer?.muted = true;
    syncRemoteCallAudio(_coord.remoteStream);
    setState(() {});
  }

  @override
  void dispose() {
    _coord.removeListener(_onCoord);
    stopRemoteCallAudio();
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    super.dispose();
  }

  String get _status {
    switch (_coord.phase) {
      case CallPhase.ringing:
        return '等待对方接听…';
      case CallPhase.connecting:
        return '连接中…';
      case CallPhase.active:
        return formatCallDuration(_coord.callDuration);
      case CallPhase.ended:
        return '已结束';
      case CallPhase.idle:
        return '';
    }
  }

  bool get _showFullControls =>
      _coord.phase == CallPhase.active || _coord.phase == CallPhase.connecting;

  @override
  Widget build(BuildContext context) {
    final isVideo = _coord.media == CallMedia.video;
    final showLocal = isVideo && !_coord.cameraOff && _localRenderer != null;
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isVideo && _remoteRenderer != null && _coord.phase == CallPhase.active)
              RTCVideoView(_remoteRenderer!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            else
              _buildAudioCenter(),
            if (!kIsWeb && !isVideo && _remoteRenderer != null)
              Offstage(child: SizedBox(width: 1, height: 1, child: RTCVideoView(_remoteRenderer!))),
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    _coord.peerName,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(_status, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
                ],
              ),
            ),
            if (showLocal)
              Positioned(
                right: 16,
                top: 72,
                width: 96,
                height: 136,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      color: Colors.black45,
                    ),
                    child: RTCVideoView(_localRenderer!, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: _showFullControls ? _buildActiveControls(isVideo) : _buildRingingControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCenter() {
    final initial = _coord.peerName.isNotEmpty ? _coord.peerName[0].toUpperCase() : '?';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 52,
            backgroundColor: Colors.white24,
            child: Text(initial, style: const TextStyle(fontSize: 40, color: Colors.white)),
          ),
          if (_coord.phase == CallPhase.ringing) ...[
            const SizedBox(height: 20),
            Text(
              _coord.media == CallMedia.video ? '视频呼叫中…' : '语音呼叫中…',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 15),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRingingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 64),
      child: CallRoundButton(
        icon: Icons.call_end,
        label: '取消',
        bg: const Color(0xFFE53935),
        onPressed: () => _coord.hangup(),
        size: 64,
      ),
    );
  }

  Widget _buildActiveControls(bool isVideo) {
    final muteBg = _coord.muted ? Colors.white : const Color(0x33FFFFFF);
    final muteFg = _coord.muted ? Colors.black87 : Colors.white;
    final speakerBg = _coord.speakerOn ? Colors.white : const Color(0x33FFFFFF);
    final speakerFg = _coord.speakerOn ? Colors.black87 : Colors.white;
    final camBg = _coord.cameraOff ? Colors.white : const Color(0x33FFFFFF);
    final camFg = _coord.cameraOff ? Colors.black87 : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CallRoundButton(
            icon: _coord.muted ? Icons.mic_off : Icons.mic,
            label: _coord.muted ? '已静音' : '静音',
            bg: muteBg,
            fg: muteFg,
            onPressed: _coord.toggleMute,
          ),
          if (!kIsWeb)
            CallRoundButton(
              icon: _coord.speakerOn ? Icons.volume_up : Icons.hearing,
              label: _coord.speakerOn ? '免提' : '听筒',
              bg: speakerBg,
              fg: speakerFg,
              onPressed: () => _coord.toggleSpeaker(),
            ),
          if (isVideo) ...[
            CallRoundButton(
              icon: Icons.cameraswitch,
              label: '翻转',
              onPressed: _coord.cameraOff ? null : () => _coord.switchCamera(),
            ),
            CallRoundButton(
              icon: _coord.cameraOff ? Icons.videocam_off : Icons.videocam,
              label: _coord.cameraOff ? '已关摄像头' : '摄像头',
              bg: camBg,
              fg: camFg,
              onPressed: _coord.toggleCamera,
            ),
          ],
          CallRoundButton(
            icon: Icons.call_end,
            label: '挂断',
            bg: const Color(0xFFE53935),
            onPressed: () => _coord.hangup(),
          ),
        ],
      ),
    );
  }
}
