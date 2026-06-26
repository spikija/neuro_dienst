import 'package:flutter/services.dart';

class FeedbackSoundService {
  static const _channel = MethodChannel('neuro_app/feedback_sound');

  static Future<void> playLogin() async {
    await _play('playLogin');
  }

  static Future<void> playRoleSelected() async {
    await _play('playRoleSelected');
  }

  static Future<void> playSuccess() async {
    await _play('playSuccess');
  }

  static Future<void> _play(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }
}
