import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../api/user_api.dart';
import '../../session.dart';
import '../../ws/app_ws.dart';
import '../../util/home_bootstrap.dart';
import '../../util/tab_data_cache.dart';
import '../../util/push_register.dart';
import '../../util/media_url.dart';
import '../app_theme.dart';
import '../login_page.dart';
import '../circle/circle_notify_page.dart';
import '../circle/live_host_page.dart';
import '../circle/live_earnings_page.dart';
import '../circle/user_circle_page.dart';
import 'qd_wallet_page.dart';
import 'about_page.dart';
import 'device_list_page.dart';
import 'digital_twin_page.dart';
import 'notification_inbox_page.dart';
import 'notification_settings_page.dart';
import 'profile_edit_page.dart';
import 'payment/payment_hub_page.dart';
import 'security_settings_page.dart';
import 'chat_prefs_page.dart';
import 'privacy_settings_page.dart';
import 'profile_section.dart';
import '../premium/user_code_display.dart';
import '../premium/my_premium_code_page.dart';
import '../user_skills_page.dart';
import '../drive/drive_page.dart';

class ProfileTab extends StatefulWidget {
  final String token;
  final String userId;
  final String displayId;
  final int inboxUnread;
  final ValueListenable<int>? inboxUnreadListenable;
  final VoidCallback? onInboxChanged;

  const ProfileTab({
    super.key,
    required this.token,
    required this.userId,
    this.displayId = '',
    this.inboxUnread = 0,
    this.inboxUnreadListenable,
    this.onInboxChanged,
  });

  @override
  State<ProfileTab> createState() => ProfileTabState();
}

