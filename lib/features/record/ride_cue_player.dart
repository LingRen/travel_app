import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_repository.dart';
import '../../data/tts/tts_service.dart';
import '../../domain/recording/ride_cue.dart';
import 'ride_cue_text.dart';

/// 骑行提示的播报出口。见设计文档 10.1。
///
/// 抽成接口是为了让记录控制器在测试里换成假实现：播报会真的出声，不该出现在
/// widget 测试里。控制器只负责「判定出该提示了」，怎么念、念不念得出来归这一层。
abstract class RideCuePlayer {
  /// 播报一批提示（可能多条，按顺序念）。
  Future<void> speak(List<RideCue> cues, DistanceUnit unit);

  Future<void> dispose();
}

/// 走系统 TTS 的实现。
///
/// 选语音而不是纯屏内浮层的唯一理由就是**熄屏放口袋**：骑行中用户常常按下电源键
/// 把手机塞进口袋，此时屏内横幅是看不见的，只有声音能把「第 3 公里，均速 21.6」
/// 送到耳朵里。
class TtsRideCuePlayer implements RideCuePlayer {
  TtsRideCuePlayer(this._tts);

  final TtsService _tts;

  @override
  Future<void> speak(List<RideCue> cues, DistanceUnit unit) async {
    for (final RideCue cue in cues) {
      try {
        await _tts.speak(rideCueSpeechText(cue, unit));
      } catch (_) {
        // 语音是尽力而为：设备没装 TTS 引擎、引擎被系统回收、或语言包缺失，
        // 都在这里静默跳过。屏内横幅照常提示，记录本身更不受影响。
        return;
      }
    }
  }

  @override
  Future<void> dispose() => _tts.dispose();
}

/// 提示播报器。抽成 provider 是为了让 widget 测试注入假实现。
final Provider<RideCuePlayer> rideCuePlayerProvider = Provider<RideCuePlayer>(
  (Ref ref) {
    final RideCuePlayer player = TtsRideCuePlayer(SystemTtsService());
    ref.onDispose(player.dispose);
    return player;
  },
);