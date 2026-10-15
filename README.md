自用的

# h5000m-immortalwrt

只做一件事：给 **Hiveton H5000M** 编译 ImmortalWrt 固件。

## 底层

| 项 | 值 |
| --- | --- |
| 源码 | `https://github.com/immortalwrt/immortalwrt`（官方主线） |
| 分支 | `master`（可在触发时改） |
| Target | `mediatek/filogic` |
| Profile | `hiveton_h5000m`（SoC **MT7987A**，无线 MT7992） |

设备定义见上游 `target/linux/mediatek/image/filogic.mk`，
`DEVICE_DTS := mt7987a-hiveton-h5000m`。

## 怎么用

**Actions → `Build H5000M` → Run workflow**，参数：

| 输入 | 默认 | 说明 |
| --- | --- | --- |
| `branch` | `master` | 底层源码分支 |
| `packages` | 空 | 临时追加插件，每行一条 `CONFIG_PACKAGE_xxx=y` |
| `test` | `false` | 勾上只导出 `.config`，不编译（改配置时先跑这个验一遍） |

产物：`mediatek-filogic-hiveton_h5000m-squashfs-sysupgrade-*.bin`

## 出厂默认值

`files/` 按 rootfs 结构摆放，会被打进固件：

| 项 | 值 |
| --- | --- |
| LAN 地址 | `192.168.10.1/24` |
| 用户名 / 密码 | `root` / `admin` |

实现见 `files/etc/uci-defaults/99-h5000m-defaults`——uci-defaults 机制在
**首次启动**时执行一次然后自删，所以 sysupgrade 保留配置升级时不会覆盖你自己改的设置。
密码写的是 MD5 crypt（`$1$`，musl/busybox 必支持），直接改 `/etc/shadow`，
不走 `echo | passwd`，不受 busybox 交互行为影响。

## 目录

```
.github/workflows/build.yml  # 单文件工作流：拉源码 → 挂 feeds → 拼配置 → 编译 → 发布
config/base.seed             # 底层：LuCI + 中文 + 基础工具（与机型无关）
config/packages.txt          # 插件清单 ★ 要加插件改这里
scripts/feeds.sh             # 挂载第三方 feeds（QModem / 模组界面 / 主题 / 风扇 / 向导）
files/etc/uci-defaults/      # 出厂默认值（LAN 地址 / root 密码）★ 要改默认设置看这里
```

## 已装插件

| 包 | 来源 | 说明 |
| --- | --- | --- |
| `qmodem` + `quectel-CM-5G-M` | LianXia233/QModem | 5G 拨号后端 |
| `luci-app-qmodem-generic` | LianXia233 | 模组管理界面（自带 RG520N-CN 支持库注入） |
| `luci-theme-mint` | LianXia233 | 界面主题（uci-defaults 自动激活） |
| `luci-app-h5000m-fancontrol` | FAN789 | H5000M 风扇调速（依赖 `kmod-hwmon-pwmfan`） |
| `luci-app-netwizard` | sirpdboy | 首次进 LuCI 的联网设置向导 |

## 加插件

往 `config/packages.txt` 追加一行 `CONFIG_PACKAGE_xxx=y` 即可。
不确定包名可以先跑一次 `test=true` 看 `.config` 有没有被 `defconfig` 丢掉。

> ⚠️ **凡是 USB 串口类插件，必须保证 `CONFIG_PACKAGE_input-support=y`**（已在清单里）。
> 它是 input/HID/USB 串口内核模块的 Kconfig 门控包，没开的话整条依赖链会被静默隐藏。

## 关于 RG520N-CN

模组是 Quectel RG520N-CN（`2c7c:0801`），不在 QModem 上游 `modem_support.json` 里。
`luci-app-qmodem-generic` 自带 `extra_modem_support.json`（含该型号），
安装时和每次开机自动幂等注入（写前备份、写后 JSON 校验失败回滚），
**不需要手工改 `modem_support.json`**。

## 许可

编译脚本与配置自写。上游与第三方：

- 底层：[immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt)
- 模组后端（拨号器）：[LianXia233/QModem](https://github.com/LianXia233/QModem)（`QMODEM_VERSION 1.2.0`）
  —— 上游是 [FUjr/QModem](https://github.com/FUjr/QModem)（`3.4.0-rc3`），本仓库用的是她的 fork
- 模组界面：[LianXia233/luci-app-qmodem-generic](https://github.com/LianXia233/luci-app-qmodem-generic)（Apache-2.0）
- 主题：[LianXia233/luci-theme-mint](https://github.com/LianXia233/luci-theme-mint)
- 风扇控制：[FAN789/luci-app-h5000m-fancontrol](https://github.com/FAN789/luci-app-h5000m-fancontrol)（Apache-2.0）
- 设置向导：[sirpdboy/luci-app-netwizard](https://github.com/sirpdboy/luci-app-netwizard)（GPLv3）
