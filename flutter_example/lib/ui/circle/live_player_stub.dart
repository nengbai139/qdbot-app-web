import 'package:flutter/material.dart';

class LivePlayer extends StatelessWidget {
  final String url;

  const LivePlayer({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('当前平台不支持直播播放\n$url', textAlign: TextAlign.center));
  }
}
