import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService instance = TtsService._init();
  final FlutterTts _tts = FlutterTts();

  TtsService._init() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await _tts.stop();
      await _tts.speak(text);
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}

