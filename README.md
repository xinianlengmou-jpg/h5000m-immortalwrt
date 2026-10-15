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

## 目录

```
.github/workflows/build.yml  # 单文件工作流：拉源码 → 挂 feeds → 拼配置 → 编译 → 发布
config/base.seed             # 底层：LuCI + 中文 + 基础工具（与机型无关）
config/packages.txt          # 插件清单 ★ 要加插件改这里
scripts/feeds.sh             # 挂载 QModem 后端与通用模组管理界面
```

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
- 模组后端：[FUjr/QModem](https://github.com/FUjr/QModem)
- 模组界面：[LianXia233/luci-app-qmodem-generic](https://github.com/LianXia233/luci-app-qmodem-generic)（Apache-2.0）
