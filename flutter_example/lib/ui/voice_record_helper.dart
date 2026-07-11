import 'package:record/record.dart';

class VoiceRecordFormat {
  final RecordConfig config;
  final String extension;

  const VoiceRecordFormat({required this.config, required this.extension});
}

/// 按平台能力选编码：Web 上 Chrome 常不支持 AAC，需回退 opus/wav
Future<VoiceRecordFormat?> pickVoiceRecordFormat(AudioRecorder recorder) async {
  const candidates = <(AudioEncoder, String)>[
    (AudioEncoder.aacLc, 'm4a'),
    (AudioEncoder.opus, 'webm'),
    (AudioEncoder.wav, 'wav'),
  ];
  for (final (encoder, ext) in candidates) {
    try {
      if (await recorder.isEncoderSupported(encoder)) {
        return VoiceRecordFormat(
          config: RecordConfig(encoder: encoder, bitRate: 128000),
          extension: ext,
        );
      }
    } catch (_) {}
  }
  return null;
}
