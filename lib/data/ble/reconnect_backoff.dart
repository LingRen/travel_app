/// 传感器断线重连的指数退避。见设计文档 11.2：1s → 2s → 4s，上限 30s。
const int kInitialBackoffMs = 1000;

/// 退避上限。
const int kMaxBackoffMs = 30000;

/// 第 [attempt] 次重连（从 0 开始）应等待的毫秒数。
int backoffDelayMs(int attempt) {
  int delay = kInitialBackoffMs;
  for (int i = 0; i < attempt && delay < kMaxBackoffMs; i++) {
    delay *= 2;
  }
  return delay > kMaxBackoffMs ? kMaxBackoffMs : delay;
}
