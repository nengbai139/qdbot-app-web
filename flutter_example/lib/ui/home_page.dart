import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../api/ai_api.dart';
import '../api/im_api.dart';
import '../call/call_service.dart';
import '../session.dart';
import '../ws/app_ws.dart';
import '../ws/app_msg_bus.dart';
import '../app_nav.dart';
import '../util/circle_conv.dart';
import '../util/home_bootstrap.dart';
import '../util/tab_data_cache.dart';
import '../util/notify_inbox.dart';
import '../util/push_register.dart';
import '../util/web_notify.dart';
import 'chat_helpers.dart';
import 'ai_chats_tab.dart';
import 'circle/circle_navigation.dart';
import 'circle/meeting_deep_link.dart';
import 'circle/circle_tab.dart';
import 'im_chats_tab.dart';
import 'onboarding_page.dart';
import 'profile/notification_settings_page.dart';
import 'profile_tab.dart';

class HomePage extends StatefulWidget {
  final String token;
  final String userId;
  final String userCode;

  const HomePage({super.key, required this.token, required this.userId, this.userCode = ''});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ponytail: 角标/横幅用 ValueNotifier，避免 setState 重建 IndexedStack 导致 Tab 整页闪
  final _tabIndex = ValueNotifier(0);
  final _imUnread = ValueNotifier(0);
  final _inboxUnread = ValueNotifier(0);
  final _aiActivity = ValueNotifier(false);
  final _circleActivity = ValueNotifier(false);
  final _wsConnected = ValueNotifier(true);

  Timer? _wsBannerTimer;
  final _profileKey = GlobalKey<ProfileTabState>();
  final _imKey = GlobalKey<IMChatsTabState>();
  final _aiKey = GlobalKey<AIChatsTabState>();
  final _circleKey = GlobalKey<CircleTabState>();
  final _imMsgStream = AppMsgBus.im;
  final _aiMsgStream = AppMsgBus.ai;
  Timer? _circleRefreshDebounce;
  Timer? _inboxRefreshDebounce;
  Timer? _imUnreadDebounce;
  late final List<Widget> _tabs;
  StreamSubscription<Map<String, dynamic>>? _wsMsgSub;
  VoidCallback? _wsConnListener;
  late final ImApi _im = ImApi(widget.token);

