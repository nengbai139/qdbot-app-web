import 'package:flutter/material.dart';

import '../../../api/user_api.dart';
import '../../../util/media_url.dart';

/// 微信朋友圈顶栏：封面 + 右下角头像昵称 + 相机发动态
class MomentsWxHeader extends StatelessWidget {
  final UserProfile? profile;
  final VoidCallback onCompose;
  final VoidCallback? onBack;

  const MomentsWxHeader({
    super.key,
    required this.profile,
    required this.onCompose,
    this.onBack,
  });

  static const _coverHeight = 280.0;
  static const _wxLink = Color(0xFF576B95);

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? '我';
    final avatar = publicMediaUrl(profile?.avatarUrl ?? '');
    return SizedBox(
      height: _coverHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF3A4F6B),
                  const Color(0xFF576B95).withValues(alpha: 0.85),
                  const Color(0xFF8FA8C8).withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
          if (onBack != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              left: 4,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              ),
            ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            right: 8,
            child: IconButton(
              onPressed: onCompose,
              tooltip: '发表',
              icon: const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 26),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: avatar.isNotEmpty
                        ? Image.network(avatar, width: 64, height: 64, fit: BoxFit.cover)
                        : Container(
                            width: 64,
                            height: 64,
                            color: _wxLink.withValues(alpha: 0.3),
                            alignment: Alignment.center,
                            child: Text(
                              name.isNotEmpty ? name[0] : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
