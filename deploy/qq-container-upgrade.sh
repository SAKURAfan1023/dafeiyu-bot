#!/bin/bash
# Run inside the qq-ai VM. Stop the bot engine first; never starts automatic replies.
set -euo pipefail
umask 077
cd "$HOME/qq-runtime"
if [[ "${1:-upgrade}" == rollback ]]; then
  BACKUP="${2:?Supply the backup directory printed during upgrade}"
  [[ "$BACKUP" == "$PWD/backups/"* && -s "$BACKUP/old-container" ]] || exit 2
  OLD=$(cat "$BACKUP/old-container")
  [[ "$OLD" =~ ^qq-ai-before-[0-9]{8}-[0-9]{6}$ ]] || exit 2
  sudo docker inspect "$OLD" >/dev/null
  sudo tar -tzf "$BACKUP/qq-data.tar.gz" >/dev/null
  sudo tar -tzf "$BACKUP/config.tar.gz" >/dev/null
  VOLUME=$(sudo docker volume inspect -f '{{.Mountpoint}}' qq-ai-data)
  # Keep the attempted upgrade and its new data as a second recovery point.
  if sudo docker container inspect qq-ai >/dev/null 2>&1; then
    sudo docker stop qq-ai >/dev/null
    sudo docker rename qq-ai "qq-ai-failed-$(date +%Y%m%d-%H%M%S)"
  fi
  sudo tar -czf "$BACKUP/qq-data-after-upgrade.tar.gz" -C "$VOLUME" .
  sudo tar -czf "$BACKUP/config-after-upgrade.tar.gz" config plugins
  sudo find "$VOLUME" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  sudo tar -xzf "$BACKUP/qq-data.tar.gz" -C "$VOLUME"
  sudo rm -rf config plugins
  sudo tar -xzf "$BACKUP/config.tar.gz"
  sudo cp "$BACKUP/entrypoint.sh" qq-container-entrypoint.sh
  sudo docker rename "$OLD" qq-ai
  sudo docker start qq-ai >/dev/null
  echo 'Rollback restored the cold backup; automatic replies remain off.'
  exit 0
fi
[[ "${1:-upgrade}" == upgrade ]] || exit 2
test -s qq-container-create.sh
test -s qq-container-entrypoint.sh
sudo docker inspect qq-ai >/dev/null
# Refuse unfamiliar mounts; backups must cover all writable account/config data.
sudo docker inspect qq-ai | python3 -c '
import json,os,sys
m={x["Destination"]:x for x in json.load(sys.stdin)[0]["Mounts"]}
expected={"/app/napcat/config":os.path.realpath("config"),"/qq-entrypoint.sh":os.path.realpath("qq-container-entrypoint.sh")}
assert all(m.get(k,{}).get("Source")==v for k,v in expected.items()), "Unexpected bind mount"
assert m.get("/app/.config/QQ",{}).get("Name")=="qq-ai-data", "Unexpected account volume"
assert set(m).issubset(set(expected)|{"/app/.config/QQ","/app/napcat/plugins"}), "Unbacked extra mount"
assert "/app/napcat/plugins" not in m or m["/app/napcat/plugins"].get("Source")==os.path.realpath("plugins"), "Unexpected plugin mount"
'
bash qq-container-create.sh pull
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$PWD/backups/$STAMP"
OLD="qq-ai-before-$STAMP"
mkdir -p "$BACKUP" plugins
chmod 700 "$BACKUP"
sudo docker inspect qq-ai > "$BACKUP/container.json"
printf '%s\n' "$OLD" > "$BACKUP/old-container"
sudo cp qq-container-entrypoint.sh "$BACKUP/entrypoint.sh"
sudo docker stop qq-ai >/dev/null
# Preserve the previously non-persistent plugin files before replacing the container.
sudo docker cp qq-ai:/app/napcat/plugins/. plugins/
VOLUME=$(sudo docker volume inspect -f '{{.Mountpoint}}' qq-ai-data)
sudo tar -czf "$BACKUP/qq-data.tar.gz" -C "$VOLUME" .
sudo tar -czf "$BACKUP/config.tar.gz" config plugins
sudo tar -tzf "$BACKUP/qq-data.tar.gz" >/dev/null
sudo tar -tzf "$BACKUP/config.tar.gz" >/dev/null
sudo chmod 600 "$BACKUP/"*
sudo docker rename qq-ai "$OLD"
echo "Cold backup: $BACKUP"
echo "Rollback: bash qq-container-upgrade.sh rollback '$BACKUP'"
if ! bash qq-container-create.sh; then
  echo 'New container creation failed. Old container and backups are retained; run rollback.' >&2
  exit 1
fi
sudo docker start qq-ai >/dev/null
for attempt in {1..45}; do
  if curl --fail --silent --max-time 2 http://127.0.0.1:6099/webui/ >/dev/null; then
    echo 'New management endpoint ready. Verify QQ login, version and OneBot before enabling replies.'
    exit 0
  fi
  sleep 1
done
echo 'New management endpoint unavailable. Inspect state or use the printed rollback command.' >&2
exit 1
