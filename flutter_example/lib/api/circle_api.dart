import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_client.dart';
import '../config.dart';
import '../ui/circle/circle_models.dart';
import '../util/file_mime.dart';
import '../util/media_url.dart';
import '../util/video_poster.dart';

class CircleApi {
  final ApiClient _c;
  CircleApi(String token) : _c = ApiClient(token: token);

  /// 圈子媒体上传 init（分配 circle/{userId}/{kind}/… objectKey）
  Future<CircleUploadInit> mediaUploadInit({
    required String kind,
    required String filename,
    int sizeBytes = 0,
  }) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/media/upload/init', body: {
      'kind': kind,
      'filename': filename,
      'sizeBytes': sizeBytes,
    });
    _ensureOk(resp);
    return CircleUploadInit.fromJson(_data(resp));
  }

  /// 经 init 分配 objectKey 后直传 qdbot_images
  Future<String> uploadMediaBytes(
    List<int> bytes, {
    required String userId,
    required String kind,
    required String filename,
    int maxBytes = 20 * 1024 * 1024,
  }) async {
    if (bytes.length > maxBytes) {
      throw Exception('文件不能超过 ${maxBytes ~/ (1024 * 1024)}MB');
    }
    var name = filename.trim();
    if (name.isEmpty) name = 'upload.bin';
    final init = await mediaUploadInit(kind: kind, filename: name, sizeBytes: bytes.length);
    final req = http.MultipartRequest('POST', Uri.parse(init.uploadUrl));
    if (_c.token != null && _c.token!.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer ${_c.token}';
    }
    req.fields['userId'] = userId;
    req.fields['objectKey'] = init.objectKey;
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: name,
      contentType: MediaType.parse(mimeForFilename(name)),
    ));
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) throw Exception('上传失败: ${resp.body}');
    final url = (jsonDecode(resp.body) as Map<String, dynamic>)['url']?.toString().trim() ?? '';
    if (url.isEmpty) return publicMediaUrl(init.downloadUrl);
    return publicMediaUrl(url);
  }

  Future<({String url, String? poster})> uploadVideoWithPoster(
    List<int> bytes, {
    required String userId,
    String? filename,
  }) async {
    final results = await Future.wait<Object?>([
      uploadMediaBytes(bytes, userId: userId, kind: 'video', filename: filename ?? 'video.mp4'),
      captureVideoPosterJpeg(bytes, filename: filename),
    ]);
    final url = results[0]! as String;
    final posterBytes = results[1] as List<int>?;
    String? poster;
    if (posterBytes != null && posterBytes.isNotEmpty) {
      try {
        poster = await uploadMediaBytes(posterBytes, userId: userId, kind: 'poster', filename: 'poster.jpg', maxBytes: 5 * 1024 * 1024);
      } catch (_) {}
    }
    return (url: url, poster: poster);
  }

  Future<CircleFeedPage> feedMoments({String? cursor, int limit = 20}) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/feed/moments', query: {
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'limit': '$limit',
    });
    _ensureOk(resp);
    final data = _data(resp);
    final items = (data['items'] as List? ?? [])
        .map((e) => CirclePost.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return CircleFeedPage(
      items: items,
      cursor: (data['cursor'] ?? '').toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Future<CirclePost> createMoment({
    required String text,
    List<String> images = const [],
    String visibility = 'friends',
  }) async {
    return createPost(text: text, images: images, visibility: visibility, circleType: 'moment');
  }

  Future<CircleFeedPage> feedVideo({String? cursor, int limit = 20}) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/feed/video', query: {
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'limit': '$limit',
    });
    _ensureOk(resp);
    return _parseFeed(resp);
  }

  Future<CirclePost> createVideo({
    required String videoUrl,
    String posterUrl = '',
    String text = '',
    String visibility = 'public',
  }) async {
    return createPost(
      text: text,
      videoUrl: videoUrl,
      posterUrl: posterUrl,
      visibility: visibility,
      circleType: 'video',
    );
  }

  Future<CirclePost> createPost({
    String text = '',
    List<String> images = const [],
    String videoUrl = '',
    String posterUrl = '',
    String visibility = 'friends',
    required String circleType,
  }) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/posts', body: {
      'text': text,
      if (images.isNotEmpty) 'images': images,
      if (videoUrl.isNotEmpty) 'videoUrl': videoUrl,
      if (posterUrl.isNotEmpty) 'posterUrl': posterUrl,
      'visibility': visibility,
      'circleType': circleType,
    });
    _ensureOk(resp);
    return CirclePost.fromJson(_data(resp));
  }

  CircleFeedPage _parseFeed(http.Response resp) {
    final data = _data(resp);
    final items = (data['items'] as List? ?? [])
        .map((e) => CirclePost.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return CircleFeedPage(
      items: items,
      cursor: (data['cursor'] ?? '').toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Future<({bool liked, int likeCount})> toggleLike(String postId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/posts/$postId/like');
    _ensureOk(resp);
    final data = _data(resp);
    return (liked: data['liked'] == true, likeCount: (data['likeCount'] as num?)?.toInt() ?? 0);
  }

  Future<List<CircleComment>> listComments(String postId) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/posts/$postId/comments');
    _ensureOk(resp);
    final data = _data(resp);
    return (data['items'] as List? ?? [])
        .map((e) => CircleComment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<CircleComment> addComment(String postId, String text) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/posts/$postId/comments', body: {'text': text});
    _ensureOk(resp);
    return CircleComment.fromJson(_data(resp));
  }

  Future<void> deletePost(String postId) async {
    final resp = await _c.delete('${AppConfig.circleApiPath}/posts/$postId');
    _ensureOk(resp);
  }

  Future<void> follow(String userId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/follow/$userId');
    _ensureOk(resp);
  }

  Future<void> unfollow(String userId) async {
    final resp = await _c.delete('${AppConfig.circleApiPath}/follow/$userId');
    _ensureOk(resp);
  }

  Future<bool> followStatus(String userId) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/follow/$userId');
    _ensureOk(resp);
    return _data(resp)['following'] == true;
  }

  Future<UserCircleFeed> userPosts(String userId, {String? cursor, int limit = 20}) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/users/$userId/posts', query: {
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'limit': '$limit',
    });
    _ensureOk(resp);
    final data = _data(resp);
    final items = (data['items'] as List? ?? [])
        .map((e) => CirclePost.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return UserCircleFeed(
      items: items,
      cursor: (data['cursor'] ?? '').toString(),
      hasMore: data['hasMore'] == true,
      following: data['following'] == true,
      isSelf: data['isSelf'] == true,
    );
  }

  Future<LiveRoom?> myLiveRoom() async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/mine');
    _ensureOk(resp);
    final room = _data(resp)['room'];
    if (room == null) return null;
    return LiveRoom.fromJson(Map<String, dynamic>.from(room as Map));
  }

  Future<List<LiveRoom>> listLiveRooms({String status = 'live', int limit = 20}) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms', query: {
      if (status.isNotEmpty) 'status': status,
      'limit': '$limit',
    });
    _ensureOk(resp);
    final data = _data(resp);
    return (data['items'] as List? ?? [])
        .map((e) => LiveRoom.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<LiveRoom> createLiveRoom(String title, {String? coverUrl, String roomType = 'live', String? joinPassword}) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms', body: {
      'title': title,
      'roomType': roomType,
      if (joinPassword != null && joinPassword.isNotEmpty) 'joinPassword': joinPassword,
      if (coverUrl != null && coverUrl.isNotEmpty) 'coverUrl': coverUrl,
    });
    _ensureOk(resp);
    return LiveRoom.fromJson(_data(resp));
  }

  Future<LiveRoom> updateLiveRoomCover(String roomId, String coverUrl) async {
    final resp = await _c.patch('${AppConfig.circleApiPath}/live/rooms/$roomId/cover', body: {'coverUrl': coverUrl});
    _ensureOk(resp);
    return LiveRoom.fromJson(_data(resp));
  }

  Future<({String url, String token, String roomName, bool canPublish})> fetchLiveKitToken(String roomId, {String? livekitRoom}) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/livekit-token', body: {
      if (livekitRoom != null && livekitRoom.isNotEmpty) 'livekitRoom': livekitRoom,
    });
    _ensureOk(resp);
    final data = _data(resp);
    return (
      url: (data['url'] ?? '').toString(),
      token: (data['token'] ?? '').toString(),
      roomName: (data['roomName'] ?? '').toString(),
      canPublish: data['canPublish'] == true,
    );
  }

  Future<void> joinCheckLiveRoom(String roomId, {required String passcode}) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/join-check', body: {'passcode': passcode});
    _ensureOk(resp);
  }

  Future<LiveRoom> getLiveRoom(String roomId) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId');
    _ensureOk(resp);
    return LiveRoom.fromJson(_data(resp));
  }

  Future<bool> liveStreamActive(String roomId) async {
    final s = await liveStreamStatus(roomId);
    return s.pushActive;
  }

  Future<({bool pushActive, String playUrl})> liveStreamStatus(String roomId) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId/stream-status');
    _ensureOk(resp);
    final data = _data(resp);
    return (
      pushActive: data['pushActive'] == true,
      playUrl: (data['playUrl'] ?? '').toString(),
    );
  }

  Future<LiveRoom> startLiveRoom(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/start');
    _ensureOk(resp);
    return LiveRoom.fromJson(_data(resp));
  }

  Future<LiveRoom> setMeetingRecording(String roomId, bool enabled) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/recording', body: {'enabled': enabled});
    _ensureOk(resp);
    return LiveRoom.fromJson(_data(resp));
  }

  Future<({LiveRoom room, String? replayPostId})> stopLiveRoom(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/stop');
    _ensureOk(resp);
    final data = _data(resp);
    final replay = (data['replayPostId'] ?? '').toString();
    return (
      room: LiveRoom.fromJson(data),
      replayPostId: replay.isEmpty ? null : replay,
    );
  }

  Future<List<ReplayViewer>> listReplayViewers(String roomId) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId/replay-viewers');
    _ensureOk(resp);
    return ( _data(resp)['items'] as List? ?? [])
        .map((e) => ReplayViewer.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> addReplayViewer(String roomId, {required String userId, String? userName}) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/replay-viewers', body: {
      'userId': userId,
      if (userName != null && userName.isNotEmpty) 'userName': userName,
    });
    _ensureOk(resp);
  }

  Future<void> removeReplayViewer(String roomId, String userId) async {
    final resp = await _c.delete('${AppConfig.circleApiPath}/live/rooms/$roomId/replay-viewers/$userId');
    _ensureOk(resp);
  }

  Future<List<LiveMessage>> listLiveMessages(String roomId, {String since = ''}) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId/messages', query: {
      if (since.isNotEmpty) 'since': since,
    });
    _ensureOk(resp);
    final data = _data(resp);
    return (data['items'] as List? ?? [])
        .map((e) => LiveMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<LiveMessage> sendLiveMessage(String roomId, String text) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/messages', body: {'text': text});
    _ensureOk(resp);
    return LiveMessage.fromJson(_data(resp));
  }

  Future<LiveGiftOrderResult> createLiveGiftOrder(String roomId, String giftId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/gifts/order', body: {'giftId': giftId});
    _ensureOk(resp);
    return LiveGiftOrderResult.fromJson(_data(resp));
  }

  Future<LiveGiftEvent> sendLiveGift(String roomId, String giftId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/gifts/send', body: {'giftId': giftId});
    _ensureOk(resp);
    final data = _data(resp);
    final gift = data['gift'] ?? data;
    return LiveGiftEvent.fromJson(Map<String, dynamic>.from(gift as Map));
  }

  Future<double> getQdBalance() async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/wallet/qd');
    _ensureOk(resp);
    return (_data(resp)['balance'] as num?)?.toDouble() ?? 0;
  }

  Future<({List<LiveBackdropItem> items, double balance})> listLiveBackdropItems() async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/backdrops');
    _ensureOk(resp);
    final data = _data(resp);
    final items = (data['items'] as List? ?? [])
        .map((e) => LiveBackdropItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return (items: items, balance: (data['balance'] as num?)?.toDouble() ?? 0);
  }

  Future<LiveBackdropItem> purchaseLiveBackdropItem(String backdropId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/backdrops/$backdropId/purchase');
    _ensureOk(resp);
    return LiveBackdropItem.fromJson(_data(resp));
  }

  Future<LiveRoom> applyLiveRoomBackdrop(String roomId, String backdropId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/backdrop', body: {'backdropId': backdropId});
    _ensureOk(resp);
    return LiveRoom.fromJson(_data(resp));
  }

  Future<LivePk?> getLivePk(String roomId) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId/pk');
    _ensureOk(resp);
    final p = _data(resp)['pk'];
    if (p == null) return null;
    return LivePk.fromJson(Map<String, dynamic>.from(p as Map));
  }

  Future<LivePk> inviteLivePk(String roomId, String targetRoomId, {int minutes = 5}) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/pk/invite', body: {
      'targetRoomId': targetRoomId,
      'minutes': minutes,
    });
    _ensureOk(resp);
    return LivePk.fromJson(Map<String, dynamic>.from((_data(resp)['pk'] as Map?) ?? {}));
  }

  Future<LivePk> acceptLivePk(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/pk/accept');
    _ensureOk(resp);
    return LivePk.fromJson(Map<String, dynamic>.from((_data(resp)['pk'] as Map?) ?? {}));
  }

  Future<void> rejectLivePk(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/pk/reject');
    _ensureOk(resp);
  }

  Future<void> endLivePk(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/pk/end');
    _ensureOk(resp);
  }

  Future<LiveGiftEvent> confirmLiveGift(String roomId, {required String giftOrderId, String? payOrderId}) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/gifts/confirm', body: {
      'giftOrderId': giftOrderId,
      if (payOrderId != null) 'payOrderId': payOrderId,
    });
    _ensureOk(resp);
    return LiveGiftEvent.fromJson(_data(resp));
  }

  Future<List<LiveGiftRank>> listLiveGiftRank(String roomId, {int limit = 10}) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId/gifts/rank', query: {'limit': '$limit'});
    _ensureOk(resp);
    final data = _data(resp);
    return (data['items'] as List? ?? [])
        .map((e) => LiveGiftRank.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<LiveGiftEvent>> listRoomGifts(String roomId, {int limit = 10}) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId/gifts', query: {'limit': '$limit'});
    _ensureOk(resp);
    final data = _data(resp);
    return (data['items'] as List? ?? [])
        .map((e) => LiveGiftEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<LiveGiftEarnings> myLiveGiftEarnings({String? roomId}) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/gifts/earnings/mine', query: {
      if (roomId != null && roomId.isNotEmpty) 'roomId': roomId,
    });
    _ensureOk(resp);
    return LiveGiftEarnings.fromJson(_data(resp));
  }

  Future<LiveEarningsDetail> myLiveEarningsDetail({int limit = 20}) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/gifts/earnings/detail', query: {'limit': '$limit'});
    _ensureOk(resp);
    return LiveEarningsDetail.fromJson(_data(resp));
  }

  Future<LiveRedPacket> createLiveRedPacket(String roomId, {required double totalAmount, required int totalCount, String title = ''}) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/redpackets', body: {
      'totalAmount': totalAmount,
      'totalCount': totalCount,
      if (title.isNotEmpty) 'title': title,
    });
    _ensureOk(resp);
    return LiveRedPacket.fromJson(_data(resp));
  }

  Future<LiveRedPacket?> activeLiveRedPacket(String roomId) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId/redpackets/active');
    _ensureOk(resp);
    final data = _data(resp);
    final p = data['packet'];
    if (p == null) return null;
    return LiveRedPacket.fromJson(Map<String, dynamic>.from(p as Map));
  }

  Future<LiveRedPacketGrab> grabLiveRedPacket(String roomId, String packetId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/redpackets/$packetId/grab');
    _ensureOk(resp);
    return LiveRedPacketGrab.fromJson(_data(resp));
  }

  Future<LiveCohost> getLiveCohost(String roomId) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId/cohost');
    _ensureOk(resp);
    final data = _data(resp);
    return LiveCohost.fromJson(Map<String, dynamic>.from((data['cohost'] as Map?) ?? {}));
  }

  Future<String> getLiveCohostWhip(String roomId) async {
    final resp = await _c.get('${AppConfig.circleApiPath}/live/rooms/$roomId/cohost/whip');
    _ensureOk(resp);
    return (_data(resp)['whipPublishUrl'] ?? '').toString();
  }

  Future<LiveCohost> requestLiveCohost(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/cohost/request');
    _ensureOk(resp);
    return LiveCohost.fromJson(Map<String, dynamic>.from((_data(resp)['cohost'] as Map?) ?? {}));
  }

  Future<LiveCohost> acceptLiveCohost(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/cohost/accept');
    _ensureOk(resp);
    return LiveCohost.fromJson(Map<String, dynamic>.from((_data(resp)['cohost'] as Map?) ?? {}));
  }

  Future<LiveCohost> rejectLiveCohost(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/cohost/reject');
    _ensureOk(resp);
    return LiveCohost.fromJson(Map<String, dynamic>.from((_data(resp)['cohost'] as Map?) ?? {}));
  }

  Future<LiveCohost> endLiveCohost(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/cohost/end');
    _ensureOk(resp);
    return LiveCohost.fromJson(Map<String, dynamic>.from((_data(resp)['cohost'] as Map?) ?? {}));
  }

  Future<void> admitLobbyParticipant(String roomId, String userId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/lobby/$userId/admit');
    _ensureOk(resp);
  }

  Future<void> removeLiveParticipant(String roomId, String userId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/participants/$userId/remove');
    _ensureOk(resp);
  }

  Future<void> muteAllMeeting(String roomId, {bool allowUnmute = false}) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/mute-all', body: {
      'allowUnmute': allowUnmute,
    });
    _ensureOk(resp);
  }

  Future<Map<String, String>> startMeetingBreakout(
    String roomId, {
    int count = 3,
    Map<String, int>? assignments,
  }) async {
    final body = <String, dynamic>{'count': count};
    if (assignments != null && assignments.isNotEmpty) {
      body['assignments'] = assignments;
    }
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/breakout/start', body: body);
    _ensureOk(resp);
    final raw = _data(resp)['assignments'];
    final out = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) => out[k.toString()] = v.toString());
    }
    return out;
  }

  Future<String> assignMeetingBreakout(String roomId, {required String userId, required int group}) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/breakout/assign', body: {
      'userId': userId,
      'group': group,
    });
    _ensureOk(resp);
    return (_data(resp)['livekitRoom'] ?? '').toString();
  }

  Future<void> endMeetingBreakout(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/breakout/end');
    _ensureOk(resp);
  }

  Future<void> unmuteAllMeeting(String roomId) async {
    final resp = await _c.post('${AppConfig.circleApiPath}/live/rooms/$roomId/unmute-all');
    _ensureOk(resp);
  }

  Map<String, dynamic> _data(http.Response resp) {
    final j = jsonDecode(resp.body);
    if (j is Map && j['data'] is Map) return Map<String, dynamic>.from(j['data'] as Map);
    if (j is Map) return Map<String, dynamic>.from(j);
    return {};
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    var msg = 'HTTP ${resp.statusCode}';
    try {
      final j = jsonDecode(resp.body);
      if (j is Map && j['message'] != null) msg = j['message'].toString();
    } catch (_) {}
    throw Exception(msg);
  }
}

class CircleUploadInit {
  CircleUploadInit({
    required this.mediaId,
    required this.objectKey,
    required this.uploadUrl,
    required this.downloadUrl,
    this.kind = '',
  });

  final String mediaId;
  final String objectKey;
  final String uploadUrl;
  final String downloadUrl;
  final String kind;

  factory CircleUploadInit.fromJson(Map<String, dynamic> j) => CircleUploadInit(
        mediaId: j['mediaId']?.toString() ?? '',
        objectKey: j['objectKey']?.toString() ?? '',
        uploadUrl: j['uploadUrl']?.toString() ?? '',
        downloadUrl: j['downloadUrl']?.toString() ?? '',
        kind: j['kind']?.toString() ?? '',
      );
}
