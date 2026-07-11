import 'package:flutter/material.dart';
import '../../api/user_api.dart';
import '../../session.dart';

String _platformLabel(String p) {
  switch (p) {
    case 'ios':
      return 'iOS';
    case 'android':
      return 'Android';
    case 'web':
      return 'Web';
    case 'pad':
      return '平板';
    default:
      return p.isEmpty ? '未知' : p;
  }
}

class DeviceListPage extends StatefulWidget {
  final String token;

  const DeviceListPage({super.key, required this.token});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  List<AppDeviceInfo> _devices = [];
  String _currentDeviceId = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await SessionStore.loadOrCreateDeviceId();
      final devices = await UserApi(widget.token).getDevices();
      if (mounted) {
        setState(() {
          _currentDeviceId = id;
          _devices = devices;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录设备'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : _devices.isEmpty
                  ? const Center(child: Text('暂无登录设备记录'))
                  : ListView.separated(
                      itemCount: _devices.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) {
                        final d = _devices[i];
                        final current = d.deviceId == _currentDeviceId;
                        return ListTile(
                          leading: Icon(
                            d.platform == 'web' ? Icons.language : Icons.phone_iphone,
                            color: current ? Theme.of(context).colorScheme.primary : null,
                          ),
                          title: Text('${_platformLabel(d.platform)}${current ? '（本机）' : ''}'),
                          subtitle: Text(
                            [
                              if (d.osVersion.isNotEmpty) d.osVersion,
                              if (d.lastLoginAt != null) '最近登录 ${d.lastLoginAt!.toLocal()}'.split('.').first,
                            ].join(' · '),
                          ),
                          trailing: d.pushToken.isNotEmpty
                              ? const Icon(Icons.notifications_active, size: 18, color: Colors.green)
                              : null,
                        );
                      },
                    ),
    );
  }
}
