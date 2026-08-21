#!/bin/bash
#
# gpu-rgb.sh - GPU utilization reactive RGB lighting for OpenRGB
#
# Maps GPU utilization to a color gradient across all detected RGB devices:
#   0-14%  : Devices off
#   15-40% : Green -> Yellow (red channel ramps up)
#   40-100%: Yellow -> Red   (green channel ramps down)
#
# Polling is dynamic: idle (off) polls every 5s, active scales from 4s
# at 15% down to 1s at 100% (integer math), multiplied by POLL_MULTIPLIER.
# Updates use one OpenRGB client call targeting all devices: concurrent
# openrgb processes collide on direct hardware access and segfault, and
# sequential per-device calls cascade slowly across devices.

MODE="Static"
# Every detected device is targeted by omitting --device. Devices on this
# host, in order from `openrgb -l`:
#   0-3 : ENE DRAM (4 DIMMs)
#   4   : ASUS ROG STRIX RTX 3090 (GPU)
#   5   : ASUS PRIME X570-PRO (Motherboard)
# Note: a device OpenRGB detects in the future would also be included.
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

# --- OpenRGB availability check with retry ---
# openrgb drives RGB controllers directly; no server/daemon is needed on
# this host. This probe verifies openrgb can enumerate devices (e.g. i2c
# access works) before entering the main loop.
retry=0
while [ "$retry" -lt "$MAX_RETRIES" ]; do
    if openrgb --list-devices --noautoconnect > /dev/null 2>&1; then
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

    # A transient query failure (driver reload, GPU reset) returns empty or
    # non-numeric output. Keep the last LED state and retry after the idle
    # interval instead of flashing garbage colors or spinning in a tight loop.
    if ! [[ "$UTIL" =~ ^[0-9]+$ ]]; then
        sleep $((5 * POLL_MULTIPLIER))
        continue
    fi

    if [ "$UTIL" -lt 15 ]; then
        # Off: below 15%, shut down all RGB to save power/avoid distraction
        if [ "$PREV_STATE" != "off" ]; then
            # One call, all devices. On failure leave PREV_STATE unset so
            # the next poll retries the update.
            if openrgb --mode off --noautoconnect; then
                PREV_STATE="off"
            else
                PREV_STATE=""
            fi
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
            if openrgb --mode "$MODE" --color "$HEX" --noautoconnect; then
                PREV_STATE="$HEX"
            else
                PREV_STATE=""
            fi
        fi
        # Sleep scales linearly: 1s at 100% -> 5s at 15%
        SLEEP=$(( (1 + (100 - UTIL) * 4 / 100) * POLL_MULTIPLIER ))
    fi

    sleep "$SLEEP"
done
