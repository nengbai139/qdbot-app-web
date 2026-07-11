import '../config.dart';

/// Normalizes image URLs for HTTPS web (chat, avatar, etc.).
String publicMediaUrl(String url) {
  if (url.isEmpty) return url;
  var u = url.trim();
  if (u.endsWith('?')) u = u.substring(0, u.length - 1);
  final parsed = Uri.tryParse(u);
  if (parsed == null) return u;
  final base = Uri.parse(AppConfig.baseUrl);

  // Legacy dev presign: path is public-read via nginx /images/ → OSS
  if (parsed.host == 'host.docker.internal' && parsed.path.startsWith('/images/')) {
    return Uri(scheme: base.scheme, host: base.host, path: parsed.path).toString();
  }

  // OSS 直链（私有桶 403）→ nginx /images/{key}
  if (parsed.host.contains('aliyuncs.com')) {
    final key = parsed.path.startsWith('/') ? parsed.path.substring(1) : parsed.path;
    if (key.isNotEmpty) {
      return Uri(scheme: base.scheme, host: base.host, path: '/images/$key').toString();
    }
  }

  if (parsed.scheme == 'http' && parsed.host == base.host) {
    return Uri(scheme: 'https', host: parsed.host, path: parsed.path).toString();
  }

  // Public bucket path — drop stale presign query if any
  if (parsed.host == base.host && parsed.path.startsWith('/images/')) {
    return Uri(scheme: base.scheme, host: base.host, path: parsed.path).toString();
  }

  return u;
}
