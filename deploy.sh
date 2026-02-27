#!/bin/bash
# Deploy WatchClaw to a physical Apple Watch using a locally stored device ID.
#
# Usage:
#   ./deploy.sh
#   ./deploy.sh --release
#   ./deploy.sh //:WatchClawPhone
#   WATCHCLAW_DEVICE_ID=<id> ./deploy.sh

set -euo pipefail

TARGET="//:WatchClaw"
COMPILATION_MODE=()

for arg in "$@"; do
  case "$arg" in
    --release)
      # Build with full Swift optimizations (-O) instead of debug (-Onone)
      COMPILATION_MODE=(-c opt)
      shift
      ;;
    //*)
      TARGET="$arg"
      shift
      ;;
    *)
      break
      ;;
  esac
done

DEVICE_ID_FILE="${WATCHCLAW_DEVICE_FILE:-$HOME/.config/watchclaw/device_id}"
DEVICE_ID="${WATCHCLAW_DEVICE_ID:-}"

if [[ -z "$DEVICE_ID" && -f "$DEVICE_ID_FILE" ]]; then
  DEVICE_ID="$(tr -d '[:space:]' < "$DEVICE_ID_FILE")"
fi

if [[ -z "$DEVICE_ID" ]]; then
  cat <<EOF
Missing device identifier.

Set one of:
  1) WATCHCLAW_DEVICE_ID environment variable
  2) File: $DEVICE_ID_FILE (single line with the device ID)

Find your device ID with:
  xcrun devicectl list devices
EOF
  exit 1
fi

# Determine CPU and device flag based on target
if [[ "$TARGET" == *"Phone"* ]]; then
  exec bazel run "$TARGET" \
    --ios_multi_cpus=arm64 \
    ${COMPILATION_MODE[@]+"${COMPILATION_MODE[@]}"} \
    "--@rules_apple//apple/build_settings:ios_device=$DEVICE_ID" \
    "$@"
else
  exec bazel run "$TARGET" \
    --watchos_cpus=arm64_32 \
    ${COMPILATION_MODE[@]+"${COMPILATION_MODE[@]}"} \
    "--@rules_apple//apple/build_settings:watchos_device=$DEVICE_ID" \
    "$@"
fi
