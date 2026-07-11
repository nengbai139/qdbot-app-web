import 'package:flutter/material.dart';
import '../../api/upload_api.dart';
import '../../api/user_api.dart';
import '../../util/media_url.dart';
import '../im_media.dart';

class ProfileEditPage extends StatefulWidget {
  final String token;
  final String userId;
  final UserProfile initial;

  const ProfileEditPage({
    super.key,
    required this.token,
    required this.userId,
    required this.initial,
  });

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final TextEditingController _nickname;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  String _avatarUrl = '';
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.initial.nickname);
    _email = TextEditingController(text: widget.initial.email);
    _phone = TextEditingController(text: widget.initial.phone);
    _avatarUrl = widget.initial.avatarUrl;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    setState(() => _uploading = true);
    try {
      final picked = await pickImageBytes();
      if (picked == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未选择图片')));
        }
        return;
      }
      final url = await UploadApi(widget.token).uploadAvatarBytes(
        picked.bytes,
        userId: widget.userId,
        filename: picked.name,
      );
      await UserApi(widget.token).updateSettings(
        nickname: _nickname.text.trim(),
        avatarUrl: url,
        email: _email.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('头像已更新')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await UserApi(widget.token).updateSettings(
        nickname: _nickname.text.trim(),
        avatarUrl: _avatarUrl,
        email: _email.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, UserProfile(
        userId: widget.userId,
        nickname: _nickname.text.trim(),
        avatarUrl: _avatarUrl,
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        tenantId: widget.initial.tenantId,
        workspaceId: widget.initial.workspaceId,
        platform: widget.initial.platform,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _nickname.text.isNotEmpty ? _nickname.text : widget.userId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑资料'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  key: ValueKey(_avatarUrl),
                  radius: 44,
                  backgroundImage: _avatarUrl.isNotEmpty ? NetworkImage(publicMediaUrl(_avatarUrl)) : null,
                  child: _avatarUrl.isEmpty
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 32))
                      : null,
                ),
                if (_uploading)
                  const Positioned.fill(child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _uploading ? null : _pickAvatar,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('更换头像'),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nickname,
            decoration: const InputDecoration(labelText: '昵称', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '邮箱', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '手机', border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }
}
