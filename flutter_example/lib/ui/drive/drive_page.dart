import 'package:flutter/material.dart';
import '../../api/drive_api.dart';
import '../file_message.dart';
import '../im_media.dart';

/// 我的云盘（Phase 1：列表、上传、文件夹、删除）
class DrivePage extends StatefulWidget {
  const DrivePage({super.key, required this.token, required this.userId});
  final String token;
  final String userId;

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> {
  late final DriveApi _drive;
  String? _folderId;
  String _folderName = '我的云盘';
  List<DriveNode> _nodes = [];
  DriveQuota? _quota;
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _drive = DriveApi(widget.token);
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _drive.listNodes(parentId: _folderId),
        _drive.quota(),
      ]);
      if (!mounted) return;
      setState(() {
        _nodes = results[0] as List<DriveNode>;
        _quota = results[1] as DriveQuota;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  Future<void> _newFolder() async {
    final name = await _promptName('新建文件夹');
    if (name == null || name.isEmpty) return;
    try {
      await _drive.createFolder(name);
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _uploadFile() async {
    if (_uploading) return;
    final picked = await pickFileBytes();
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      await _drive.uploadBytes(
        picked.bytes,
        name: picked.name ?? 'file',
        parentId: _folderId,
      );
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<String?> _promptName(String title, {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
  }

  Future<void> _openNode(DriveNode n) async {
    if (n.nodeType == 'folder') {
      setState(() {
        _folderId = n.nodeId;
        _folderName = n.name;
      });
      await _refresh();
      return;
    }
    if ((n.downloadUrl ?? '').isNotEmpty) {
      // ponytail: Phase 1 仅提示 URL；后续接 in-app 预览
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n.downloadUrl!)));
    }
  }

  Future<void> _onMore(DriveNode n) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      final name = await _promptName('重命名', initial: n.name);
      if (name == null || name.isEmpty) return;
      try {
        await _drive.rename(n.nodeId, name);
        await _refresh();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } else if (action == 'delete') {
      try {
        await _drive.trash(n.nodeId);
        await _refresh();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (_folderId == null) return true;
    setState(() {
      _folderId = null;
      _folderName = '我的云盘';
    });
    await _refresh();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final q = _quota;
    final usedPct = q != null && q.limitBytes > 0 ? q.usedBytes / q.limitBytes : 0.0;
    return PopScope(
      canPop: _folderId == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_folderName),
          actions: [
            IconButton(icon: const Icon(Icons.create_new_folder_outlined), onPressed: _newFolder),
          ],
        ),
        body: Column(
          children: [
            if (q != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已用 ${formatFileSize(q.usedBytes)} / ${formatFileSize(q.limitBytes)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: usedPct.clamp(0, 1)),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _nodes.isEmpty
                      ? const Center(child: Text('空文件夹，点右下角上传'))
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            itemCount: _nodes.length,
                            itemBuilder: (_, i) {
                              final n = _nodes[i];
                              final isFolder = n.nodeType == 'folder';
                              return ListTile(
                                leading: Icon(isFolder ? Icons.folder : fileIconForName(n.name)),
                                title: Text(n.name),
                                subtitle: isFolder ? null : Text(formatFileSize(n.sizeBytes)),
                                onTap: () => _openNode(n),
                                trailing: IconButton(
                                  icon: const Icon(Icons.more_horiz),
                                  onPressed: () => _onMore(n),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
        floatingActionButton: _uploading
            ? const FloatingActionButton(onPressed: null, child: CircularProgressIndicator(color: Colors.white))
            : FloatingActionButton(onPressed: _uploadFile, child: const Icon(Icons.upload_file)),
      ),
    );
  }
}
