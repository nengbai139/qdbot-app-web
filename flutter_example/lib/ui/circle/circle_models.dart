import 'package:flutter/material.dart';

import '../../util/media_url.dart';

class CirclePost {
  final String postId;
  final String authorId;
  final String authorName;
  final String authorCode;
  final String authorEmail;
  final String authorAvatar;
  final String text;
  final List<String> images;
  final int likeCount;
  final int commentCount;
  final bool liked;
  final String visibility;
  final String createdAt;
  final String videoUrl;
  final String posterUrl;
  final String circleType;

  const CirclePost({
    required this.postId,
    required this.authorId,
    required this.authorName,
    this.authorCode = '',
    this.authorEmail = '',
    required this.authorAvatar,
    required this.text,
    this.images = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.liked = false,
    this.visibility = 'friends',
    this.createdAt = '',
    this.videoUrl = '',
    this.posterUrl = '',
    this.circleType = 'moment',
  });

  factory CirclePost.fromJson(Map<String, dynamic> j) => CirclePost(
        postId: (j['postId'] ?? '').toString(),
        authorId: (j['authorId'] ?? '').toString(),
        authorName: (j['authorName'] ?? '').toString(),
        authorCode: (j['authorCode'] ?? '').toString(),
        authorEmail: (j['authorEmail'] ?? '').toString(),
        authorAvatar: publicMediaUrl((j['authorAvatar'] ?? '').toString()),
        text: (j['text'] ?? '').toString(),
        images: (j['images'] as List? ?? []).map((e) => publicMediaUrl(e.toString())).toList(),
        likeCount: (j['likeCount'] as num?)?.toInt() ?? 0,
        commentCount: (j['commentCount'] as num?)?.toInt() ?? 0,
        liked: j['liked'] == true,
        visibility: (j['visibility'] ?? 'friends').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
        videoUrl: publicMediaUrl((j['videoUrl'] ?? '').toString()),
        posterUrl: publicMediaUrl((j['posterUrl'] ?? '').toString()),
        circleType: (j['circleType'] ?? 'moment').toString(),
      );

  /// 昵称 → 展示码 → 邮箱 → user_id（与 IM / 圈子后端一致）
  String get authorDisplay {
    if (authorName.isNotEmpty && authorName != authorId) return authorName;
    if (authorCode.isNotEmpty && authorCode != authorId) return authorCode;
    if (authorEmail.isNotEmpty) return authorEmail;
    return authorId;
  }

  bool isOwnedBy(String viewerId, {String? altViewerId}) {
    final aid = authorId.trim();
    if (aid.isEmpty) return false;
    for (final raw in [viewerId, altViewerId]) {
      final id = raw?.trim() ?? '';
      if (id.isNotEmpty && id == aid) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'postId': postId,
        'authorId': authorId,
        'authorName': authorName,
        'authorCode': authorCode,
        'authorEmail': authorEmail,
        'authorAvatar': authorAvatar,
        'text': text,
        'images': images,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'liked': liked,
        'visibility': visibility,
        'createdAt': createdAt,
        'videoUrl': videoUrl,
        'posterUrl': posterUrl,
        'circleType': circleType,
      };

  CirclePost copyWith({
    String? postId,
    String? authorId,
    String? authorName,
    String? authorCode,
    String? authorEmail,
    String? authorAvatar,
    String? text,
    List<String>? images,
    int? likeCount,
    int? commentCount,
    bool? liked,
    String? visibility,
    String? createdAt,
    String? videoUrl,
    String? posterUrl,
    String? circleType,
  }) =>
      CirclePost(
        postId: postId ?? this.postId,
        authorId: authorId ?? this.authorId,
        authorName: authorName ?? this.authorName,
        authorCode: authorCode ?? this.authorCode,
        authorEmail: authorEmail ?? this.authorEmail,
        authorAvatar: authorAvatar ?? this.authorAvatar,
        text: text ?? this.text,
        images: images ?? this.images,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        liked: liked ?? this.liked,
        visibility: visibility ?? this.visibility,
        createdAt: createdAt ?? this.createdAt,
        videoUrl: videoUrl ?? this.videoUrl,
        posterUrl: posterUrl ?? this.posterUrl,
        circleType: circleType ?? this.circleType,
      );
}

class CircleComment {
  final String commentId;
  final String authorId;
  final String authorName;
  final String text;
  final String createdAt;

