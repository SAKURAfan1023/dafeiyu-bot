#!/bin/bash
set -euo pipefail
exec bash "$(dirname "$0")/setup-social.sh" "$@"
