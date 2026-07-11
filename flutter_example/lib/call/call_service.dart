import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api/im_api.dart';
import '../api/webrtc_api.dart';
import 'call_page.dart';
import 'call_remote_audio_platform.dart';
import 'call_ring.dart';
import 'call_signal.dart';
import 'call_ui.dart';

/// ponytail: IM 信令 + 独立 webrtc-relay(TURN) + Google STUN 兜底
class CallCoordinator extends ChangeNotifier {
  CallCoordinator._();
  static final instance = CallCoordinator._();

  GlobalKey<NavigatorState>? _navKey;
  ImApi? _im;
  String _userId = '';
  String _token = '';
  List<Map<String, dynamic>>? _iceServers;
  DateTime? _iceFetchedAt;

  CallPhase _phase = CallPhase.idle;
  CallMedia? _media;
  String _peerId = '';
  String _peerName = '';
  String? _callId;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _muted = false;
  bool _speakerOn = false;
  bool _cameraOff = false;
  bool _webrtcReady = true;
  String? _lastError;
  DateTime? _activeSince;
  Timer? _durationTimer;
  String? _pendingOfferSdp;
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteDescSet = false;
  bool _incomingDialogOpen = false;
  bool _callPageOpen = false;
  String? _dedupeSignalKey;
  DateTime? _dedupeAt;
  String? _chatPeerId;
  String? _chatPeerName;

  CallPhase get phase => _phase;
  CallMedia? get media => _media;
  String get peerId => _peerId;
  String get peerName => _peerName.isNotEmpty ? _peerName : _peerId;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get muted => _muted;
  bool get speakerOn => _speakerOn;
  bool get cameraOff => _cameraOff;
  Duration get callDuration =>
      _activeSince == null ? Duration.zero : DateTime.now().difference(_activeSince!);
  bool get webrtcReady => _webrtcReady;
  String? get lastError => _lastError;
  bool get inCall => _phase != CallPhase.idle && _phase != CallPhase.ended;

  void bind({
    required GlobalKey<NavigatorState> navKey,
    required String userId,
    required String token,
    required ImApi im,
  }) {
    _navKey = navKey;
    _userId = userId;
    _token = token;
    _im = im;
  }

  /// 当前打开的私聊页，用于来电显示对方昵称
  void registerChatPeer(String peerId, String peerName) {
    _chatPeerId = peerId;
    _chatPeerName = peerName;
  }

  void unregisterChatPeer(String peerId) {
    if (_chatPeerId == peerId) {
      _chatPeerId = null;
      _chatPeerName = null;
    }
  }

