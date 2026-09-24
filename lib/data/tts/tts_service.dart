import 'package:flutter_tts/flutter_tts.dart';

/// 文本转语音的最薄一层封装。
///
/// 抽成接口是为了让上层（`features/record/ride_cue_player.dart`）可以在测试里
/// 换成假实现——播报是副作用，不能在 widget 测试里真的出声。
abstract class TtsService {
  /// 念一段文本。引擎还没就绪时由实现自己完成初始化。
  Future<void> speak(String text);

  /// 掐掉正在念的内容。
  Future<void> stop();

  Future<void> dispose();
}

/// 走系统 TTS 引擎（Android 上就是系统设置里的「文字转语音」）。
///
/// 不做任何兜底：引擎缺失或出错就抛给调用方，由调用方决定降级方式。语音只是
/// 提示的一个通道，屏内横幅不依赖它。
class SystemTtsService implements TtsService {
  SystemTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  /// 只在首次播报前配置一次：`setLanguage` 会触发引擎加载，每句都设一遍是白费。
  bool _configured = false;

  Future<void> _configure() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(1.0);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    // 不等待念完：等待会把 1Hz 节拍卡住。而是让引擎排队念（队列模式 1 = 追加），
    // 同一拍里判定出来的多条提示才不会被后一条冲掉。
    await _tts.awaitSpeakCompletion(false);
    await _tts.setQueueMode(1);
    _configured = true;
  }

  @override
  Future<void> speak(String text) async {
    if (!_configured) await _configure();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    if (!_configured) return;
    await _tts.stop();
  }

  @override
  Future<void> dispose() async {
    if (!_configured) return;
    await _tts.stop();
  }
}