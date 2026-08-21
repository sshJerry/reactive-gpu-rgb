# gpu-rgb

GPU utilization reactive RGB lighting via OpenRGB. Maps NVIDIA GPU load
to a smooth color gradient (green → yellow → red) across all OpenRGB
devices. Designed for headless Proxmox/Debian hosts.

## Prerequisites

- NVIDIA GPU with `nvidia-smi`
- [OpenRGB](https://openrgb.org) installed (`openrgb` available on PATH)
- Access to RGB controllers (i2c-dev and related kernel modules loaded).
  No OpenRGB server or daemon is needed: each CLI call drives the
  hardware directly. The script verifies at startup that openrgb can
  enumerate devices, retrying 3 times spaced 15s apart before exiting.

## Behavior notes

- A transient `nvidia-smi` failure (driver reload, GPU reset) keeps the
  last LED state and retries after the idle poll interval.
- All devices are updated with a single OpenRGB client call. Concurrent
  openrgb processes segfault from colliding on direct hardware access,
  so updates stay serialized. A failed update is retried on the next poll.

## Install

```bash
# Deploy script
sudo cp gpu-rgb.sh /root/gpu-rgb.sh
sudo chmod +x /root/gpu-rgb.sh

# Install and start service
sudo cp gpu-rgb.service /etc/systemd/system/gpu-rgb.service
sudo systemctl daemon-reload
sudo systemctl enable --now gpu-rgb
```

## Manage

```bash
systemctl status gpu-rgb    # check status
systemctl stop gpu-rgb      # stop
systemctl start gpu-rgb     # start
journalctl -u gpu-rgb -f    # follow logs
```

## Manual test

```bash
nohup /root/gpu-rgb.sh &    # run in background
fg                           # bring to foreground
pkill -f gpu-rgb.sh          # stop
```
