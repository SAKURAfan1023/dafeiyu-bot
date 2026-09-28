#!/bin/bash
# Lifecycle only. Initial VM/container provisioning is documented separately.
set -euo pipefail
LIMA_BIN="${LIMA_BIN:-$(command -v limactl || true)}"
[[ -n "$LIMA_BIN" ]] || LIMA_BIN="$HOME/.local/qq-runtime/lima/bin/limactl"
if [[ ! -x "$LIMA_BIN" ]]; then
  echo '尚未安装 QQ 独立运行环境，请先完成部署。' >&2
  exit 1
fi
case "${1:-status}" in
  start)
    "$LIMA_BIN" start qq-ai --tty=false --timeout=3m
    "$LIMA_BIN" shell qq-ai sudo docker start qq-ai >/dev/null
    for attempt in {1..30}; do
      if curl --fail --silent --max-time 2 http://127.0.0.1:6099/webui/ >/dev/null; then
        exit 0
      fi
      sleep 1
    done
    echo '容器已请求启动，但管理接口尚未就绪，请检查容器状态。' >&2
    exit 1
    ;;
  stop)
    "$LIMA_BIN" stop qq-ai --tty=false
    ;;
  status)
    "$LIMA_BIN" list qq-ai
    ;;
  *) echo '用法：qq-runtime.sh start|stop|status' >&2; exit 2 ;;
esac
