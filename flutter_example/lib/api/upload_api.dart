import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_client.dart';
import '../config.dart';
import '../util/file_mime.dart';
import '../util/media_url.dart';
import '../util/video_poster.dart';

/// 根据文件头 / 文件名推断上传类型（服务端用于扩展名与 Content-Type）
String detectImageUploadType(List<int> bytes, {String? filename}) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 3 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return 'gif';
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45) {
    return 'webp';
  }
  final lower = (filename ?? '').toLowerCase();
  if (lower.endsWith('.png')) return 'png';
  if (lower.endsWith('.webp')) return 'webp';
  if (lower.endsWith('.gif')) return 'gif';
  return 'jpeg';
}

String detectMediaUploadType(List<int> bytes, {String? filename}) {
  final lower = (filename ?? '').toLowerCase();
  if (bytes.length >= 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
    return 'mp4';
  }
  if (bytes.length >= 4 && bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3) {
    return 'webm';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 3 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return 'gif';
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45) {
    return 'webp';
  }
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'jpeg';
  final dot = lower.lastIndexOf('.');
  if (dot > 0 && dot < lower.length - 1) {
    final ext = lower.substring(dot + 1);
    if (ext.length <= 8) return ext;
  }
  return detectImageUploadType(bytes, filename: filename);
}

class MediaUploadInit {
  MediaUploadInit({
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

  factory MediaUploadInit.fromJson(Map<String, dynamic> j) => MediaUploadInit(
        mediaId: j['mediaId']?.toString() ?? '',
        objectKey: j['objectKey']?.toString() ?? '',
        uploadUrl: j['uploadUrl']?.toString() ?? '',
        downloadUrl: j['downloadUrl']?.toString() ?? '',
        kind: j['kind']?.toString() ?? '',
      );
}

/// IM / 头像 / AI 附件 → qdbot_system init + qdbot_images objectKey
class UploadApi {
  final ApiClient _c;
  UploadApi(String token) : _c = ApiClient(token: token);

  Future<String> uploadAvatarBytes(List<int> bytes, {required String userId, String? filename}) =>
      _uploadWithKind(bytes, userId: userId, kind: 'avatar', filename: filename, maxBytes: 2 * 1024 * 1024, label: '头像');

  Future<String> uploadImageBytes(List<int> bytes, {required String userId, String? filename}) =>
      _uploadWithKind(bytes, userId: userId, kind: 'image', filename: filename, maxBytes: 5 * 1024 * 1024, label: '图片');

  Future<String> uploadAudioBytes(List<int> bytes, {required String userId, String? filename}) =>
      _uploadWithKind(bytes, userId: userId, kind: 'voice', filename: filename, maxBytes: 5 * 1024 * 1024, label: '语音');

  Future<String> uploadVideoBytes(List<int> bytes, {required String userId, String? filename}) =>
      _uploadWithKind(bytes, userId: userId, kind: 'video', filename: filename, maxBytes: 20 * 1024 * 1024, label: '视频');

  Future<String> uploadFileBytes(List<int> bytes, {required String userId, String? filename}) =>
      _uploadWithKind(bytes, userId: userId, kind: 'file', filename: filename, maxBytes: 10 * 1024 * 1024, label: '文件');

  Future<String> uploadGroupAvatarBytes(
    List<int> bytes, {
    required String userId,
    required String groupId,
    String? filename,
  }) =>
      _uploadWithKind(
        bytes,
        userId: userId,
        kind: 'group_avatar',
        filename: filename,
        groupId: groupId,
        maxBytes: 2 * 1024 * 1024,
        label: '群头像',
      );

  Future<({String url, String? poster})> uploadVideoWithPoster(
    List<int> bytes, {
    required String userId,
    String? filename,
  }) async {
    final results = await Future.wait<Object?>([
      uploadVideoBytes(bytes, userId: userId, filename: filename),
      captureVideoPosterJpeg(bytes, filename: filename),
    ]);
    final url = results[0]! as String;
    final posterBytes = results[1] as List<int>?;
    String? poster;
    if (posterBytes != null && posterBytes.isNotEmpty) {
      poster = await _uploadPoster(posterBytes, userId: userId);
    }
    return (url: url, poster: poster);
  }

  Future<String?> _uploadPoster(List<int> bytes, {required String userId}) async {
    for (final kind in ['poster', 'image']) {
      try {
        return await _uploadWithKind(
          bytes,
          userId: userId,
          kind: kind,
          filename: 'poster.jpg',
          maxBytes: 2 * 1024 * 1024,
          label: '封面',
        );
      } catch (_) {}
    }
    return null;
  }

  Future<MediaUploadInit> mediaUploadInit({
    required String kind,
    required String filename,
    int sizeBytes = 0,
    String? groupId,
  }) async {
    final resp = await _c.post('/app/media/upload/init', body: {
      'kind': kind,
      'filename': filename,
      'sizeBytes': sizeBytes,
      if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
    });
    if (resp.statusCode != 200) throw Exception('init failed: ${resp.body}');
    return MediaUploadInit.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<String> _uploadWithKind(
    List<int> bytes, {
    required String userId,
    required String kind,
    String? filename,
    String? groupId,
    required int maxBytes,
    required String label,
  }) async {
    if (bytes.length > maxBytes) {
      throw Exception('$label不能超过 ${maxBytes ~/ (1024 * 1024)}MB');
    }
    final ext = detectMediaUploadType(bytes, filename: filename);
    var name = (filename ?? '').trim();
    if (name.isEmpty) name = 'upload.$ext';
    if (!name.contains('.')) name = '$name.$ext';

    final init = await mediaUploadInit(kind: kind, filename: name, sizeBytes: bytes.length, groupId: groupId);
    final uploadUrl = init.uploadUrl.isNotEmpty
        ? init.uploadUrl
        : '${AppConfig.baseUrl}/qdbot_images/upload';

    final req = http.MultipartRequest('POST', Uri.parse(uploadUrl));
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
    if (resp.statusCode == 200) {
      // ponytail: 服务端缺 PUBLIC_BASE_URL 时 body.url 为 OSS 预签名；init.downloadUrl 才是稳定公网路径
      final canonical = publicMediaUrl(init.downloadUrl);
      if (canonical.isNotEmpty) return canonical;
      final url = (jsonDecode(resp.body) as Map<String, dynamic>)['url']?.toString().trim() ?? '';
      return publicMediaUrl(url);
    }
    throw Exception('上传失败: ${resp.body}');
  }
}
