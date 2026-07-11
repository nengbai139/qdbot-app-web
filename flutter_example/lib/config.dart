/// 服务端地址（可通过 --dart-define=QDBOT_BASE_URL=... 覆盖）
class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'QDBOT_BASE_URL',
    defaultValue: 'https://www.aimatchem.com',
  );

  static const wsPath = String.fromEnvironment(
    'QDBOT_WS_PATH',
    defaultValue: '/ws/app/connect',
  );

  static String wsConnectUrl(String token) =>
      '${baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://')}$wsPath?token=${Uri.encodeComponent(token)}';

  /// WebRTC ICE/TURN 凭证服务（独立 relay，nginx 反代 /webrtc/）
  static const webrtcRelayUrl = String.fromEnvironment(
    'QDBOT_WEBRTC_URL',
    defaultValue: 'https://www.aimatchem.com/webrtc',
  );

  /// 圈子微服务 API（nginx 反代 /app/circle/v1/ → qdbot_circle:8100）
  static const circleApiPath = String.fromEnvironment(
    'QDBOT_CIRCLE_PATH',
    defaultValue: '/app/circle/v1',
  );
}
