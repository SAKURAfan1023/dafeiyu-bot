#!/bin/bash
# Run inside the dedicated qq-ai VM after copying config and entrypoint here.
set -euo pipefail
cd "$HOME/qq-runtime"
# Architecture-specific manifests from the upstream multi-arch index.
case "$(uname -m)" in
  x86_64) IMAGE='mlikiowa/napcat-docker@sha256:69c5ca84ec226d658d0d5cd19997c6c89169da3206faa2948c2dc67d669b6406' ;;
  aarch64|arm64) IMAGE='mlikiowa/napcat-docker@sha256:c5a74db0e7ce14dcc42c1ed1facdc8b0a47b29de65afe069c795608c149fa2cb' ;;
  *) echo 'Unsupported CPU architecture' >&2; exit 1 ;;
esac
if [[ "${1:-create}" == pull ]]; then
  sudo docker pull "$IMAGE"
  sudo docker run --rm --network none --entrypoint /bin/sh "$IMAGE" -c \
    'test "$(id -u)" = 0 && id napcat >/dev/null && test -x /opt/QQ/qq && command -v gosu >/dev/null && command -v Xvfb >/dev/null && printf "%s  %s\n" 6801f93e533846cea05f4f531874a0e84371ab2331c5585b57cd7e3b869cf96b /app/NapCat.Shell.zip | sha256sum -c -'
  exit 0
fi
[[ "${1:-create}" == create ]] || { echo 'Usage: qq-container-create.sh [create|pull]' >&2; exit 2; }
if sudo docker container inspect qq-ai >/dev/null 2>&1; then
  echo 'qq-ai already exists; use the lifecycle script to start it.'
  exit 0
fi
# Mounted credentials belong to the container's napcat UID, which may differ from the VM user.
sudo test -s config/webui.json
sudo test -s config/onebot11.json
sudo test -s config/napcat.json
test -s qq-container-entrypoint.sh
mkdir -p plugins
sudo docker pull "$IMAGE"
sudo docker create --name qq-ai --hostname qq-ai-runtime --init \
  --restart=no --memory=2g --cpus=2 --pids-limit=512 \
  --security-opt=no-new-privileges:true \
  -p 127.0.0.1:6099:6099 -p 127.0.0.1:3001:3001 \
  --mount "type=bind,source=$PWD/config,target=/app/napcat/config" \
  --mount "type=bind,source=$PWD/plugins,target=/app/napcat/plugins" \
  --mount "type=bind,source=$PWD/qq-container-entrypoint.sh,target=/qq-entrypoint.sh,readonly" \
  --mount type=volume,source=qq-ai-data,target=/app/.config/QQ \
  --log-driver=local --log-opt max-size=1m --log-opt max-file=2 \
  --entrypoint /bin/bash "$IMAGE" /qq-entrypoint.sh >/dev/null
echo 'QQ container created; automatic replies remain off.'
