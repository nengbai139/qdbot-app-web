import 'package:flutter/material.dart';

class CircleVodPlayer extends StatelessWidget {
  final String url;
  final String posterUrl;
  final bool active;
  final bool playing;

  const CircleVodPlayer({
    super.key,
    required this.url,
    this.posterUrl = '',
    this.active = false,
    this.playing = true,
  });

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Colors.black12);
  }
}
