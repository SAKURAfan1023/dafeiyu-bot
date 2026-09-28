#!/bin/bash
# Run inside the dedicated qq-ai VM after copying config and entrypoint here.
set -euo pipefail
cd "$HOME/qq-runtime"
# Architecture-specific manifests from the upstream multi-arch index.
case "$(uname -m)" in
  x86_64) IMAGE='mlikiowa/napcat-docker@sha256:41b1a8e10953065f4796ab19c0c8760cd3175376be976c5480710d29a77357ee' ;;
  aarch64|arm64) IMAGE='mlikiowa/napcat-docker@sha256:fbb892ec4bf3f922e0df79e65fe1192ddc55be638474819aeedb0a619bbe3ba5' ;;
  *) echo 'Unsupported CPU architecture' >&2; exit 1 ;;
esac
if sudo docker container inspect qq-ai >/dev/null 2>&1; then
  echo 'qq-ai already exists; use the lifecycle script to start it.'
  exit 0
fi
test -s config/webui.json
test -s config/onebot11.json
test -s config/napcat.json
test -s qq-container-entrypoint.sh
sudo docker pull "$IMAGE"
sudo docker create --name qq-ai --hostname qq-ai-runtime --init \
  --restart=no --memory=2g --cpus=2 --pids-limit=512 \
  --security-opt=no-new-privileges:true \
  -p 127.0.0.1:6099:6099 -p 127.0.0.1:3001:3001 \
  --mount "type=bind,source=$PWD/config,target=/app/napcat/config" \
  --mount "type=bind,source=$PWD/qq-container-entrypoint.sh,target=/qq-entrypoint.sh,readonly" \
  --mount type=volume,source=qq-ai-data,target=/app/.config/QQ \
  --log-driver=local --log-opt max-size=1m --log-opt max-file=2 \
  --entrypoint /bin/bash "$IMAGE" /qq-entrypoint.sh >/dev/null
echo 'QQ container created; automatic replies remain off.'
