import 'package:http/http.dart' as http;
import 'api_client.dart';

class ImApi {
  final ApiClient _c;
  ImApi(String token) : _c = ApiClient(token: token);

  Future<http.Response> groups() => _c.get('/app/im/groups');
  Future<http.Response> sessions() => _c.get('/app/im/sessions');
  Future<http.Response> messages(String peerId, {int limit = 0, int offset = 0}) =>
      _c.get('/app/im/messages', query: {
        'peerId': peerId,
        if (limit > 0) 'limit': '$limit',
        if (offset > 0) 'offset': '$offset',
      });

  Future<http.Response> unreadCount() => _c.get('/app/im/unread');

  Future<http.Response> send({String? toUserId, String? groupId, required String content, String contentType = 'text'}) =>
      _c.post('/app/im/send', body: {
        if (toUserId != null) 'toUserId': toUserId,
        if (groupId != null) 'groupId': groupId,
        'content': content,
        'contentType': contentType,
      });

  Future<http.Response> createGroup(String name, List<String> members) =>
      _c.post('/app/im/group/create', body: {'name': name, 'members': members});

  Future<http.Response> joinGroup(String groupId) =>
      _c.post('/app/im/group/$groupId/join');

  Future<http.Response> leaveGroup(String groupId, {String? userId}) =>
      _c.post('/app/im/group/$groupId/leave', body: userId == null ? null : {'userId': userId});

  Future<http.Response> groupMembers(String groupId) =>
      _c.get('/app/im/group/$groupId/members');

  Future<http.Response> groupMessages(String groupId, {int limit = 0, int offset = 0}) =>
      _c.get('/app/im/group/$groupId/messages', query: {
        if (limit > 0) 'limit': '$limit',
        if (offset > 0) 'offset': '$offset',
      });

  Future<http.Response> groupNotice(String groupId) =>
      _c.get('/app/im/group/$groupId/notice');

  Future<http.Response> updateGroupNotice(String groupId, String notice) =>
      _c.put('/app/im/group/$groupId/notice', body: {'notice': notice});

  Future<http.Response> revokeMessage(String msgId) =>
      _c.post('/app/im/revoke/$msgId');

  Future<http.Response> markRead(String msgId) =>
      _c.post('/app/im/read', body: {'msgId': msgId});

  Future<http.Response> transferOwner(String groupId, String newOwnerId) =>
      _c.put('/app/im/group/$groupId/transfer', body: {'newOwnerId': newOwnerId});

  Future<http.Response> inviteMembers(String groupId, List<String> members) =>
      _c.post('/app/im/group/$groupId/invite', body: {'members': members});

  Future<http.Response> renameGroup(String groupId, String name) =>
      _c.put('/app/im/group/$groupId/name', body: {'name': name});

  Future<http.Response> setMemberAlias(String groupId, String userId, String alias) =>
      _c.put('/app/im/group/$groupId/member/$userId/alias', body: {'alias': alias});

  Future<http.Response> searchUsers(String query) =>
      _c.get('/app/im/users/search', query: {'q': query});

  Future<http.Response> togglePinSession(String sessionId) =>
      _c.put('/app/im/session/$sessionId/pin');

  Future<http.Response> toggleMuteSession(String sessionId) =>
      _c.put('/app/im/session/$sessionId/mute');

  Future<http.Response> setSessionHidden(String sessionId, bool hidden) =>
      _c.put('/app/im/session/$sessionId/hide', body: {'hidden': hidden});
}
