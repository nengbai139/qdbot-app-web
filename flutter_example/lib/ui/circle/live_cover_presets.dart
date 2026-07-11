import '../../config.dart';

class LiveCoverPreset {
  final String id;
  final String label;
  final String file;

  const LiveCoverPreset({required this.id, required this.label, required this.file});

  String get url => '${AppConfig.baseUrl}/app_web/covers/$file';
}

/// 内置直播背景（随 Web 包发布在 /app_web/covers/）
const liveCoverPresets = [
  LiveCoverPreset(id: 'ocean', label: '大海', file: 'ocean.jpg'),
  LiveCoverPreset(id: 'sky', label: '蓝天', file: 'sky.jpg'),
  LiveCoverPreset(id: 'sunset', label: '日落', file: 'sunset.jpg'),
  LiveCoverPreset(id: 'stars', label: '星空', file: 'stars.jpg'),
  LiveCoverPreset(id: 'city', label: '城市', file: 'city.jpg'),
  LiveCoverPreset(id: 'forest', label: '森林', file: 'forest.jpg'),
];
