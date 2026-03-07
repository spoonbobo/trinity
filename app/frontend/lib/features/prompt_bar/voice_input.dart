import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceInputController extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  String _transcript = '';

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;
  String get transcript => _transcript;

  Future<void> initialize() async {
    _isAvailable = await _speech.initialize(
      onError: (error) {
        _isListening = false;
        notifyListeners();
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          notifyListeners();
        }
      },
    );
    notifyListeners();
  }

  void startListening({required void Function(String) onResult}) {
    if (!_isAvailable || _isListening) return;
    _isListening = true;
    _transcript = '';
    notifyListeners();

    _speech.listen(
      onResult: (result) {
        _transcript = result.recognizedWords;
        notifyListeners();
        if (result.finalResult) {
          _isListening = false;
          notifyListeners();
          onResult(_transcript);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenMode: stt.ListenMode.dictation,
    );
  }

  void stopListening() {
    _speech.stop();
    _isListening = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }
}
