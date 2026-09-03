#!/usr/bin/env bash
# monitor.sh - Live thermal + fan monitor for the GL73 8SE.
# Usage: ./monitor.sh [seconds]   (default: 5 readings, 2s apart)
# Requires root for isw -r (EC reads).
set -uo pipefail

N="${1:-5}"
for i in $(seq 1 "$N"); do
  printf '\n--- %s ---\n' "$(date +%H:%M:%S)"
  for z in /sys/class/thermal/thermal_zone*; do
    printf '  %-14s %3d C\n' "$(cat "$z/type")" "$(( $(cat "$z/temp") / 1000 ))"
  done
  printf '  nvidia-smi: '; nvidia-smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader 2>/dev/null || echo "n/a"
  echo "  EC (isw):"
  sudo isw -r 1 2>/dev/null | tail -3
  sleep 2
done