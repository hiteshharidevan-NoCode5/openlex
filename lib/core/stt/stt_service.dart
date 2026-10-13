import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttService {
  static final SttService instance = SttService._init();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;

  SttService._init();

  Future<bool> init() async {
    if (!_isAvailable) {
      _isAvailable = await _speech.initialize();
    }
    return _isAvailable;
  }

  bool get isListening => _speech.isListening;

  Future<void> listen({
    required Function(String recognizedWords) onResult,
    required Function() onDone,
  }) async {
    bool available = await init();
    if (available) {
      await _speech.listen(
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty) {
            onResult(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
      );
    } else {
      onDone();
    }
  }

  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }
}