  @override
  void initState() {
    super.initState();
    TabDataCache.bindToken(widget.token);
    TabDataCache.restore(widget.token);
    _tabs = [
      RepaintBoundary(
        child: IMChatsTab(
          key: _imKey,
          token: widget.token,
          userId: widget.userId,
          userCode: widget.userCode,
          msgStream: _imMsgStream.stream,
          onUnreadChanged: _refreshUnread,
          isTabActive: () => _tabIndex.value == 0,
        ),
      ),
      RepaintBoundary(
        child: AIChatsTab(
          key: _aiKey,
          token: widget.token,
          userId: widget.userId,
          msgStream: _aiMsgStream.stream,
          isTabActive: () => _tabIndex.value == 1,
        ),
      ),
      RepaintBoundary(
        child: CircleTab(key: _circleKey, token: widget.token, userId: widget.userId),
      ),
      RepaintBoundary(
        child: ProfileTab(
          key: _profileKey,
          token: widget.token,
          userId: widget.userId,
          displayId: widget.userCode.isNotEmpty ? widget.userCode : widget.userId,
          inboxUnreadListenable: _inboxUnread,
          onInboxChanged: _refreshInboxUnread,
        ),
      ),
    ];
    _ensureOnboarding();
    AppWs.ensureStarted(widget.token);
    _wsMsgSub = AppWs.messages.listen(_onWsMessage);
    // ponytail: 延迟非关键 API，等 WS 连上 + 页面渲染完成再加载，减少移动端内存峰值
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _handlePendingUserCode();
      _handlePendingMeeting();
      _maybePromptWebNotify();
      if (await HomeBootstrap.shouldInit(widget.token)) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _refreshUnread();
        });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _aiKey.currentState?.refreshIfStale();
            _profileKey.currentState?.refreshIfStale();
          }
        });
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _refreshInboxUnread();
        });
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) {
            syncNotificationPrefsFromServer(widget.token);
            _checkSubscriptionExpiryNotify();
          }
        });
      }
      if (mounted) registerPushIfNeeded(authToken: widget.token, userId: widget.userId);
    });
    setupWebNotifyHandler((kind, data) {
      if (!mounted) return;
      if (kind == 'subscription') {
        _tabIndex.value = 3;
        return;
      }
      if (kind == 'circle') {
        _tabIndex.value = 2;
        _circleActivity.value = false;
        final roomId = (data['roomId'] ?? '').toString();
        if (roomId.isNotEmpty) {
          _openLiveRoom(roomId);
        } else {
          _circleKey.currentState?.refresh();
        }
        return;
      }
      if (kind == 'ai') {
        _tabIndex.value = 1;
        _aiActivity.value = false;
        _aiKey.currentState?.openFromNotify(data);
      } else {
        _tabIndex.value = 0;
        _imKey.currentState?.openFromNotify(data);
      }
    });
    _wsConnListener = () {
      if (!mounted) return;
      _wsBannerTimer?.cancel();
      if (AppWs.connected.value) {
        if (!_wsConnected.value) _wsConnected.value = true;
        return;
      }
      _wsBannerTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _wsConnected.value) _wsConnected.value = false;
      });
    };
    AppWs.connected.addListener(_wsConnListener!);
    CallCoordinator.instance.bind(navKey: rootNavigatorKey, userId: widget.userId, token: widget.token, im: _im);
  }

  Future<void> _onWsMessage(Map<String, dynamic> msg) async {
    if (!mounted) return;
        final t = (msg['type'] ?? '').toString();
        if (t == 'im') {
          final ct = (msg['contentType'] ?? msg['ext']?['contentType'] ?? '').toString();
          if (ct == 'call_signal') {
            CallCoordinator.instance.handleImMessage(msg);
            if (kIsWeb && webDocumentHidden()) {
              maybeNotifyCallSignal(msg);
            }
          }
          final muted = await SessionStore.loadMutedSessions();
          final hidden = await SessionStore.loadHiddenSessions();
          final gid = (msg['groupId'] ?? msg['ext']?['groupId'] ?? '').toString();
          final from = (msg['fromUserId'] ?? msg['ext']?['fromUserId'] ?? '').toString();
          final key = gid.isNotEmpty ? 'g:$gid' : 's:$from';
          final notifyOn = await SessionStore.loadWebNotifyEnabled();
          if (ct != 'call_signal' && !muted.contains(key) && !hidden.contains(key)) {
            final entry = NotifyInbox.imFromMessage(msg, null);
            if (entry != null) {
              await NotifyInbox.record(
                id: entry.id.isNotEmpty ? entry.id : null,
                kind: entry.kind,
                title: entry.title,
                body: entry.body,
                data: entry.data,
                token: widget.token,
              );
            }
            if (notifyOn) maybeNotifyImMessage(msg);
          }
          _debouncedRefreshUnread();
          _debouncedRefreshInboxUnread();
        } else if (t == 'ai') {
          final circleUtil = isCircleUtilityWs(Map<String, dynamic>.from(msg));
          if (!circleUtil) {
            final convId = aiConvIdFromWs(Map<String, dynamic>.from(msg));
            final content = (msg['content'] ?? '').toString();
            if (!isCircleUtilityConvId(convId) && !isAgentProgressContent(content)) {
              if (_tabIndex.value != 1 && !_aiActivity.value) _aiActivity.value = true;
              final notifyOn = await SessionStore.loadWebNotifyEnabled();
              final entry = NotifyInbox.aiFromMessage(msg);
              await NotifyInbox.record(
                id: entry.id.isNotEmpty ? entry.id : null,
                kind: entry.kind,
                title: entry.title,
                body: entry.body,
                data: entry.data,
                token: widget.token,
              );
              _debouncedRefreshInboxUnread();
              if (notifyOn) maybeNotifyAiMessage(msg);
            }
          }
        } else if (t == 'circle') {
          if (_tabIndex.value != 2 && !_circleActivity.value) _circleActivity.value = true;
          final entry = NotifyInbox.circleFromMessage(msg);
          if (entry != null) {
            await NotifyInbox.record(
              id: entry.id.isNotEmpty ? entry.id : null,
              kind: entry.kind,
              title: entry.title,
              body: entry.body,
              data: entry.data,
              token: widget.token,
            );
          }
          _debouncedRefreshInboxUnread();
          final notifyOn = await SessionStore.loadWebNotifyEnabled();
          if (notifyOn) maybeNotifyCircleMessage(msg);
          final event = (msg['event'] ?? entry?.data['event'] ?? '').toString();
          final payload = msg['payload'];
          final roomId = (payload is Map ? payload['roomId'] : null)?.toString() ?? (entry?.data['roomId'] ?? '').toString();
          if (event == 'live.start' && roomId.isNotEmpty) {
            _openLiveRoom(roomId);
          } else if (_tabIndex.value == 2) {
            _scheduleCircleRefresh();
          }
        }
        if (t == 'im') {
          AppMsgBus.publishIm(msg);
        } else if (t == 'ai' && !isCircleUtilityWs(Map<String, dynamic>.from(msg))) {
          AppMsgBus.publishAi(msg);
        }
  }

  Future<void> _maybePromptWebNotify() async {
    if (!kIsWeb || !mounted) return;
    if (!await SessionStore.loadWebNotifyEnabled()) return;
    if (await SessionStore.loadWebNotifyPromptDone()) return;
    await SessionStore.saveWebNotifyPromptDone();
    if (!mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开启浏览器通知'),
        content: const Text('允许后，在标签页未激活时也能收到 IM 与 AI 消息提醒（类似微信桌面通知）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('暂不')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('允许')),
        ],
      ),
    );
    if (allow != true || !mounted) return;
    final ok = await requestWebNotifyPermission();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未获得通知权限，可在浏览器地址栏或「我的 → 消息通知」中开启')),
      );
    }
  }

  Future<void> _handlePendingUserCode() async {
    final code = await SessionStore.takePendingUserCode();
    if (code == null || !mounted) return;
    _tabIndex.value = 0;
    await _imKey.currentState?.openFromUserCode(code);
  }

  Future<void> _handlePendingMeeting() async {
    final roomId = await SessionStore.takePendingMeetingRoom();
    if (roomId == null || !mounted) return;
    final passcode = await SessionStore.takePendingMeetingPasscode() ?? '';
    _tabIndex.value = 2;
    try {
      await joinMeetingByInvite(
        context,
        token: widget.token,
        userId: widget.userId,
        roomId: roomId,
        passcode: passcode,
      );
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.contains('wrong passcode') ? '入会密码错误' : '无法加入会议：$e')),
      );
    }
  }

  Future<void> _ensureOnboarding() async {
    final done = await SessionStore.loadOnboardingDone();
    if (done || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingPage(token: widget.token, userId: widget.userId, userCode: widget.userCode),
      ),
    );
  }

  Future<void> _checkSubscriptionExpiryNotify() async {
    try {
      final notifyOn = await SessionStore.loadWebNotifyEnabled();
      if (!notifyOn) return;
      final sub = await AiApi(widget.token).getSubscription();
      if (!sub.active || !sub.expiringSoon) return;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (await SessionStore.loadExpiryNotifyDate() == today) return;
      await NotifyInbox.record(
        id: NotifyInbox.inboxIdForSubscription(DateTime.now()),
        kind: 'subscription',
        title: '订阅即将到期',
        body: '${sub.planName.isNotEmpty ? sub.planName : 'AI Pro'} 还剩 ${sub.daysLeft} 天',
        data: const {'kind': 'subscription'},
        token: widget.token,
      );
      _refreshInboxUnread();
      maybeNotifySubscriptionExpiry(daysLeft: sub.daysLeft, planName: sub.planName);
      await SessionStore.saveExpiryNotifyDate(today);
    } catch (_) {}
  }

  Future<void> _refreshInboxUnread() async {
    try {
      final n = await NotifyInbox.unreadCount(token: widget.token);
      if (mounted && n != _inboxUnread.value) _inboxUnread.value = n;
    } catch (_) {}
  }

  void _debouncedRefreshInboxUnread() {
    _inboxRefreshDebounce?.cancel();
    _inboxRefreshDebounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _refreshInboxUnread();
    });
  }

  void _debouncedRefreshUnread() {
    _imUnreadDebounce?.cancel();
    _imUnreadDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _refreshUnread();
    });
  }

  void _scheduleCircleRefresh() {
    _circleRefreshDebounce?.cancel();
    _circleRefreshDebounce = Timer(const Duration(milliseconds: 2000), () {
      if (mounted && _tabIndex.value == 2) {
        _circleKey.currentState?.scheduleRefresh();
      }
    });
  }

  void _openLiveRoom(String roomId) {
    if (!mounted || roomId.isEmpty) return;
    openCircleRoomById(context, token: widget.token, userId: widget.userId, roomId: roomId);
  }

  Future<void> _refreshUnread() async {
    try {
      final resp = await _im.unreadCount();
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        final n = parseCount(data['unreadCount']);
        if (n != _imUnread.value) _imUnread.value = n;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _wsBannerTimer?.cancel();
    _circleRefreshDebounce?.cancel();
    _inboxRefreshDebounce?.cancel();
    _imUnreadDebounce?.cancel();
    setupWebNotifyHandler(null);
    _wsMsgSub?.cancel();
    if (_wsConnListener != null) AppWs.connected.removeListener(_wsConnListener!);
    _tabIndex.dispose();
    _imUnread.dispose();
    _inboxUnread.dispose();
    _aiActivity.dispose();
    _circleActivity.dispose();
    _wsConnected.dispose();
    super.dispose();
  }

  String _badgeLabel(int n) => n > 99 ? '99+' : '$n';

  Widget _wsBanner() {
    return Material(
      color: Colors.orange.shade100,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 18, color: Colors.orange.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text('连接已断开，正在重连…', style: TextStyle(color: Colors.orange.shade900, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomNav() {
    return ValueListenableBuilder<int>(
      valueListenable: _tabIndex,
      builder: (context, index, _) {
        return ValueListenableBuilder<int>(
          valueListenable: _imUnread,
          builder: (context, imUnread, __) {
            return ValueListenableBuilder<bool>(
              valueListenable: _aiActivity,
              builder: (context, aiActivity, ___) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _circleActivity,
                  builder: (context, circleActivity, ____) {
                    return ValueListenableBuilder<int>(
                      valueListenable: _inboxUnread,
                      builder: (context, inboxUnread, _____) {
                        return NavigationBar(
                          selectedIndex: index,
                          onDestinationSelected: _onTabSelected,
                          destinations: [
                            NavigationDestination(
                              icon: Badge(
                                isLabelVisible: imUnread > 0,
                                label: Text(_badgeLabel(imUnread)),
                                child: const Icon(Icons.chat_bubble_outline),
                              ),
                              selectedIcon: Badge(
                                isLabelVisible: imUnread > 0,
                                label: Text(_badgeLabel(imUnread)),
                                child: const Icon(Icons.chat_bubble),
                              ),
                              label: '消息',
                            ),
                            NavigationDestination(
                              icon: Badge(
                                isLabelVisible: aiActivity,
                                label: const Text('·'),
                                child: const Icon(Icons.smart_toy_outlined),
                              ),
                              selectedIcon: Badge(
                                isLabelVisible: aiActivity,
                                label: const Text('·'),
                                child: const Icon(Icons.smart_toy),
                              ),
                              label: '助手',
                            ),
                            NavigationDestination(
                              icon: Badge(
                                isLabelVisible: circleActivity,
                                label: const Text('·'),
                                child: const Icon(Icons.hub_outlined),
                              ),
                              selectedIcon: Badge(
                                isLabelVisible: circleActivity,
                                label: const Text('·'),
                                child: const Icon(Icons.hub),
                              ),
                              label: '圈子',
                            ),
                            NavigationDestination(
                              icon: Badge(
                                isLabelVisible: inboxUnread > 0,
                                label: Text(_badgeLabel(inboxUnread)),
                                child: const Icon(Icons.person_outline),
                              ),
                              selectedIcon: Badge(
                                isLabelVisible: inboxUnread > 0,
                                label: Text(_badgeLabel(inboxUnread)),
                                child: const Icon(Icons.person),
                              ),
                              label: '我的',
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _onTabSelected(int i) {
    _tabIndex.value = i;
    if (i == 1) _aiActivity.value = false;
    if (i == 2) _circleActivity.value = false;
    if (i == 0) {
      _refreshUnread();
      _imKey.currentState?.refreshIfStale();
    }
    if (i == 1) _aiKey.currentState?.refreshIfStale();
    if (i == 2) _circleKey.currentState?.refreshIfStale();
    if (i == 3) {
      _profileKey.currentState?.refreshIfStale();
      _refreshInboxUnread();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _StableTabStack(indexListenable: _tabIndex, children: _tabs),
          ValueListenableBuilder<bool>(
            valueListenable: _wsConnected,
            builder: (context, connected, _) {
              if (connected) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topCenter,
                child: _wsBanner(),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }
}

/// ponytail: 独立 State 监听 tab 切换，避免 Scaffold.build 反复新建 IndexedStack
class _StableTabStack extends StatefulWidget {
  final ValueListenable<int> indexListenable;
  final List<Widget> children;

  const _StableTabStack({required this.indexListenable, required this.children});

  @override
  State<_StableTabStack> createState() => _StableTabStackState();
}

class _StableTabStackState extends State<_StableTabStack> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.indexListenable.value;
    widget.indexListenable.addListener(_onIndex);
  }

  @override
  void didUpdateWidget(covariant _StableTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.indexListenable != widget.indexListenable) {
      oldWidget.indexListenable.removeListener(_onIndex);
      widget.indexListenable.addListener(_onIndex);
      _index = widget.indexListenable.value;
    }
  }

  void _onIndex() {
    final next = widget.indexListenable.value;
    if (next == _index || !mounted) return;
    setState(() => _index = next);
  }

  @override
  void dispose() {
    widget.indexListenable.removeListener(_onIndex);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(index: _index, children: widget.children);
  }
}
