#!/bin/bash
# Use the upstream image's QQ and NapCat, without its environment-masking setup.
set -euo pipefail
cd /app
unzip -oq NapCat.Shell.zip -d /tmp/napcat-release
shopt -s dotglob nullglob
for item in /tmp/napcat-release/*; do
    [[ "$(basename "$item")" == config ]] || cp -a "$item" /app/napcat/
done
# Runtime configuration is mounted separately, not replaced by release defaults.
export NAPCAT_WORKDIR=/app/napcat
export NAPCAT_DISABLE_BYPASS=1
export DISPLAY=:1
export FFMPEG_PATH=/usr/bin/ffmpeg
chown -R napcat:napcat /app/napcat /app/.config/QQ
chown napcat:napcat /app /app/.config
# A stopped container retains /tmp, but the previous X server is gone.
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
gosu napcat Xvfb :1 -screen 0 1080x760x16 +extension GLX +render >/dev/null 2>&1 &
sleep 2
cd /app/napcat
exec gosu napcat /opt/QQ/qq --no-sandbox
