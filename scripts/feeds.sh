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
# 用上游 FUjr/QModem 主线（当前 3.4.0_rc3）。**不要**换成 LianXia233 的 1.2.0 fork，
# 两个都是实测踩出来的硬伤：
#  1) 文件冲突：luci-app-qmodem-generic 2.5.0 自己打包了一层增强版周边服务
#     （qmodem-worker / qmodem-stats-collect / qmodem-stats-loop / qmodem-task /
#      qmodem-modem-support / qmodem-mt5700-fix，以及 rpcd 插件
#      qmodem_cache·qmodem_stats·qmodem_support·qos）。
#     LianXia233 的 1.2.0 fork 是重构版，把同名文件也实现了一遍 → 两个包往同一批路径写，
#     apk 报 17 条 "trying to overwrite ... owned by qmodem" → package/install Error 1，
#     源码全编译完了却卡在组装 rootfs。FUjr 主线这些同名文件一个都没有，
#     与 generic 正好互补（generic 的 Makefile 写的就是 LUCI_DEPENDS:=+luci-base +qmodem，
#     README 指定的后端也是 FUjr 主线）。
#  2) Rust：1.2.0 fork 的 Makefile 有 Build/CompileRust，调 build-rust.sh 交叉编译
#     仓库根的 rust/ workspace（产物 qmodem-atd，triple aarch64-unknown-linux-musl）；
#     低配机器（如 3.3G 内存的虚拟机）编不动，实测 package/feeds/qmodem/qmodem failed to build。
#     主线是纯 C + shell，无 Rust。
# 版本号：主线自带 3.4.0_rc3（上游已把 -rc.3 改成 apk 合法的 _rc3），
#   下面 version.mk 的改写保护会自动跳过。
# RG520N-CN 不会丢：主线 modem_support.json 只有 rg520n-eu / rg520n-eb，
#   rg520n-cn 由 generic 自带的 extra_modem_support.json + 幂等合并脚本开机注入。
# 仓库结构是 application/* 与 luci/*，直接 src-git 扫不到包，
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
# 当前用的 FUjr 主线是 `3.4.0_rc3`（上游已自行改成 apk 合法形式），会自动跳过；
# 万一将来上游回退成 `-rc.N` 写法或有别的包带这类版本，这道保护就生效。
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
