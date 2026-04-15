#!/bin/bash

# エラーが発生したら即座に終了する設定
set -e

echo "--- CANインターフェースの初期化を開始します ---"

# 1. カーネルモジュールのロード
echo "[1/3] Loading kernel modules..."
sudo modprobe can
sudo modprobe peak_usb

# 2. ネットワークデバイスの設定と起動
echo "[2/3] Setting up can0 interface..."
sudo ip link set can0 type can bitrate 500000
sudo ip link set can0 up

# 3. CANメッセージの送信
echo "[3/3] Sending CAN messages..."
sudo cansend can0 601#2B40600006000000
sudo cansend can0 602#2B40600006000000

echo "--- 設定が完了しました ---"