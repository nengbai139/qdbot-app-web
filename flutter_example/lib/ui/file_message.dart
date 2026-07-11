import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_theme.dart';

class FileAttachment {
  final String url;
  final String name;
  final int size;

  const FileAttachment({required this.url, required this.name, this.size = 0});
}

FileAttachment? tryParseFileMessage(String content, {String contentType = 'text'}) {
  if (contentType != 'file') return null;
  try {
    final j = jsonDecode(content);
    if (j is Map) {
      return FileAttachment(
        url: (j['url'] ?? '').toString(),
        name: (j['name'] ?? '文件').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
      );
    }
  } catch (_) {}
  if (content.startsWith('http')) {
    final uri = Uri.tryParse(content);
    final name = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '文件';
    return FileAttachment(url: content, name: name);
  }
  if (content.isNotEmpty) return FileAttachment(url: '', name: content);
  return null;
}

String encodeFileMessage({required String url, required String name, int size = 0, String? driveNodeId}) {
  final m = <String, dynamic>{'url': url, 'name': name, 'size': size};
  if (driveNodeId != null && driveNodeId.isNotEmpty) m['driveNodeId'] = driveNodeId;
  return jsonEncode(m);
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

IconData fileIconForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description_outlined;
  if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart_outlined;
  if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Icons.slideshow_outlined;
  if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) return Icons.folder_zip_outlined;
  return Icons.insert_drive_file_outlined;
}

class FileMessageBubble extends StatelessWidget {
  final FileAttachment file;
  final bool isMe;
  final VoidCallback? onTap;

  const FileMessageBubble({super.key, required this.file, required this.isMe, this.onTap});

  @override
  Widget build(BuildContext context) {
    final sizeLabel = formatFileSize(file.size);
    return Material(
      color: isMe ? AppTheme.brandBlue : AppTheme.bubbleOtherFor(Theme.of(context).brightness),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(fileIconForName(file.name), color: isMe ? Colors.white : AppTheme.brandBlue, size: 28),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (sizeLabel.isNotEmpty)
                      Text(
                        sizeLabel,
                        style: TextStyle(color: isMe ? Colors.white70 : Colors.grey.shade600, fontSize: 11),
                      ),
                  ],
                ),
              ),
              Icon(Icons.download_rounded, size: 18, color: isMe ? Colors.white70 : Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}