  Future<List<Map<String, dynamic>>> _iceConfig() async {
    final cached = _iceServers;
    final at = _iceFetchedAt;
    if (cached != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 5)) {
      return cached;
    }
    if (_token.isNotEmpty) {
      final remote = await WebrtcApi(_token).fetchIceServers();
      if (remote != null && remote.isNotEmpty) {
        _iceServers = remote;
        _iceFetchedAt = DateTime.now();
        return remote;
      }
    }
    return fallbackIceServers();
  }

  void handleImMessage(Map<String, dynamic> msg, {String? peerHintName}) {
    final ct = (msg['contentType'] ?? msg['ext']?['contentType'] ?? '').toString();
    if (ct != 'call_signal') return;
    final raw = (msg['content'] ?? msg['ext']?['content'] ?? '').toString();
    final signal = CallSignal.parse(raw);
    if (signal == null) return;
    if (signal.fromUserId == _userId) return;
    if (_isDuplicateSignal(raw, signal)) return;
    final from = signal.fromUserId;
    final hint = peerHintName ??
        (signal.fromUserId == _chatPeerId ? _chatPeerName : null) ??
        (msg['senderName'] ?? msg['ext']?['senderName'] ?? from).toString();
    unawaited(_onSignal(signal, peerHintName: hint.isNotEmpty ? hint : null));
  }

  bool _isDuplicateSignal(String raw, CallSignal signal) {
    final key = '${signal.callId}|${signal.action.name}|${raw.hashCode}';
    final now = DateTime.now();
    if (_dedupeSignalKey == key &&
        _dedupeAt != null &&
        now.difference(_dedupeAt!) < const Duration(seconds: 3)) {
      return true;
    }
    _dedupeSignalKey = key;
    _dedupeAt = now;
    return false;
  }

  Future<void> startOutgoing({
    required String peerId,
    required String peerName,
    required CallMedia media,
  }) async {
    if (inCall) {
      _toast('当前已在通话中');
      return;
    }
    if (!await _ensureWebRtc()) return;
    _peerId = peerId;
    _peerName = peerName;
    _media = media;
    _callId = newCallId();
    _remoteDescSet = false;
    _pendingIce.clear();
    _muted = false;
    _speakerOn = false;
    _cameraOff = false;
    _phase = CallPhase.ringing;
    notifyListeners();
    _openCallPage();
    await _sendSignal(CallSignal(
      callId: _callId!,
      action: CallAction.invite,
      media: media,
      fromUserId: _userId,
      toUserId: peerId,
    ));
    try {
      await _prepareLocalMedia(media);
      await _ensurePeerConnection();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await _sendSignal(CallSignal(
        callId: _callId!,
        action: CallAction.offer,
        media: media,
        fromUserId: _userId,
        toUserId: peerId,
        sdp: offer.sdp,
      ));
      _phase = CallPhase.connecting;
      notifyListeners();
    } catch (e) {
      _lastError = '$e';
      await hangup(notifyPeer: true);
      _toast('无法发起通话: $e');
    }
  }

  Future<void> acceptIncoming({String? peerName}) async {
    if (_callId == null || _media == null || _peerId.isEmpty) return;
    if (peerName != null && peerName.isNotEmpty) _peerName = peerName;
    if (!await _ensureWebRtc()) return;
    _phase = CallPhase.connecting;
    notifyListeners();
    _openCallPage();
    await _sendSignal(CallSignal(
      callId: _callId!,
      action: CallAction.accept,
      media: _media!,
      fromUserId: _userId,
      toUserId: _peerId,
    ));
    try {
      await _prepareLocalMedia(_media!);
      await _ensurePeerConnection();
      if (_pendingOfferSdp != null) {
        await _applyOffer(_media!, _pendingOfferSdp!);
        _pendingOfferSdp = null;
      }
    } catch (e) {
      _lastError = '$e';
      await hangup(notifyPeer: true);
      _toast('无法接听: $e');
    }
  }

  Future<void> rejectIncoming() async {
    if (_callId == null || _peerId.isEmpty) return;
    await _sendSignal(CallSignal(
      callId: _callId!,
      action: CallAction.reject,
      media: _media ?? CallMedia.audio,
      fromUserId: _userId,
      toUserId: _peerId,
    ));
    _endCallLocally();
  }

  Future<void> hangup({bool notifyPeer = true}) async {
    if (notifyPeer && _callId != null && _peerId.isNotEmpty) {
      await _sendSignal(CallSignal(
        callId: _callId!,
        action: CallAction.hangup,
        media: _media ?? CallMedia.audio,
        fromUserId: _userId,
        toUserId: _peerId,
      ));
    }
    _endCallLocally();
  }

  void _dismissIncomingDialog() {
    if (!_incomingDialogOpen) return;
    final nav = _navKey?.currentState;
    if (nav != null && nav.canPop()) nav.pop();
    _incomingDialogOpen = false;
    stopIncomingRing();
  }

  void _endCallLocally({String? toast}) {
    _dismissIncomingDialog();
    if (toast != null && toast.isNotEmpty) _toast(toast);
    _popCallPageIfOpen();
    _reset();
  }

  void _popCallPageIfOpen() {
    if (!_callPageOpen) return;
    final nav = _navKey?.currentState;
    if (nav != null && nav.canPop()) nav.pop();
    _callPageOpen = false;
  }

  bool _shouldEndCallFromPeer(CallSignal signal) {
    if (signal.action != CallAction.hangup && signal.action != CallAction.reject) {
      return false;
    }
    final sameCall = _callId == null || _callId == signal.callId;
    final samePeer = _peerId.isEmpty || _peerId == signal.fromUserId;
    if (!sameCall || !samePeer) return false;
    return _incomingDialogOpen ||
        _callPageOpen ||
        inCall ||
        _phase == CallPhase.ringing ||
        _phase == CallPhase.connecting ||
        _phase == CallPhase.active;
  }

  Future<void> _onPeerEndedCall(CallSignal signal) async {
    final msg = signal.action == CallAction.reject ? '对方已拒绝' : '通话已结束';
    _endCallLocally(toast: msg);
  }

  void toggleMute() {
    _muted = !_muted;
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_muted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    if (!kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(_speakerOn);
      } catch (_) {}
    }
    notifyListeners();
  }

  void toggleCamera() {
    if (_media != CallMedia.video) return;
    _cameraOff = !_cameraOff;
    for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_cameraOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_media != CallMedia.video || _cameraOff) return;
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
      notifyListeners();
    } catch (_) {}
  }

  void _markActive() {
    if (_activeSince != null) return;
    _activeSince = DateTime.now();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _activeSince = null;
  }

  Future<void> _onSignal(CallSignal signal, {String? peerHintName}) async {
    try {
      await _handleSignal(signal, peerHintName: peerHintName);
    } catch (e) {
      _lastError = '$e';
      if (signal.action == CallAction.offer ||
          signal.action == CallAction.answer ||
          signal.action == CallAction.ice) {
        _toast('通话连接失败: $e');
        await hangup(notifyPeer: true);
      }
    }
  }

  Future<void> _handleSignal(CallSignal signal, {String? peerHintName}) async {
    if (_shouldEndCallFromPeer(signal)) {
      await _onPeerEndedCall(signal);
      return;
    }

    if (_callId != null && signal.callId != _callId) {
      if (signal.action == CallAction.hangup || signal.action == CallAction.reject) {
        if (_peerId == signal.fromUserId && inCall) {
          await _onPeerEndedCall(signal);
        }
        return;
      }
      if (signal.action == CallAction.invite) {
        await _sendSignal(CallSignal(
          callId: signal.callId,
          action: CallAction.reject,
          media: signal.media,
          fromUserId: _userId,
          toUserId: signal.fromUserId,
        ));
      }
      return;
    }

    switch (signal.action) {
      case CallAction.invite:
        if (_callId == signal.callId) {
          _media ??= signal.media;
          if (_peerId.isEmpty) _peerId = signal.fromUserId;
          if (peerHintName != null && peerHintName.isNotEmpty) _peerName = peerHintName;
          if (_phase == CallPhase.idle) {
            _phase = CallPhase.ringing;
            notifyListeners();
            _showIncomingDialog(signal);
          }
          return;
        }
        if (shouldRejectIncomingInvite(
          activeCallId: _callId,
          inviteCallId: signal.callId,
          inCall: inCall,
        )) {
          await _sendSignal(CallSignal(
            callId: signal.callId,
            action: CallAction.reject,
            media: signal.media,
            fromUserId: _userId,
            toUserId: signal.fromUserId,
          ));
          return;
        }
        _callId = signal.callId;
        _media = signal.media;
        _peerId = signal.fromUserId;
        _peerName = peerHintName ?? _peerName;
        _phase = CallPhase.ringing;
        notifyListeners();
        _showIncomingDialog(signal);
        return;
      case CallAction.accept:
        if (_phase == CallPhase.ringing || _phase == CallPhase.connecting) {
          _phase = CallPhase.connecting;
          notifyListeners();
        }
        return;
      case CallAction.reject:
      case CallAction.hangup:
        if (_shouldEndCallFromPeer(signal) || _callPageOpen || _incomingDialogOpen || inCall) {
          await _onPeerEndedCall(signal);
        }
        return;
      case CallAction.offer:
        if (!await _ensureWebRtc()) return;
        _callId ??= signal.callId;
        _media = signal.media;
        _peerId = signal.fromUserId;
        if (_phase == CallPhase.idle) {
          _phase = CallPhase.ringing;
          _pendingOfferSdp = signal.sdp;
          notifyListeners();
          _showIncomingDialog(signal);
          return;
        }
        if (_phase == CallPhase.ringing) {
          _pendingOfferSdp = signal.sdp;
          return;
        }
        await _applyOffer(signal.media, signal.sdp);
      case CallAction.answer:
        if (_pc == null || signal.sdp == null) return;
        await _pc!.setRemoteDescription(RTCSessionDescription(signal.sdp, 'answer'));
        _remoteDescSet = true;
        await _flushPendingIce();
        _phase = CallPhase.active;
        _markActive();
        notifyListeners();
      case CallAction.ice:
        if (_pc == null || signal.candidate == null) return;
        final c = signal.candidate!;
        await _addIceCandidate(RTCIceCandidate(
          c['candidate']?.toString(),
          c['sdpMid']?.toString(),
          c['sdpMLineIndex'] as int?,
        ));
    }
  }

  Future<void> _addIceCandidate(RTCIceCandidate candidate) async {
    if (_pc == null) return;
    if (!_remoteDescSet) {
      _pendingIce.add(candidate);
      return;
    }
    await _pc!.addCandidate(candidate);
  }

  Future<void> _flushPendingIce() async {
    final pc = _pc;
    if (pc == null || _pendingIce.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_pendingIce);
    _pendingIce.clear();
    for (final c in pending) {
      await pc.addCandidate(c);
    }
  }

  Future<void> _applyOffer(CallMedia media, String? sdp) async {
    if (sdp == null || sdp.isEmpty) return;
    await _prepareLocalMedia(media);
    await _ensurePeerConnection();
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    _remoteDescSet = true;
    await _flushPendingIce();
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _sendSignal(CallSignal(
      callId: _callId!,
      action: CallAction.answer,
      media: media,
      fromUserId: _userId,
      toUserId: _peerId,
      sdp: answer.sdp,
    ));
    _phase = CallPhase.active;
    _markActive();
    notifyListeners();
  }

  Future<void> _prepareLocalMedia(CallMedia media) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': media == CallMedia.video,
    });
    _localStream = stream;
    if (media == CallMedia.video && !kIsWeb) {
      _speakerOn = true;
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;
    final ice = await _iceConfig();
    final pc = await createPeerConnection({'iceServers': ice});
    _pc = pc;
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(track, _localStream!);
    }
    pc.onTrack = (event) async {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      } else {
        _remoteStream ??= await createLocalMediaStream('remote-${_callId ?? 'x'}');
        await _remoteStream!.addTrack(event.track);
      }
      for (final t in _remoteStream!.getAudioTracks()) {
        t.enabled = true;
      }
      await syncRemoteCallAudio(_remoteStream);
      notifyListeners();
    };
    pc.onIceCandidate = (c) {
      if (_callId == null || _peerId.isEmpty) return;
      unawaited(_sendSignal(CallSignal(
        callId: _callId!,
        action: CallAction.ice,
        media: _media ?? CallMedia.audio,
        fromUserId: _userId,
        toUserId: _peerId,
        candidate: c.toMap(),
      )));
    };
    pc.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateClosed ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (_phase == CallPhase.connecting || _phase == CallPhase.active) {
          _endCallLocally(toast: '通话连接中断');
        }
      }
    };
  }

  Future<bool> _ensureWebRtc() async {
    // ponytail: flutter_webrtc 的 initialize 在 Web 上未实现，浏览器直接用 RTCPeerConnection
    if (kIsWeb) {
      _webrtcReady = true;
      return true;
    }
    try {
      await WebRTC.initialize();
      _webrtcReady = true;
      return true;
    } catch (e) {
      _webrtcReady = false;
      _lastError = '$e';
      _toast('当前环境不支持音视频通话');
      return false;
    }
  }

  Future<void> _sendSignal(CallSignal signal) async {
    final im = _im;
    if (im == null) return;
    try {
      final resp = await im.send(
        toUserId: signal.toUserId,
        content: jsonEncode(signal.toJson()),
        contentType: 'call_signal',
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _lastError = '信令发送失败 ${resp.statusCode}';
      }
    } catch (e) {
      _lastError = '信令发送失败: $e';
    }
  }

  void _openCallPage() {
    final nav = _navKey?.currentState;
    if (nav == null || _callPageOpen) return;
    _callPageOpen = true;
    nav.push(MaterialPageRoute(builder: (_) => const CallPage())).whenComplete(() {
      _callPageOpen = false;
    });
  }

  void _showIncomingDialog(CallSignal signal) {
    if (_incomingDialogOpen) return;
    void present() {
      final ctx = _navKey?.currentContext;
      if (ctx == null) return;
      if (_incomingDialogOpen) return;
      _incomingDialogOpen = true;
      startIncomingRing();
      showGeneralDialog<void>(
        context: ctx,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        pageBuilder: (dialogCtx, _, __) => CallIncomingDialog(
          peerName: peerName,
          media: signal.media,
          onReject: () async {
            await rejectIncoming();
          },
          onAccept: () async {
            Navigator.pop(dialogCtx);
            _incomingDialogOpen = false;
            stopIncomingRing();
            await acceptIncoming(peerName: peerName);
          },
        ),
      ).whenComplete(() {
        stopIncomingRing();
        _incomingDialogOpen = false;
      });
    }

    final ctx = _navKey?.currentContext;
    if (ctx != null) {
      present();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => present());
  }

  void _toast(String msg) {
    final ctx = _navKey?.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _reset() {
    _phase = CallPhase.ended;
    notifyListeners();
    stopIncomingRing();
    stopRemoteCallAudio();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _remoteStream?.dispose();
    _localStream = null;
    _remoteStream = null;
    _pc?.close();
    _pc = null;
    _callId = null;
    _media = null;
    _peerId = '';
    _peerName = '';
    _muted = false;
    _speakerOn = false;
    _cameraOff = false;
    _stopDurationTimer();
    _pendingOfferSdp = null;
    _pendingIce.clear();
    _remoteDescSet = false;
    _incomingDialogOpen = false;
    _phase = CallPhase.idle;
    notifyListeners();
  }
}

enum CallPhase { idle, ringing, connecting, active, ended }
