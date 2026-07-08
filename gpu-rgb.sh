#!/bin/bash
#
# gpu-rgb.sh - GPU utilization reactive RGB lighting for OpenRGB
#
# Maps GPU utilization to a color gradient across all detected RGB devices:
#   0-14%  : Devices off
#   15-40% : Green -> Yellow (red channel ramps up)
#   40-100%: Yellow -> Red   (green channel ramps down)
#
# Polling is dynamic: idle (off) polls every 5s, active scales from 5s
# at 15% down to 1s at 100%, multiplied by POLL_MULTIPLIER.

MODE="Static"
GPU_DEVICE=0
MOBO_DEVICE=1
POLL_MULTIPLIER=1

# How many times to retry GPU detection before giving up.
MAX_RETRIES=3
RETRY_DELAY=15

#
# Manual testing (when not running as a systemd service):
#
#   Run in background, freeing the console:
#       nohup /root/gpu-rgb.sh &
#
#   Bring it back to the foreground:
#       fg
#
#   Stop the backgrounded script:
#       pkill -f gpu-rgb.sh
#       pkill -9 -f gpu-rgb.sh   (force kill if it hangs)
#
#   Check if it's still running:
#       pgrep -f gpu-rgb.sh
#
#   View output (if launched with nohup):
#       tail -f /root/nohup.out
#

# --- GPU detection with retry ---
retry=0
while [ "$retry" -lt "$MAX_RETRIES" ]; do
    if nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i 0 > /dev/null 2>&1; then
        break
    fi
    retry=$((retry + 1))
    if [ "$retry" -lt "$MAX_RETRIES" ]; then
        sleep "$RETRY_DELAY"
    fi
done

# If all retries exhausted, exit quietly so systemd leaves the service dead.
if [ "$retry" -ge "$MAX_RETRIES" ]; then
    exit 0
fi

# --- Main loop ---
PREV_STATE=""

while true; do
    UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i 0 | tr -d ' \n\r')

    if [ "$UTIL" -lt 15 ]; then
        # Off: below 15%, shut down all RGB to save power/avoid distraction
        if [ "$PREV_STATE" != "off" ]; then
            openrgb --device $GPU_DEVICE  --mode off --noautoconnect
            openrgb --device $MOBO_DEVICE --mode off --noautoconnect
            PREV_STATE="off"
        fi
        SLEEP=$((5 * POLL_MULTIPLIER))
    else
        if [ "$UTIL" -le 40 ]; then
            # Green (00FF00) -> Yellow (FFFF00): ramp up red channel
            R=$(( ($UTIL - 15) * 255 / 25 ))
            G=255
            B=0
        else
            # Yellow (FFFF00) -> Red (FF0000): ramp down green channel
            R=255
            G=$(( 255 - ($UTIL - 40) * 255 / 60 ))
            B=0
        fi
        HEX=$(printf "%02X%02X%02X" "$R" "$G" "$B")
        if [ "$PREV_STATE" != "$HEX" ]; then
            openrgb --device $GPU_DEVICE  --mode "$MODE" --color "$HEX" --noautoconnect
            openrgb --device $MOBO_DEVICE --mode "$MODE" --color "$HEX" --noautoconnect
            PREV_STATE="$HEX"
        fi
        # Sleep scales linearly: 1s at 100% -> 5s at 15%
        SLEEP=$(( (1 + (100 - UTIL) * 4 / 100) * POLL_MULTIPLIER ))
    fi

    sleep "$SLEEP"
done