  const CircleComment({
    required this.commentId,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.createdAt = '',
  });

  factory CircleComment.fromJson(Map<String, dynamic> j) => CircleComment(
        commentId: (j['commentId'] ?? '').toString(),
        authorId: (j['authorId'] ?? '').toString(),
        authorName: _authorDisplayFromJson(j),
        text: (j['text'] ?? '').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
      );
}

class CircleFeedPage {
  final List<CirclePost> items;
  final String cursor;
  final bool hasMore;

  const CircleFeedPage({required this.items, this.cursor = '', this.hasMore = false});
}

class UserCircleFeed {
  final List<CirclePost> items;
  final String cursor;
  final bool hasMore;
  final bool following;
  final bool isSelf;

  const UserCircleFeed({
    required this.items,
    this.cursor = '',
    this.hasMore = false,
    this.following = false,
    this.isSelf = false,
  });
}

String _authorDisplayFromJson(Map<String, dynamic> j) {
  final id = (j['authorId'] ?? '').toString();
  final name = (j['authorName'] ?? '').toString();
  final code = (j['authorCode'] ?? '').toString();
  final email = (j['authorEmail'] ?? '').toString();
  if (name.isNotEmpty && name != id) return name;
  if (code.isNotEmpty && code != id) return code;
  if (email.isNotEmpty) return email;
  return id;
}

enum CircleKind { moments, video, live, shop, game }

extension CircleKindX on CircleKind {
  String get label => switch (this) {
        CircleKind.moments => '朋友圈',
        CircleKind.video => '视频圈',
        CircleKind.live => '直播圈',
        CircleKind.shop => '购物圈',
        CircleKind.game => '游戏圈',
      };

  IconData get icon => switch (this) {
        CircleKind.moments => Icons.photo_library_outlined,
        CircleKind.video => Icons.ondemand_video_outlined,
        CircleKind.live => Icons.sensors_outlined,
        CircleKind.shop => Icons.shopping_bag_outlined,
        CircleKind.game => Icons.sports_esports_outlined,
      };

  bool get available => this == CircleKind.moments || this == CircleKind.video || this == CircleKind.live;
}

class LiveRoom {
  final String roomId;
  final String hostId;
  final String hostName;
  final String hostAvatar;
  final String coverUrl;
  final String title;
  final String roomType;

  /// 圈子房间类型：`live` = 直播圈，`meeting` = 视频会议（与 [mediaMode] 推流技术无关）
  static const roomTypeLive = 'live';
  static const roomTypeMeeting = 'meeting';
  final String mediaMode;
  final String livekitUrl;
  final String status;
  final String pushUrl;
  final String playUrl;
  final String whipPublishUrl;
  final String createdAt;
  final String? startedAt;
  final bool hasJoinPassword;
  final String joinPassword;
  final bool recording;

  const LiveRoom({
    required this.roomId,
    required this.hostId,
    required this.hostName,
    this.hostAvatar = '',
    this.coverUrl = '',
    required this.title,
    this.roomType = 'live',
    this.mediaMode = 'hls',
    this.livekitUrl = '',
    required this.status,
    required this.pushUrl,
    required this.playUrl,
    this.whipPublishUrl = '',
    this.createdAt = '',
    this.startedAt,
    this.hasJoinPassword = false,
    this.joinPassword = '',
    this.recording = false,
  });

  /// 视频会议是否可入会（统一 LiveKit SFU）
  bool get meetingJoinable => isMeeting && isSfu;

  bool get isSfu => mediaMode == 'sfu' && livekitUrl.isNotEmpty;

  /// 视频会议（直播圈入口创建的房间为 false）
  bool get isMeeting => roomType == roomTypeMeeting;

  /// 直播圈互动直播
  bool get isLiveBroadcast => roomType == roomTypeLive;

