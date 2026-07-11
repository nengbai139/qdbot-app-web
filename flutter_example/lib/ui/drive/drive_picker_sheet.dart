import 'package:flutter/material.dart';
import '../../api/drive_api.dart';
import '../../util/media_url.dart';
import '../file_message.dart';

/// 从云盘选择文件（仅 file 类型），用于 IM/AI 附件
Future<DriveNode?> showDrivePickerSheet(
  BuildContext context, {
  required String token,
  required String userId,
}) async {
  return showModalBottomSheet<DriveNode>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _DrivePickerSheet(token: token, userId: userId),
  );
}

class _DrivePickerSheet extends StatefulWidget {
  const _DrivePickerSheet({required this.token, required this.userId});
  final String token;
  final String userId;

  @override
  State<_DrivePickerSheet> createState() => _DrivePickerSheetState();
}

class _DrivePickerSheetState extends State<_DrivePickerSheet> {
  late final DriveApi _drive;
  String? _folderId;
  final _stack = <String?>[];
  List<DriveNode> _nodes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _drive = DriveApi(widget.token);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final nodes = await _drive.listNodes(parentId: _folderId);
      if (mounted) setState(() {
        _nodes = nodes;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _enterFolder(DriveNode n) {
    _stack.add(_folderId);
    _folderId = n.nodeId;
    _load();
  }

  void _goBack() {
    if (_stack.isEmpty) return;
    setState(() => _folderId = _stack.removeLast());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.65;
    return SizedBox(
      height: h,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                if (_stack.isNotEmpty)
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack),
                const Expanded(
                  child: Text('从云盘选择', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _nodes.isEmpty
                    ? const Center(child: Text('暂无文件'))
                    : ListView.builder(
                        itemCount: _nodes.length,
                        itemBuilder: (_, i) {
                          final n = _nodes[i];
                          final isFolder = n.nodeType == 'folder';
                          return ListTile(
                            leading: Icon(isFolder ? Icons.folder_outlined : fileIconForName(n.name)),
                            title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: isFolder
                                ? null
                                : Text(formatFileSize(n.sizeBytes), style: const TextStyle(fontSize: 12)),
                            onTap: () {
                              if (isFolder) {
                                _enterFolder(n);
                              } else if ((n.downloadUrl ?? '').isNotEmpty) {
                                Navigator.pop(context, n);
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// 将云盘文件编码为 IM file 消息体
String encodeDriveFileMessage(DriveNode node) => encodeFileMessage(
      url: publicMediaUrl(node.downloadUrl ?? ''),
      name: node.name,
      size: node.sizeBytes,
      driveNodeId: node.nodeId,
    );
