/// 靓号分享 deep link（Web: ?userCode=U202600888）
const kAppWebBase = 'https://www.aimatchem.com/app_web/';

String? parseUserCodeFromUri(Uri uri) {
  final raw = (uri.queryParameters['userCode'] ?? uri.queryParameters['code'] ?? '').trim();
  return raw.length >= 2 ? raw : null;
}

String shareLinkForUserCode(String code) {
  return Uri.parse(kAppWebBase).replace(queryParameters: {'userCode': code}).toString();
}