  factory LiveRoom.fromJson(Map<String, dynamic> j) => LiveRoom(
        roomId: (j['roomId'] ?? '').toString(),
        hostId: (j['hostId'] ?? '').toString(),
        hostName: (j['hostName'] ?? '').toString(),
        hostAvatar: publicMediaUrl((j['hostAvatar'] ?? '').toString()),
        coverUrl: publicMediaUrl((j['coverUrl'] ?? j['hostAvatar'] ?? '').toString()),
        title: (j['title'] ?? '').toString(),
        roomType: (j['roomType'] ?? 'live').toString(),
        mediaMode: (j['mediaMode'] ?? 'hls').toString(),
        livekitUrl: (j['livekitUrl'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        pushUrl: (j['pushUrl'] ?? '').toString(),
        playUrl: publicMediaUrl((j['playUrl'] ?? '').toString()),
        whipPublishUrl: (j['whipPublishUrl'] ?? '').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
        startedAt: j['startedAt']?.toString(),
        hasJoinPassword: j['hasJoinPassword'] == true,
        joinPassword: (j['joinPassword'] ?? '').toString(),
        recording: j['recording'] == true,
      );

  bool get isLive => status == 'live';
  bool get canStart => status == 'idle';

  /// OBS「服务器」= pushUrl 去掉末尾 /{streamKey}
  String get rtmpServer {
    if (pushUrl.isEmpty) return '';
    final i = pushUrl.lastIndexOf('/');
    return i > 0 ? pushUrl.substring(0, i) : pushUrl;
  }

  /// OBS「串流密钥」= roomId（与 SRS app 名 live 下的 stream）
  String get streamKey => roomId.isNotEmpty ? roomId : pushUrl.split('/').last;
}

class ReplayViewer {
  final String userId;
  final String userName;
  final bool isHost;

  const ReplayViewer({required this.userId, this.userName = '', this.isHost = false});

  factory ReplayViewer.fromJson(Map<String, dynamic> j) => ReplayViewer(
        userId: (j['userId'] ?? '').toString(),
        userName: (j['userName'] ?? '').toString(),
        isHost: j['isHost'] == true,
      );
}

class LiveBackdropItem {
  final String id;
  final String name;
  final String imageUrl;
  final double price;
  final bool owned;

  const LiveBackdropItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.price = 0,
    this.owned = false,
  });

  bool get free => price <= 0;

  factory LiveBackdropItem.empty() => const LiveBackdropItem(id: '', name: '', imageUrl: '');

