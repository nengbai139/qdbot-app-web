import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_client.dart';
import '../config.dart';
import '../util/file_mime.dart';
import '../util/media_url.dart';

class DriveNode {
  DriveNode({
    required this.nodeId,
    required this.name,
    required this.nodeType,
    this.parentId,
    this.sizeBytes = 0,
    this.mimeType,
    this.downloadUrl,
  });

  final String nodeId;
  final String name;
  final String nodeType;
  final String? parentId;
  final int sizeBytes;
  final String? mimeType;
  final String? downloadUrl;

  factory DriveNode.fromJson(Map<String, dynamic> j) => DriveNode(
        nodeId: j['nodeId']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        nodeType: j['nodeType']?.toString() ?? 'file',
        parentId: j['parentId']?.toString(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        mimeType: j['mimeType']?.toString(),
        downloadUrl: j['downloadUrl']?.toString(),
      );
}

class DriveQuota {
  DriveQuota({required this.usedBytes, required this.limitBytes});
  final int usedBytes;
  final int limitBytes;

  factory DriveQuota.fromJson(Map<String, dynamic> j) => DriveQuota(
        usedBytes: (j['usedBytes'] as num?)?.toInt() ?? 0,
        limitBytes: (j['limitBytes'] as num?)?.toInt() ?? 0,
      );
}

class DriveUploadInit {
  DriveUploadInit({
    required this.nodeId,
    required this.storageKey,
    required this.uploadUrl,
    this.downloadUrl,
  });

  final String nodeId;
  final String storageKey;
  final String uploadUrl;
  final String? downloadUrl;

  factory DriveUploadInit.fromJson(Map<String, dynamic> j) => DriveUploadInit(
        nodeId: j['nodeId']?.toString() ?? '',
        storageKey: j['storageKey']?.toString() ?? '',
        uploadUrl: j['uploadUrl']?.toString() ?? '',
        downloadUrl: j['downloadUrl']?.toString(),
      );
}

/// 云盘 API（Phase 1）
class DriveApi {
  DriveApi(String token) : _c = ApiClient(token: token);
  final ApiClient _c;

  Future<List<DriveNode>> listNodes({String? parentId, bool trash = false}) async {
    final q = <String, String>{};
    if (parentId != null && parentId.isNotEmpty) q['parentId'] = parentId;
    if (trash) q['trash'] = 'true';
    final resp = await _c.get('/app/drive/nodes', query: q);
    if (resp.statusCode != 200) throw Exception(resp.body);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final nodes = data['nodes'] as List? ?? const [];
    return nodes.map((e) => DriveNode.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<DriveNode> createFolder(String name, {String? parentId}) async {
    final resp = await _c.post('/app/drive/folders', body: {
      'name': name,
      if (parentId != null) 'parentId': parentId,
    });
    if (resp.statusCode != 200) throw Exception(resp.body);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return DriveNode.fromJson(data['node'] as Map<String, dynamic>);
  }

  Future<DriveUploadInit> uploadInit({
    required String name,
    String? parentId,
    String? mimeType,
    int sizeBytes = 0,
  }) async {
    final resp = await _c.post('/app/drive/upload/init', body: {
      'name': name,
      if (parentId != null) 'parentId': parentId,
      if (mimeType != null) 'mimeType': mimeType,
      'sizeBytes': sizeBytes,
    });
    if (resp.statusCode != 200) throw Exception(resp.body);
    return DriveUploadInit.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<DriveNode> uploadComplete({
    required String nodeId,
    required String url,
    required int sizeBytes,
    String? sha256,
  }) async {
    final resp = await _c.post('/app/drive/upload/complete', body: {
      'nodeId': nodeId,
      'url': url,
      'sizeBytes': sizeBytes,
      if (sha256 != null) 'sha256': sha256,
    });
    if (resp.statusCode != 200) throw Exception(resp.body);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return DriveNode.fromJson(data['node'] as Map<String, dynamic>);
  }

  Future<DriveNode> getFile(String nodeId) async {
    final resp = await _c.get('/app/drive/files/$nodeId');
    if (resp.statusCode != 200) throw Exception(resp.body);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return DriveNode.fromJson(data['node'] as Map<String, dynamic>);
  }

  Future<DriveQuota> quota() async {
    final resp = await _c.get('/app/drive/quota');
    if (resp.statusCode != 200) throw Exception(resp.body);
    return DriveQuota.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> trash(String nodeId) async {
    final resp = await _c.delete('/app/drive/nodes/$nodeId');
    if (resp.statusCode != 200) throw Exception(resp.body);
  }

  Future<DriveNode> rename(String nodeId, String name) async {
    final resp = await _c.patch('/app/drive/nodes/$nodeId', body: {'name': name});
    if (resp.statusCode != 200) throw Exception(resp.body);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return DriveNode.fromJson(data['node'] as Map<String, dynamic>);
  }

  /// init → 带 objectKey 直传 qdbot_images → complete
  Future<DriveNode> uploadBytes(
    List<int> bytes, {
    required String name,
    String? parentId,
    String? mimeType,
  }) async {
    final init = await uploadInit(
      name: name,
      parentId: parentId,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
    final url = await _uploadWithObjectKey(bytes, name: name, objectKey: init.storageKey);
    return uploadComplete(nodeId: init.nodeId, url: url, sizeBytes: bytes.length);
  }

  Future<String> _uploadWithObjectKey(
    List<int> bytes, {
    required String name,
    required String objectKey,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('${AppConfig.baseUrl}/qdbot_images/upload'));
    req.fields['objectKey'] = objectKey;
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: name,
      contentType: MediaType.parse(mimeForFilename(name)),
    ));
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) throw Exception(resp.body);
    final url = (jsonDecode(resp.body) as Map<String, dynamic>)['url']?.toString().trim() ?? '';
    if (url.isEmpty) throw Exception('upload ok but no url');
    return publicMediaUrl(url);
  }
}
