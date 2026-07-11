import 'package:flutter/material.dart';

Widget buildVideoBubbleThumb(String url, {double width = 200, double height = 120}) {
  return Container(
    width: width,
    height: height,
    color: const Color(0xFF2A2A2A),
    child: Icon(Icons.videocam_outlined, size: 40, color: Colors.white.withValues(alpha: 0.22)),
  );
}
