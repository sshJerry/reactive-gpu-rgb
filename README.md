# gpu-rgb

GPU utilization reactive RGB lighting via OpenRGB. Maps NVIDIA GPU load
to a smooth color gradient (green → yellow → red) across all OpenRGB
devices. Designed for headless Proxmox/Debian hosts.

## Prerequisites

- NVIDIA GPU with `nvidia-smi`
- [OpenRGB](https://openrgb.org) installed (`openrgb` available on PATH)

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
