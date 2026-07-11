/// ponytail: 推流检测防抖；避免 SRS/HLS 瞬时抖动把播放器拆掉导致黑屏
class StreamLatch {
  bool displayed = false;
  int _inactiveStreak = 0;

  /// 更新服务端 pushActive，返回 UI 是否应继续显示播放器。
  bool update(bool active) {
    if (active) {
      _inactiveStreak = 0;
      displayed = true;
      return true;
    }
    if (!displayed) return false;
    _inactiveStreak++;
    // 连续 4 次未检测到（约 8s）才切回等待态
    if (_inactiveStreak >= 4) {
      displayed = false;
      return false;
    }
    return true;
  }

  bool get reconnecting => displayed && _inactiveStreak > 0;

  void reset() {
    displayed = false;
    _inactiveStreak = 0;
  }
}
