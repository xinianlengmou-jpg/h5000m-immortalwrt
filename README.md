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
files/etc/uci-defaults/      # 出厂默认值（LAN 地址 / root 密码 / RG520N-CN 接口表）
files/usr/sbin/              # qmodem-ecm-boot：ECM 模组开机兜底拨号
files/etc/init.d/            # 上面那个的 procd 启动脚本（START=99）
```

## 已装插件

| 包 | 来源 | 说明 |
| --- | --- | --- |
| `qmodem` + `quectel-CM-5G-M` | FUjr/QModem 主线 | 5G 拨号后端（`3.4.0_rc3`，纯 C + shell） |
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

模组是 Quectel RG520N-CN（`2c7c:0801`）。上游 `modem_support.json` 里只有
`rg520n-eu` / `rg520n-eb`，**没有 `-cn` 中国版**。
`luci-app-qmodem-generic` 自带 `extra_modem_support.json`（含该型号），
安装时和每次开机自动幂等注入（写前备份、写后 JSON 校验失败回滚），
**不需要手工改 `modem_support.json`**。
（这也是后端换回 FUjr 主线后 RG520N-CN 依然可用的原因。）

### 已知问题：QMI 模式数据面不通，需改用 ECM

**症状**：拨号看起来成功——能注册、能激活 PDP、能拿到 IP 和 DNS，默认路由也在，
但就是上不了网。下行全坏：

- `raw_ip=N` 时 `wwan0` 收到 **0 字节 / 0 包**
- 手动 `echo Y > /sys/class/net/wwan0/qmi/raw_ip` 后能收包了，但 `rx errs` 十几万且持续增长
- conntrack 条目全是 `[UNREPLIED]`，ping 网关和公网 100% 丢包，上行却是通的

**归因**：约九成是**系统侧**的问题，模组本身没问题。

- 排除法：切到 ECM 后，同一块模组、同一张卡、同一运营商、同一个内核 6.18，
  数据面 100% 正常 → 蜂窝能力 / SIM / APN / 内核 USB 栈 / netifd / 防火墙 NAT 全部无责
- QMI 控制面正常（注册、激活、取 IP 都成功）→ 只坏数据面封装
- 主线 `qmi_wwan.ko` 里是有 `usb:v2C7Cp0801d*...` alias 的，驱动**认得**这颗模组
- `quectel-CM-M` 二进制里同时存在两条 sysfs 路径：
  `/sys/class/net/%s/qmi/rawip`（无下划线，Quectel 定制驱动 `qmi_wwan_q` 的属性名）和
  `/sys/class/net/%s/qmi/raw_ip`（有下划线，主线 `qmi_wwan` 的属性名）。
  这套固件用的是主线驱动，raw-ip 协商没走通（`raw_ip` 一直停在 `N`）

模组固件本身只有一处瑕疵，且不影响上网：ECM 模式下它的 USB 配置描述符是畸形的
（声明 6 个接口却编号到 11），内核会报
`usb 2-1: config 1 has an invalid interface number: 10 but max is 6`。
这只影响 qmodem 的自动识别（见下），不影响数据收发。

**解法**：把模组切到 ECM（usbnet 映射：`0`=qmi `1`=ecm `2`=mbim `3`=rndis `5`=ncm）。

```sh
# 切模式（只下发 AT+QCFG="usbnet",1，不会自己重启模组）
ubus call qmodem set_mode '{"config_section":"2_1","mode":"ecm"}'
# 重启模组让设置生效（ubus 的 do_reboot 实测无效，别用）
tom_modem -d /dev/ttyUSB2 -o a -c 'AT+CFUN=1,1'
# 读回确认
tom_modem -d /dev/ttyUSB2 -o a -c 'AT+QCFG="usbnet"'   # -> +QCFG: "usbnet",1
```

该模组**不支持 NCM**（`AT+QCFG="usbnet",5` 返回 ERROR），MBIM 虽然模式支持但固件里
没有 `umbim` / `uqmi`，拨不了号。ECM 是唯一走得通的路，而且它不需要用户态拨号工具
（`at_dial_monitor` + DHCP 即可），反而比 QMI 更稳。

ECM 模式下实测：ping 13–25 ms，`curl` HTTP 200，IPv6 也通，AMBR 下行 1000 Mbps。

### 配套的两个开机修复

切到 ECM 后还有个坑：`modem_scand` 认不到模组，因为 ECM 的数据网卡挂在接口 **1.10**，
而 qmodem 自带的 `modem_port_rule.json` 只为 `2c7c:0801` 登记了 `1.2/1.3/1.4`。
日志表现为 `slot=2-1 type=usb has no net device yet` → 5 次重试后放弃 → 不注册、不拨号。

仓库里已经内置两个文件处理这件事：

| 文件 | 作用 |
| --- | --- |
| `files/etc/uci-defaults/99-qmodem-rg520n-cn` | 首次启动时把 `1.10` / `1.11` 补进接口表（幂等，改前备份）。**改完需要重启一次**才会被 `modem_scand` 重新读取 |
| `files/usr/sbin/qmodem-ecm-boot` + `files/etc/init.d/qmodem-ecm-boot` | 开机兜底（START=99）。等 ECM/NCM/RNDIS 网卡出现后，把它和 qmodem 的 section 对上、置 `state=enabled`、下发拨号。只在驱动是 `cdc_ether` / `cdc_ncm` / `rndis_host` 时动作，QMI/MBIM 不干预，且幂等 |

已验证：把 `state` 改成 `disabled`、`network` 改成错误的 `wwan0` 再重启，开机后仍能自动
纠正并上网（`/tmp/qmodem-ecm-boot.log` 有日志）。


## 许可

编译脚本与配置自写。上游与第三方：

- 底层：[immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt)
- 模组后端（拨号器）：[FUjr/QModem](https://github.com/FUjr/QModem) 主线（`3.4.0_rc3`）

> ⚠️ **后端不要用 LianXia233/QModem 那个 1.2.0 fork**，会和 `luci-app-qmodem-generic` 撞车：
> generic 自带 `qmodem-worker` / `qmodem-stats-collect` / `qmodem-modem-support` /
> `qmodem-mt5700-fix` 及 rpcd 插件 `qmodem_cache`·`qmodem_stats`·`qmodem_support`·`qos`，
> 而 1.2.0 fork 把这些同名文件也实现了一遍 → apk 报 17 条
> `trying to overwrite ... owned by qmodem` → `package/install` Error 1（源码已全编译完，
> 卡在组装 rootfs）。FUjr 主线这些同名文件一个都没有，正好互补。
> 另外 1.2.0 fork 要 `cargo` 交叉编译 rust workspace，低配机器编不动。
- 模组界面：[LianXia233/luci-app-qmodem-generic](https://github.com/LianXia233/luci-app-qmodem-generic)（Apache-2.0）
- 主题：[LianXia233/luci-theme-mint](https://github.com/LianXia233/luci-theme-mint)
- 风扇控制：[FAN789/luci-app-h5000m-fancontrol](https://github.com/FAN789/luci-app-h5000m-fancontrol)（Apache-2.0）
- 设置向导：[sirpdboy/luci-app-netwizard](https://github.com/sirpdboy/luci-app-netwizard)（GPLv3）
