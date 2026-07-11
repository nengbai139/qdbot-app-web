import 'package:flutter/material.dart';

import '../circle_models.dart';
import 'circle_ui.dart';

class MeetingCaptionOverlay extends StatelessWidget {
  const MeetingCaptionOverlay({
    super.key,
    required this.lines,
    this.translations = const {},
  });

  final List<LiveCaption> lines;
  final Map<String, String> translations;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final visible = lines.length > 3 ? lines.sublist(lines.length - 3) : lines;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 16,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: visible.map((c) {
            final tr = translations[c.captionId];
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kMeetingAccent.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.speakerName.isNotEmpty)
                    Text(
                      c.speakerName,
                      style: TextStyle(color: kMeetingAccent.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  Text(
                    c.text,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: c.isFinal ? 0.95 : 0.65),
                      fontSize: 15,
                      height: 1.35,
                      fontStyle: c.isFinal ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                  if (tr != null && tr.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(tr, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.3)),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