class ProfileTabState extends State<ProfileTab> {
  UserProfile? _profile;
  bool _loading = true;
  DateTime? _lastFetch;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (!TabDataCache.hasProfile) await TabDataCache.restore(widget.token);
    if (!mounted) return;
    if (TabDataCache.hasProfile) {
      setState(() {
        _profile = TabDataCache.profile;
        _loading = false;
      });
      _lastFetch = DateTime.now();
      _loadProfile(silent: true);
    } else {
      _loadProfile();
    }
  }

  void refreshIfStale({Duration maxAge = const Duration(seconds: 60)}) {
    final now = DateTime.now();
    if (_lastFetch != null && now.difference(_lastFetch!) < maxAge) return;
    _loadProfile(silent: _profile != null);
  }

  Future<void> refreshPrefs() => _loadProfile(silent: _profile != null);

  Future<void> _loadProfile({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && _profile == null) setState(() => _loading = true);
    try {
      final p = await UserApi(widget.token).getProfile();
      if (mounted) setState(() {
        _profile = p;
        _loading = false;
      });
      TabDataCache.putProfile(p);
      _lastFetch = DateTime.now();
    } catch (_) {
      if (mounted) {
        setState(() {
          if (_profile == null) _profile = UserProfile(userId: widget.userId);
          _loading = false;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  String get _userCode {
    final fromProfile = _profile?.userCode ?? '';
    if (fromProfile.isNotEmpty) return fromProfile;
    return widget.displayId.isNotEmpty ? widget.displayId : widget.userId;
  }

  String get _levelName => _profile?.levelName ?? '';

  String get _displayName {
    final n = _profile?.nickname ?? '';
    if (n.isNotEmpty) return n;
    return _userCode;
  }

  Future<void> _openEdit() async {
    final initial = _profile ?? UserProfile(userId: widget.userId);
    await Navigator.push<UserProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileEditPage(token: widget.token, userId: widget.userId, initial: initial),
      ),
    );
    if (mounted) await _loadProfile();
  }

  void _openChatPrefs() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatPrefsPage()));
  }

  void _openPrivacy() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySettingsPage()));
  }

  void _openPay() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentHubPage(
          token: widget.token,
          userId: widget.userId,
          currentUserCode: _userCode,
        ),
      ),
    );
  }

  Widget _inboxListTile() {
    Widget tile(int unread) {
      return ListTile(
        leading: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: const Icon(Icons.inbox_outlined),
        ),
        title: const Text('通知中心'),
        subtitle: Text(unread > 0 ? '$unread 条未读 · 点击进入会话' : '有未读时按会话汇总'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationInboxPage(
                token: widget.token,
                userId: widget.userId,
                userCode: _userCode,
              ),
            ),
          );
          widget.onInboxChanged?.call();
        },
      );
    }

    final listenable = widget.inboxUnreadListenable;
    if (listenable == null) return tile(widget.inboxUnread);
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (_, unread, __) => tile(unread),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: _loading && _profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _ProfileCard(
                  name: _displayName,
                  userCode: _userCode,
                  levelName: _levelName,
                  avatarUrl: _profile?.avatarUrl ?? '',
                  tenantId: _profile?.tenantId ?? '',
                  onTap: _openEdit,
                ),
                const SizedBox(height: 16),
                _QuickGrid(
                  onPay: _openPay,
                  onTwin: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DigitalTwinPage(token: widget.token, userId: widget.userId)),
                  ),
                  onNotify: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => NotificationSettingsPage(token: widget.token)),
                  ),
                  onDevices: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DeviceListPage(token: widget.token)),
                  ),
                ),
                ProfileSection(
                  title: '存储',
                  children: [
                    ListTile(
                      leading: Icon(Icons.cloud_outlined, color: AppTheme.brandBlue.withValues(alpha: 0.9)),
                      title: const Text('我的云盘'),
                      subtitle: const Text('文件、图片、视频统一管理'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DrivePage(token: widget.token, userId: widget.userId),
                        ),
                      ),
                    ),
                  ],
                ),
                ProfileSection(
                  title: '账号',
                  children: [
                    ListTile(
                      leading: Icon(Icons.diamond_outlined, color: Colors.amber.shade800),
                      title: const Text('我的靓号'),
                      subtitle: Text(_userCode.isNotEmpty ? '$_userCode${_levelName.isNotEmpty && _levelName != '普通' ? ' · $_levelName' : ''}' : '展示码与分享'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyPremiumCodePage(
                            token: widget.token,
                            userId: widget.userId,
                            fallbackUserCode: _userCode,
                          ),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('账号与安全'),
                      subtitle: Text(_profile?.email.isNotEmpty == true ? _profile!.email : '密码、展示码、设备'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SecuritySettingsPage(
                            token: widget.token,
                            userId: widget.userId,
                            userCode: _userCode,
                            email: _profile?.email ?? '',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ProfileSection(
                  title: 'AI 助手',
                  children: [
                    ListTile(
                      leading: Icon(Icons.psychology_outlined, color: Colors.deepPurple.shade400),
                      title: const Text('专有 Skill'),
                      subtitle: const Text('创建与管理专有指令；在助手输入框左侧图标选用'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserSkillsPage(
                            token: widget.token,
                            userId: widget.userId,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ProfileSection(
                  title: '圈子',
                  children: [
                    ListTile(
                      leading: Icon(Icons.account_circle_outlined, color: AppTheme.brandBlue.withValues(alpha: 0.9)),
                      title: const Text('我的圈子'),
                      subtitle: const Text('查看我发布的动态与视频'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserCirclePage(
                            token: widget.token,
                            viewerId: widget.userId,
                            authorId: widget.userId,
                            authorName: _displayName,
                            authorCode: _userCode,
                            authorAvatar: publicMediaUrl(_profile?.avatarUrl ?? ''),
                          ),
                        ),
                      ),
                    ),
                    const ProfileDivider(),
                    ListTile(
                      leading: Icon(Icons.groups_outlined, color: AppTheme.brandBlue.withValues(alpha: 0.9)),
                      title: const Text('圈子通知'),
                      subtitle: const Text('点赞、评论、开播提醒'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CircleNotifyPage(token: widget.token, userId: widget.userId),
                        ),
                      ),
                    ),
                    const ProfileDivider(),
                    ListTile(
                      leading: Icon(Icons.sensors, color: const Color(0xFFE5484D).withValues(alpha: 0.9)),
                      title: const Text('我要开播'),
                      subtitle: const Text('创建直播间 · OBS 推流'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveHostPage(token: widget.token, userId: widget.userId),
                        ),
                      ),
                    ),
                    const ProfileDivider(),
                    ListTile(
                      leading: Icon(Icons.account_balance_wallet_outlined, color: AppTheme.brandBlue.withValues(alpha: 0.9)),
                      title: const Text('QD币钱包'),
                      subtitle: const Text('充值 · 直播礼物消费'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QdWalletPage(token: widget.token, userId: widget.userId),
                        ),
                      ),
                    ),
                    const ProfileDivider(),
                    ListTile(
                      leading: Icon(Icons.monetization_on_outlined, color: const Color(0xFFE5484D).withValues(alpha: 0.85)),
                      title: const Text('直播收益'),
                      subtitle: const Text('累计打赏 · 按场次明细'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LiveEarningsPage(token: widget.token, userId: widget.userId),
                        ),
                      ),
                    ),
                  ],
                ),
                ProfileSection(
                  title: '偏好',
                  children: [
                    _inboxListTile(),
                    const ProfileDivider(),
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('消息通知'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => NotificationSettingsPage(token: widget.token)),
                      ),
                    ),
                    const ProfileDivider(),
                    ListTile(
                      leading: const Icon(Icons.chat_outlined),
                      title: const Text('聊天偏好'),
                      subtitle: const Text('主题、回车发送、已读状态'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openChatPrefs,
                    ),
                    const ProfileDivider(),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('隐私'),
                      subtitle: const Text('搜索可见性与会话管理'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openPrivacy,
                    ),
                  ],
                ),
                ProfileSection(
                  title: '其他',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('关于'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AboutPage(
                            token: widget.token,
                            userId: widget.userId,
                            userCode: _userCode,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await unregisterPush(authToken: widget.token, userId: widget.userId);
                      AppWs.stop();
                      await HomeBootstrap.reset();
                      TabDataCache.clear();
                      await SessionStore.clear();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                        (_) => false,
                      );
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('退出登录'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String userCode;
  final String levelName;
  final String avatarUrl;
  final String tenantId;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.name,
    required this.userCode,
    this.levelName = '',
    required this.avatarUrl,
    required this.tenantId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                key: ValueKey(avatarUrl),
                radius: 32,
                backgroundColor: AppTheme.brandBlue.withValues(alpha: 0.12),
                backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(publicMediaUrl(avatarUrl)) : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(fontSize: 24, color: AppTheme.brandBlue, fontWeight: FontWeight.w600),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    if (userCode.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      UserCodeRow(userCode: userCode, levelName: levelName),
                    ],
                    if (tenantId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('租户 $tenantId', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              Icon(Icons.edit_outlined, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  final VoidCallback onPay;
  final VoidCallback onTwin;
  final VoidCallback onNotify;
  final VoidCallback onDevices;

  const _QuickGrid({
    required this.onPay,
    required this.onTwin,
    required this.onNotify,
    required this.onDevices,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _QuickItem(icon: Icons.payment_outlined, label: '支付', onTap: onPay),
              _QuickItem(icon: Icons.smart_toy_outlined, label: '数字分身', onTap: onTwin),
              _QuickItem(icon: Icons.notifications_outlined, label: '通知', onTap: onNotify),
              _QuickItem(icon: Icons.devices_outlined, label: '设备', onTap: onDevices),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _QuickItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppTheme.brandBlue : Colors.grey.shade400;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: enabled ? Colors.black87 : Colors.grey)),
          ],
        ),
      ),
    );
  }
}
