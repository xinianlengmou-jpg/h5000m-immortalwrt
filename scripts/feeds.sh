#!/bin/bash
# 挂载第三方 feeds：QModem 模组管理后端 + 通用模组管理界面
#
# 用法：bash scripts/feeds.sh <源码目录>
set -euo pipefail

WRT_DIR="${1:?用法: feeds.sh <源码目录>}"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
FEED_SRC="$WORKSPACE/_feeds"

mkdir -p "$FEED_SRC"

# ---- QModem 后端（拨号器）----
# 用 LianXia233/QModem（她从上游 FUjr/QModem fork 的版本，QMODEM_VERSION 1.2.0）。
# 上游 FUjr 是 3.4.0-rc3；选她的原因：更新更勤，且后端原生支持读
# extra_modem_support.json（上游 FUjr 不读），RG520N-CN 多一层保障。
# 依赖写的是不带版本号的库名（+libubus +libubox +libblobmsg-json +libuci），
# 源码编译不受旧 ABI 影响。
# 仓库结构是 application/* 与 luci/*，直接 src-git 扫不到包，
# 所以 clone 到本地再用 src-link 注册为本地 feed。
if [ ! -d "$FEED_SRC/qmodem" ]; then
  git clone --depth=1 --single-branch --branch main \
    https://github.com/LianXia233/QModem.git "$FEED_SRC/qmodem"
fi

# ---- 通用模组管理界面 ----
# 自带 extra_modem_support.json（含 Quectel RG520N-CN），
# 安装/开机时自动幂等注入 QModem 支持库，免手工改 modem_support.json。
if [ ! -d "$FEED_SRC/qmodem-generic" ]; then
  git clone --depth=1 --single-branch --branch main \
    https://github.com/LianXia233/luci-app-qmodem-generic.git "$FEED_SRC/qmodem-generic"
fi

# ---- Mint 主题 ----
# 仓库里包目录叫 theme/（不是 luci-theme-mint/），Makefile 里已经
# LUCI_NAME:=luci-theme-mint 钉死包名，所以 src-link 扫 <feed>/*/Makefile
# 能正常认出来。自带 uci-defaults，全新安装时会自动激活该主题。
if [ ! -d "$FEED_SRC/luci-theme-mint" ]; then
  git clone --depth=1 --single-branch --branch main \
    https://github.com/LianXia233/luci-theme-mint.git "$FEED_SRC/luci-theme-mint"
fi

# ---- 风扇控制（H5000M 专用）----
# FAN789 版：JS 视图 + rpcd ACL + procd 守护进程，不依赖已被移除的 luci-lua-runtime。
# 该仓库的 Makefile 在仓库根目录，而 src-link 的 feed 是按「根目录下的子目录」找包的，
# 所以多套一层目录，让包目录名正好等于 luci-app-h5000m-fancontrol。
# 依赖 kmod-hwmon-pwmfan（pwm-fan.ko），官方 hiveton_h5000m 的 DEVICE_PACKAGES 自带。
if [ ! -d "$FEED_SRC/fancontrol/luci-app-h5000m-fancontrol" ]; then
  mkdir -p "$FEED_SRC/fancontrol"
  git clone --depth=1 --single-branch --branch main \
    https://github.com/FAN789/luci-app-h5000m-fancontrol.git \
    "$FEED_SRC/fancontrol/luci-app-h5000m-fancontrol"
fi

# ---- 设置向导 ----
# sirpdboy 版网络设置向导：首次进 LuCI 引导配 WAN/LAN/无线。
# 这个仓库本身把包藏在 luci-app-netwizard/ 子目录里，正好一层，直接挂根目录即可。
# 纯 JS + /bin/sh 的 rpcd 插件，无 python/lua 依赖。
if [ ! -d "$FEED_SRC/netwizard" ]; then
  git clone --depth=1 --single-branch --branch main \
    https://github.com/sirpdboy/luci-app-netwizard.git "$FEED_SRC/netwizard"
fi

# ---- apk 版本号合法性修正（否则整个固件构建会被阻断）----
# OpenWrt 新版 apk 打包器不接受 `X.Y.Z-rc.N`：版本串被拼成 `3.4.0-rc.3-rN` 后
# apk mkpkg 报 "package version is invalid" (Error 99)，构建全灭。
# 改写成 apk 合法的 `X.Y.Z_rcN`；只影响包版本元数据。
# 当前用的 LianXia233 版是 `1.2.0`，本身合法、会自动跳过；
# 万一以后切回上游 FUjr（3.4.0-rc.3）或有 -rc.N 回退，这道保护就生效。
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
for pair in "qmodem:$FEED_SRC/qmodem" \
            "qmodem_generic:$FEED_SRC/qmodem-generic" \
            "luci_theme_mint:$FEED_SRC/luci-theme-mint" \
            "fancontrol:$FEED_SRC/fancontrol" \
            "netwizard:$FEED_SRC/netwizard"; do
  name="${pair%%:*}"; path="${pair#*:}"
  grep -q "^src-link ${name} " feeds.conf.default \
    || echo "src-link ${name} ${path}" >> feeds.conf.default
done

./scripts/feeds update qmodem qmodem_generic luci_theme_mint fancontrol netwizard
./scripts/feeds install -a -p qmodem
./scripts/feeds install -a -p qmodem_generic
./scripts/feeds install -a -p luci_theme_mint
./scripts/feeds install -a -p fancontrol
./scripts/feeds install -a -p netwizard

echo "[feeds] 已就绪"