  factory LiveBackdropItem.fromJson(Map<String, dynamic> j) => LiveBackdropItem(
        id: (j['backdropId'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        imageUrl: (j['imageUrl'] ?? '').toString(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        owned: j['owned'] == true,
      );
}

class LiveMessage {
  final String msgId;
  final String authorId;
  final String authorName;
  final String text;
  final String createdAt;

  const LiveMessage({
    required this.msgId,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.createdAt = '',
  });

  factory LiveMessage.fromJson(Map<String, dynamic> j) => LiveMessage(
        msgId: (j['msgId'] ?? '').toString(),
        authorId: (j['authorId'] ?? '').toString(),
        authorName: (j['authorName'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
      );
}

class LiveParticipant {
  final String userId;
  final String userName;
  final bool isHost;
  final bool handRaised;
  final bool speaking;

  const LiveParticipant({
    required this.userId,
    required this.userName,
    this.isHost = false,
    this.handRaised = false,
    this.speaking = false,
  });

  factory LiveParticipant.fromJson(Map<String, dynamic> j) => LiveParticipant(
        userId: (j['userId'] ?? '').toString(),
        userName: (j['userName'] ?? '').toString(),
        isHost: j['isHost'] == true,
        handRaised: j['handRaised'] == true,
        speaking: j['speaking'] == true,
      );
}

class LiveCaption {
  final String captionId;
  final String speakerId;
  final String speakerName;
  final String text;
  final bool isFinal;

  const LiveCaption({
    required this.captionId,
    required this.speakerId,
    required this.speakerName,
    required this.text,
    this.isFinal = true,
  });

  factory LiveCaption.fromJson(Map<String, dynamic> j) => LiveCaption(
        captionId: (j['captionId'] ?? '').toString(),
        speakerId: (j['speakerId'] ?? '').toString(),
        speakerName: (j['speakerName'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        isFinal: j['final'] != false,
      );
}

class LiveGiftOrderResult {
  final String giftOrderId;
  final String giftId;
  final String giftName;
  final String emoji;
  final double amount;

  LiveGiftOrderResult({
    required this.giftOrderId,
    required this.giftId,
    required this.giftName,
    required this.emoji,
    required this.amount,
  });

  factory LiveGiftOrderResult.fromJson(Map<String, dynamic> j) => LiveGiftOrderResult(
        giftOrderId: (j['giftOrderId'] ?? '').toString(),
        giftId: (j['giftId'] ?? '').toString(),
        giftName: (j['giftName'] ?? '').toString(),
        emoji: (j['emoji'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
      );
}

class LiveGiftEvent {
  final String emoji;
  final String giftName;
  final String senderName;
  final double amount;

  const LiveGiftEvent({
    required this.emoji,
    required this.giftName,
    required this.senderName,
    required this.amount,
  });

  factory LiveGiftEvent.fromJson(Map<String, dynamic> j) {
    final gift = Map<String, dynamic>.from((j['gift'] as Map?) ?? j);
    return LiveGiftEvent(
      emoji: (gift['emoji'] ?? '🎁').toString(),
      giftName: (gift['giftName'] ?? '').toString(),
      senderName: (gift['senderName'] ?? '').toString(),
      amount: (gift['amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class LiveGiftRank {
  final int rank;
  final String senderId;
  final String senderName;
  final double totalAmount;
  final int giftCount;

  const LiveGiftRank({
    required this.rank,
    required this.senderId,
    required this.senderName,
    required this.totalAmount,
    required this.giftCount,
  });

  factory LiveGiftRank.fromJson(Map<String, dynamic> j) => LiveGiftRank(
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        senderId: (j['senderId'] ?? '').toString(),
        senderName: (j['senderName'] ?? '').toString(),
        totalAmount: (j['totalAmount'] as num?)?.toDouble() ?? 0,
        giftCount: (j['giftCount'] as num?)?.toInt() ?? 0,
      );
}

class LiveGiftEarnings {
  final double totalAmount;
  final int giftCount;

  const LiveGiftEarnings({required this.totalAmount, required this.giftCount});

  factory LiveGiftEarnings.fromJson(Map<String, dynamic> j) => LiveGiftEarnings(
        totalAmount: (j['totalAmount'] as num?)?.toDouble() ?? 0,
        giftCount: (j['giftCount'] as num?)?.toInt() ?? 0,
      );
}

class LiveRoomEarnings {
  final String roomId;
  final String title;
  final double totalAmount;
  final int giftCount;
  final String lastAt;

  const LiveRoomEarnings({
    required this.roomId,
    required this.title,
    required this.totalAmount,
    required this.giftCount,
    this.lastAt = '',
  });

  factory LiveRoomEarnings.fromJson(Map<String, dynamic> j) => LiveRoomEarnings(
        roomId: (j['roomId'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        totalAmount: (j['totalAmount'] as num?)?.toDouble() ?? 0,
        giftCount: (j['giftCount'] as num?)?.toInt() ?? 0,
        lastAt: (j['lastAt'] ?? '').toString(),
      );
}

class LiveGiftRecord {
  final String giftName;
  final String emoji;
  final String senderName;
  final double amount;
  final String roomId;
  final String createdAt;

  const LiveGiftRecord({
    required this.giftName,
    required this.emoji,
    required this.senderName,
    required this.amount,
    required this.roomId,
    this.createdAt = '',
  });

  factory LiveGiftRecord.fromJson(Map<String, dynamic> j) => LiveGiftRecord(
        giftName: (j['giftName'] ?? '').toString(),
        emoji: (j['emoji'] ?? '🎁').toString(),
        senderName: (j['senderName'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        roomId: (j['roomId'] ?? '').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
      );
}

class LiveEarningsDetail {
  final double totalAmount;
  final int giftCount;
  final List<LiveRoomEarnings> rooms;
  final List<LiveGiftRecord> recent;

  const LiveEarningsDetail({
    required this.totalAmount,
    required this.giftCount,
    required this.rooms,
    required this.recent,
  });

  factory LiveEarningsDetail.fromJson(Map<String, dynamic> j) => LiveEarningsDetail(
        totalAmount: (j['totalAmount'] as num?)?.toDouble() ?? 0,
        giftCount: (j['giftCount'] as num?)?.toInt() ?? 0,
        rooms: (j['rooms'] as List? ?? [])
            .map((e) => LiveRoomEarnings.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        recent: (j['recent'] as List? ?? [])
            .map((e) => LiveGiftRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class LiveRedPacket {
  final String packetId;
  final String title;
  final double totalAmount;
  final int totalCount;
  final double remainAmount;
  final int remainCount;
  final String status;

  const LiveRedPacket({
    required this.packetId,
    required this.title,
    required this.totalAmount,
    required this.totalCount,
    required this.remainAmount,
    required this.remainCount,
    required this.status,
  });

  bool get isActive => status == 'active' && remainCount > 0;

  factory LiveRedPacket.fromJson(Map<String, dynamic> j) => LiveRedPacket(
        packetId: (j['packetId'] ?? '').toString(),
        title: (j['title'] ?? '红包').toString(),
        totalAmount: (j['totalAmount'] as num?)?.toDouble() ?? 0,
        totalCount: (j['totalCount'] as num?)?.toInt() ?? 0,
        remainAmount: (j['remainAmount'] as num?)?.toDouble() ?? 0,
        remainCount: (j['remainCount'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? '').toString(),
      );
}

class LiveRedPacketGrab {
  final String packetId;
  final double amount;
  final String senderName;
  final int? remainCount;

  const LiveRedPacketGrab({
    required this.packetId,
    required this.amount,
    required this.senderName,
    this.remainCount,
  });

  factory LiveRedPacketGrab.fromJson(Map<String, dynamic> j) {
    final grab = Map<String, dynamic>.from((j['grab'] as Map?) ?? j);
    return LiveRedPacketGrab(
      packetId: (grab['packetId'] ?? '').toString(),
      amount: (grab['amount'] as num?)?.toDouble() ?? 0,
      senderName: (grab['senderName'] ?? '').toString(),
      remainCount: (grab['remainCount'] as num?)?.toInt(),
    );
  }
}

class LiveCohost {
  final String status;
  final String userId;
  final String userName;
  final String playUrl;
  final bool pushActive;

  const LiveCohost({
    this.status = 'idle',
    this.userId = '',
    this.userName = '',
    this.playUrl = '',
    this.pushActive = false,
  });

  bool get isIdle => status.isEmpty || status == 'idle';
  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';

  factory LiveCohost.fromJson(Map<String, dynamic> j) => LiveCohost(
        status: (j['status'] ?? 'idle').toString(),
        userId: (j['userId'] ?? '').toString(),
        userName: (j['userName'] ?? '').toString(),
        playUrl: publicMediaUrl((j['playUrl'] ?? '').toString()),
        pushActive: j['pushActive'] == true,
      );
}

class LivePk {
  final String pkId;
  final String status;
  final String myName;
  final String opName;
  final double myScore;
  final double opScore;
  final String? endsAt;
  final int durationMin;
  final String inviterRoom;
  final String roomA;
  final String roomB;
  final String opRoomId;
  final String opPlayUrl;

  const LivePk({
    this.pkId = '',
    this.status = '',
    this.myName = '',
    this.opName = '',
    this.myScore = 0,
    this.opScore = 0,
    this.endsAt,
    this.durationMin = 5,
    this.inviterRoom = '',
    this.roomA = '',
    this.roomB = '',
    this.opRoomId = '',
    this.opPlayUrl = '',
  });

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get iWon => myScore > opScore;
  bool get isTie => myScore == opScore;

  factory LivePk.fromJson(Map<String, dynamic> j) => LivePk(
        pkId: (j['pkId'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        myName: (j['myName'] ?? '').toString(),
        opName: (j['opName'] ?? '').toString(),
        myScore: (j['myScore'] as num?)?.toDouble() ?? 0,
        opScore: (j['opScore'] as num?)?.toDouble() ?? 0,
        endsAt: j['endsAt']?.toString(),
        durationMin: (j['durationMin'] as num?)?.toInt() ?? 5,
        inviterRoom: (j['inviterRoom'] ?? '').toString(),
        roomA: (j['roomA'] ?? '').toString(),
        roomB: (j['roomB'] ?? '').toString(),
        opRoomId: (j['opRoomId'] ?? '').toString(),
        opPlayUrl: publicMediaUrl((j['opPlayUrl'] ?? '').toString()),
      );
}
