#!/usr/bin/env bash
# 本地启动：从被忽略的 config/amap_key.txt 读取高德 Web 服务 Key，
# 以 --dart-define 注入后运行。参数原样传给 flutter run。
set -euo pipefail

cd "$(dirname "$0")/.."

KEY_FILE="config/amap_key.txt"
if [[ ! -f "$KEY_FILE" ]]; then
  echo "缺少 $KEY_FILE。" >&2
  echo "请复制 config/amap_key.example.txt 为 $KEY_FILE 并填入高德 Web 服务 Key。" >&2
  exit 1
fi

KEY="$(tr -d '[:space:]' < "$KEY_FILE")"
if [[ -z "$KEY" || "$KEY" == "YOUR_AMAP_WEB_KEY" ]]; then
  echo "$KEY_FILE 里还没有填入有效的高德 Web 服务 Key。" >&2
  exit 1
fi

exec fvm flutter run --dart-define=AMAP_WEB_KEY="$KEY" "$@"
