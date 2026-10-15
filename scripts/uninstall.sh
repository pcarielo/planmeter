#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
destination="$HOME/Applications/PlanMeter.app"
login=()
while (($#)); do
  case "$1" in
    --destination) destination="${2:?Missing destination}"; shift 2 ;;
    --login) login=(--login); shift ;; # Accepted for compatibility; matching item removal is automatic.
    *) echo 'Usage: uninstall.sh [--destination PATH] [--login]' >&2; exit 2 ;;
  esac
done
printf 'Type the exact app path to remove (%s): ' "$destination"
IFS= read -r confirmation
exec "$ROOT/scripts/install.sh" --uninstall --destination "$destination" --confirm-path "$confirmation" ${login[@]+"${login[@]}"}
