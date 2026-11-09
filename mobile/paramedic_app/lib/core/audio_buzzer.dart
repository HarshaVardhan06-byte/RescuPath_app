import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_buzzer_stub.dart'
    if (dart.library.js_interop) 'audio_buzzer_web.dart';

class AudioBuzzer {
  static Future<void> playAlert() async {
    if (kIsWeb) {
      try {
        playWebChime();
      } catch (_) {}
    }

    try {
      unawaited(SystemSound.play(SystemSoundType.alert));
      unawaited(HapticFeedback.vibrate());
    } catch (_) {}
  }

  static Future<void> playAcknowledgeReceived() async {
    // Distinctive acknowledgement confirmation buzzer
    if (kIsWeb) {
      try {
        playWebChime();
      } catch (_) {}
    }

    try {
      unawaited(SystemSound.play(SystemSoundType.alert));
      unawaited(HapticFeedback.heavyImpact());
    } catch (_) {}
  }
}
