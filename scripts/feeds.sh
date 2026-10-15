#!/bin/bash
# 挂载第三方 feeds：QModem 模组管理后端 + 通用模组管理界面
#
# 用法：bash scripts/feeds.sh <源码目录>
set -euo pipefail

WRT_DIR="${1:?用法: feeds.sh <源码目录>}"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
FEED_SRC="$WORKSPACE/_feeds"

mkdir -p "$FEED_SRC"

# ---- QModem 后端 ----
# 仓库结构是 application/* 与 luci/*，直接 src-git 会扫不到包，
# 所以 clone 到本地再用 src-link 注册为本地 feed。
if [ ! -d "$FEED_SRC/qmodem" ]; then
  git clone --depth=1 --single-branch --branch main \
    https://github.com/FUjr/QModem.git "$FEED_SRC/qmodem"
fi

# ---- 通用模组管理界面 ----
# 自带 extra_modem_support.json（含 Quectel RG520N-CN），
# 安装/开机时自动幂等注入 QModem 支持库，免手工改 modem_support.json。
if [ ! -d "$FEED_SRC/qmodem-generic" ]; then
  git clone --depth=1 --single-branch --branch main \
    https://github.com/LianXia233/luci-app-qmodem-generic.git "$FEED_SRC/qmodem-generic"
fi

# ---- apk 版本号合法性修正（否则整个固件构建会被阻断）----
# OpenWrt 新版 apk 打包器不接受 `X.Y.Z-rc.N`：版本串被拼成 `3.4.0-rc.3-rN` 后
# apk mkpkg 报 "package version is invalid" (Error 99)，构建全灭。
# 改写成 apk 合法的 `X.Y.Z_rcN`；只影响包版本元数据。上游修好后自动跳过。
VER_FILE="$FEED_SRC/qmodem/version.mk"
if [ -f "$VER_FILE" ]; then
  if grep -qE '^QMODEM_VERSION:=[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$' "$VER_FILE"; then
    sed -i -E 's/^(QMODEM_VERSION:=)([0-9]+\.[0-9]+\.[0-9]+)-rc\.([0-9]+)$/\1\2_rc\3/' "$VER_FILE"
    echo "[feeds] QMODEM_VERSION 已改写为 $(grep -E '^QMODEM_VERSION:=' "$VER_FILE")"
  else
    echo "[feeds] QMODEM_VERSION 合法，无需改写"
  fi
fi

# ---- 注册并安装 ----
cd "$WRT_DIR"
touch feeds.conf.default
grep -q '^src-link qmodem ' feeds.conf.default \
  || echo "src-link qmodem $FEED_SRC/qmodem" >> feeds.conf.default
grep -q '^src-link qmodem_generic ' feeds.conf.default \
  || echo "src-link qmodem_generic $FEED_SRC/qmodem-generic" >> feeds.conf.default

./scripts/feeds update qmodem qmodem_generic
./scripts/feeds install -a -p qmodem
./scripts/feeds install -a -p qmodem_generic

echo "[feeds] 已就绪"
