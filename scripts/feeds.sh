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
# 自带 uci-defaults，全新安装时会自动激活该主题。
# （包目录改名与版本兜底的处理见下，因为实测直接挂会整包不被识别）
if [ ! -d "$FEED_SRC/mint" ]; then
  git clone --depth=1 --single-branch --branch main \
    https://github.com/LianXia233/luci-theme-mint.git "$FEED_SRC/mint"
fi
# 该仓库的包目录叫 theme/ 和 wallpaper/（Makefile 里用 LUCI_NAME 钉了真名）。
# src-link 挂进去后 feeds 是按目录名建 symlink 的，目录名和包名不一致时
# 容易整包不被识别（实测 Themes 菜单里连 mint 条目都没出现）。
# 直接把目录改名成真包名，目录名与 LUCI_NAME 双重一致，最稳。
[ -d "$FEED_SRC/mint/theme" ] && [ ! -d "$FEED_SRC/mint/luci-theme-mint" ] \
  && mv "$FEED_SRC/mint/theme" "$FEED_SRC/mint/luci-theme-mint"
[ -d "$FEED_SRC/mint/wallpaper" ] && [ ! -d "$FEED_SRC/mint/luci-app-mint-wallpaper" ] \
  && mv "$FEED_SRC/mint/wallpaper" "$FEED_SRC/mint/luci-app-mint-wallpaper"
# 两个 Makefile 里写的是 `PKG_VERSION ?=` / `PKG_PO_VERSION ?=`（空值，靠 CI 注入 revision）。
# Make 里「定义但为空」也算已定义，?= 不会补值；空版本号会让索引/打包出问题，
# 这里给个固定版本兜底。
# 更要命的是末尾 `include ../../luci.mk` 是**相对路径**——它按「被放进
# feeds/luci/themes/<pkg>/」来写的，两级向上正好是 luci.mk。
# 用 src-link 挂成独立 feed 时包在 package/feeds/<feed>/<pkg>/，两级向上什么都没有，
# include 找不到文件 → 整包被静默跳过（实测：feeds install 有它，.config 里却没符号）。
# 一律改成用 TOPDIR 的绝对路径引用 luci.mk。
for mk in "$FEED_SRC/mint/luci-theme-mint/Makefile" "$FEED_SRC/mint/luci-app-mint-wallpaper/Makefile"; do
  [ -f "$mk" ] || continue
  if grep -qE '^PKG_VERSION[[:space:]]*\?=[[:space:]]*$' "$mk"; then
    sed -i -E 's/^PKG_VERSION[[:space:]]*\?=[[:space:]]*$/PKG_VERSION:=1.0.0/' "$mk"
  fi
  if grep -qE '^PKG_PO_VERSION[[:space:]]*\?=[[:space:]]*$' "$mk"; then
    sed -i -E 's/^PKG_PO_VERSION[[:space:]]*\?=[[:space:]]*$/PKG_PO_VERSION:=1.0.0/' "$mk"
  fi
  if grep -qE '^include[[:space:]]+\.\./\.\./luci\.mk[[:space:]]*$' "$mk"; then
    sed -i -E 's|^include[[:space:]]+\.\./\.\./luci\.mk[[:space:]]*$|include $(TOPDIR)/feeds/luci/luci.mk|' "$mk"
    echo "[feeds] $(basename "$(dirname "$mk")") 的 ../../luci.mk 已改为 \$(TOPDIR)/feeds/luci/luci.mk"
  fi
done

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
            "luci_theme_mint:$FEED_SRC/mint" \
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
