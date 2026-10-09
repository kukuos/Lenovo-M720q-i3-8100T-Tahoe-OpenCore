# Lenovo M720q / i3-8100T / macOS Tahoe / OpenCore

联想 ThinkCentre M720q Tiny 的 Tahoe 安装与复用记录。针对 **i3-8100T、UHD 630、HDMI、有线网络、无需无线网卡**，2026-10-09 已完成实机安装，并确认拔掉 U 盘可以进入 macOS 桌面。

本仓库提供脱敏配置、可重建 EFI 的工具和排错步骤。EFI 二进制从固定版本的上游下载，并对照实测文件的 SHA-256 校验；**机器序列号、MLB、UUID、ROM、个人日志和 macOS 镜像不上传**。构建结果在本机 `dist/USB` 中生成。

## 实测硬件与功能

| 项目 | 本次设备 / 结果 |
| --- | --- |
| 主机 | Lenovo ThinkCentre M720q Tiny |
| CPU | Intel Core i3-8100T，四核，系统显示 3.1GHz |
| 核显 | Intel UHD Graphics 630，设备 ID `0x3e91` |
| 内存 | 8GB DDR4 2400MHz |
| 硬盘 | 用户提供型号：悉硕 S500 128GB；系统识别 `SSD 128GB`，NVMe / PCI-Express，128035676160 字节 |
| 显示 | HDMI，1920×1080 @ 60Hz，1536MB 动态显存，Metal 3；鼠标与窗口拖动流畅 |
| 有线网络 | 已确认可用；沿用上游 IntelMausiEthernet 驱动 |
| 内置扬声器 / 耳机 | 已确认出声，使用 VoodooHDA 3.6.9-alpha |
| 睡眠 / 唤醒 | 实测风扇停止；短按电源后风扇恢复，移动鼠标后 HDMI 恢复画面 |
| 免 U 盘启动 | 已确认拔掉 U 盘进入桌面；配置等待时间 10 秒 |
| USB | 本次安装盘、鼠标、键盘可用；未逐一验证所有端口 |
| Wi-Fi / 蓝牙 | 不作为本项目目标，未验证 |
| HDMI 音频 / DP / 多屏 / DRM / Apple 服务 | 未验证 |

本机经历的睡眠恢复有电源键后再移动鼠标点亮显示器的过程，不应据此声称所有 USB 输入设备都能直接唤醒。远程软件后台服务可能阻止空闲睡眠，需以 `pmset -g assertions` 与实际睡眠日志判断。

## 配置重点

- OpenCore **1.0.8**；SMBIOS **iMac20,1**。本次 Macmini8,1 配置遇到安装更新准备错误，改为 iMac20,1 后继续安装成功。
- USB 与硬盘版的 `Timeout=10`、`AllowSetDefault=true`；USB `LauncherOption=Disabled`，硬盘 `LauncherOption=Full`；`RequestBootVarRouting=true`。
- 核显平台 `07009B3E`，沿用上游 HDMI connector 映射；`framebuffer-stolenmem=00003001`、`framebuffer-fbmem=00009000`。最终配置不含 `-igfxvesa`。
- 本机未手动解锁 CFG Lock，保留 `AppleXcpmCfgLock`、`AppleCpuPmCfgLock` 兼容设置。不要套用其他 BIOS 版本的解锁偏移。
- 沿用上游 USBToolBox + UTBMap 映射；别的主机、端口布局和外接设备需重新核对。
- 音频禁用 AppleALC，启用 **VoodooHDA 3.6.9-alpha / 88f1f24**，通过 EFI 注入。本项目没有把音频驱动写入系统卷。旧版 3.6.8 不作为本配置的替代品。
- 当前配置为实测兼容配置：`SecureBootModel=Disabled`、`csr-active-config=03080000`，并保留 `amfi_get_out_of_my_way=1` 等调试 / 兼容参数。**未完成完整 SIP / AMFI 恢复与系统安全收紧的验证**。

Tahoe 已移除 AppleHDA，原 AppleALC 方案不能直接提供模拟音频，见 [Dortania Tahoe 说明](https://dortania.github.io/OpenCore-Install-Guide/extras/tahoe.html)。本仓库选用的 [VoodooHDA 3.6.9-alpha](https://github.com/CloverHackyColor/VoodooHDA/releases/tag/v3.6.9-alpha) 是预发布版本，出声已实测，更新后兼容性需重新验证。

## 1. 在自己电脑上重建 EFI

安装 Git 和 Python **3.10 或更高版本**，在 Windows PowerShell 中执行：

```powershell
git clone https://github.com/kukuos/Lenovo-M720q-i3-8100T-Tahoe-OpenCore.git
cd Lenovo-M720q-i3-8100T-Tahoe-OpenCore
py -3 scripts/build.py --generate-smbios
```

macOS / Linux 对应命令为 `python3 scripts/build.py --generate-smbios`。工具会：

1. 下载固定 commit 的原始 EFI、OpenCore 1.0.8 和固定版本 VoodooHDA，校验下载包。
2. 对照 `binary-sha256.json` 核对每个复用的 EFI 二进制和资源文件。
3. 用官方 macserial 生成一组新的 iMac20,1 序列号 / MLB，生成 UUID 和本地管理 ROM，并同时写入 USB 与硬盘版。
4. 检查启用的 ACPI、kext、UEFI 驱动和工具路径，运行 OpenCore 1.0.8 的 ocvalidate，生成硬盘安装文件清单。

生成的 SMBIOS 不是 Apple 服务可用性的保证，登录 Apple ID 前需自行核对标识是否合适。以后更新同一台机器的 EFI，要保留其原有四项标识；不要每次重建都换号。**同一台机器用同一组标识，不同机器各自生成。**

不带 `--generate-smbios` 会输出带占位值的配置，仅供查看；不得直接用来启动或登录 Apple 服务。`profiles/*.plist` 是公开模板，不能直接复制当成成品 EFI。

构建不会覆写已经存在的 `dist/USB`。重建前先将旧目录移走备份。构建产生的缓存、EFI 和标识均被 `.gitignore` 排除。

## 2. 获取恢复镜像

这是**有线联网的恢复安装方案**，不是完整离线安装包。构建 EFI 后执行：

```powershell
py -3 scripts/download_recovery.py
```

macOS / Linux 使用 `python3`。工具调用固定 OpenCore 包内的 macrecovery 从 Apple 获取当前提供的恢复镜像，输出到 `dist/USB/com.apple.recovery.boot`。`latest` 会随 Apple 服务变化，进入恢复环境后必须确认“重新安装 macOS Tahoe”；若提供其他版本，停止并按对应版本准备配置。首次复用时以 [官方 Windows 制作说明](https://dortania.github.io/OpenCore-Install-Guide/installer-guide/windows-install.html) 为参考。

本次恢复镜像内版本与最终安装器显示版本不同，不能把恢复镜像版本当作最终系统完整版本。本机安装成功，但未记录最终系统 `sw_vers` 的完整构建号。

## 3. 制作 U 盘

准备可清空的 **16GB 或 32GB U 盘**。本次实测为标称 16GB、系统显示约 15.9GB 的 U 盘。制作会清空所选 U 盘，先通过型号、容量与磁盘编号核对目标。

本次可启动布局为 **GPT + FAT32 EFI 系统分区（ESP）**，卷标 `TAHOE`。初次 MBR / FAT32 在本机未被识别，改为此布局后成功，但没有单独证明故障只由 MBR 引起。

Windows 可在管理员终端进入 `diskpart`，先执行 `list disk`，确认 U 盘编号，再依次执行以下步骤。`N` 必须换成已核对的 U 盘编号，**不是系统盘编号**：

```text
select disk N
detail disk
clean
convert gpt
create partition efi
format fs=fat32 quick label=TAHOE
assign
exit
```

将 `dist/USB` 里的**内容**复制到 U 盘分区根目录，布局应为：

```text
TAHOE/
├── EFI/
│   ├── BOOT/BOOTx64.efi
│   └── OC/config.plist ...
├── com.apple.recovery.boot/
│   ├── BaseSystem.dmg
│   └── BaseSystem.chunklist
├── HardDisk-Install/
│   ├── EFI/...
│   └── SHA256SUMS
├── Install-Internal-EFI.command
├── Prepare-Standalone-Shell.command
└── Restore-USB-Boot.command
```

不要只把 DMG 放进 Ventoy 当作已完成此方案。不同容量、布局或 BIOS 的兼容性未验证。

## 4. BIOS 与安装

开机按 **F1** 进入 BIOS，按实际存在的选项设置：关闭 Secure Boot、Fast Boot 和兼容模块 / CSM，启动方式设为仅 UEFI，允许 USB 启动。有 SATA 模式选项时使用 AHCI；有核显预分配内存选项时优先 64MB 或更高。当前 EFI 仍带内存补丁。此仓库不要求刷 BIOS 或强制解锁 CFG Lock。

接网线、HDMI、键盘和鼠标；按 **F12** 选择 U 盘的 UEFI 启动项。需要时按空格显示辅助恢复项；本次选择的是 **TAHOE (dmg)**。

若首次恢复启动出现图形相关 panic，可在 **USB 版** `EFI/OC/config.plist` 的现有 boot-args 后临时追加 `-igfxvesa`。本次靠它进入恢复环境，但它会禁用核显加速，账户创建和窗口可能很卡。完成安装后删除这个参数；硬盘版保持最终加速配置。

进入恢复环境后，打开磁盘工具，显示所有设备，核对目标物理硬盘。需要整盘重装时抹掉目标盘，格式 APFS、方案 GUID；这会清除该盘数据。然后选择“重新安装 macOS Tahoe”。安装重启期间继续通过 U 盘 OpenCore，优先选择 `macOS Installer`；安装完成后选择实际系统卷。本次卷名显示为 `Macintosh HD - Data`，不同安装会不同，不要仅凭名称选错盘。

## 5. 验证后安装硬盘引导

先验证：系统信息的 UHD 630 显示 **Metal 支持**，鼠标和窗口流畅；有线网络可用；内置扬声器 / 耳机出声；实际睡眠后风扇停止并能恢复显示。

在 macOS 的**普通账户终端**执行：

```bash
diskutil list
ls /Volumes
```

如果 TAHOE 不在 `/Volumes`，确认外置 U 盘的 EFI 分区编号后挂载。例如本次某次是 `disk4s1`，但编号可能变化：

```bash
sudo diskutil mount diskXs1
bash "/Volumes/TAHOE/Install-Internal-EFI.command"
```

`diskXs1` 必须替换为实际 U 盘 EFI 分区。工具从正在运行的 macOS 反查其物理硬盘，核对内置、整盘、单物理存储、约 128GB，找到该盘 EFI，备份旧 EFI 后复制并读回校验。**它只支持本次约 128GB 的单盘布局；其他容量不会自动放行。** 对于其他容量，需要自行审查工具的容量限制或参考 [手动迁移 EFI](https://dortania.github.io/OpenCore-Post-Install/universal/oc2hdd.html)，不要为了绕过错误删除检查。

工具不格式化硬盘，不删除 Microsoft 等其他引导目录。看到“硬盘 EFI 复制及文件校验完成”后，保留桌面备份，关机、拔 U 盘，按 F12 选择内置硬盘 OpenCore / UEFI 启动项。进入 OpenCore 后选系统卷，按 **Control + Enter** 设为默认系统。重启不按键，检查是否在等待 10 秒后进入 macOS。

## 6. F12 仍只有 Windows Boot Manager 时

本机旧盘装过 Windows。复制硬盘 EFI 后，BIOS 仍选旧 Windows Boot Manager，出现 `winload.efi` 缺失、`0xc0000225`。这时硬盘 OpenCore 尚未首次启动，`LauncherOption=Full` 还没有机会注册自己的启动项。改纯 UEFI 后本机仍遇到此问题。

有效处理为**独立 USB Shell 启动硬盘 OpenCore**，详见 [完整排错记录](docs/TROUBLESHOOTING.md)。不要从已经运行的 OpenCore 的工具菜单进入 Shell，再启动另一份 OpenCore，否则会报 `Already started`。

先用正常 U 盘引导进入 macOS，执行：

```bash
bash "/Volumes/TAHOE/Prepare-Standalone-Shell.command"
```

它备份 U 盘 `BOOTx64.efi` 为 `BOOTx64-before-shell.efi`，临时将 USB 入口换成独立 OpenShell。重启从 U 盘 UEFI 进入 Shell，按 Esc 跳过启动脚本倒计时，输入：

```text
map -r
```

核对设备路径：含 `USB(...)` 的 FS 是 U 盘，内置盘的 EFI 位于 NVMe / 内置磁盘路径下的 `HD(1,GPT,...)`。本次为 **FS0=USB、FS1=内置 EFI**，但不能假定以后总是这个编号。确认后，本次执行：

```text
ls FS1:\EFI\BOOT\BOOTx64.efi
FS1:\EFI\BOOT\BOOTx64.efi
```

首字母是 **F**，不是 P。进入硬盘 OpenCore 后选系统卷，Control + Enter，然后关机拔 U 盘验证。必要时在 BIOS 的主要启动顺序中把新 OpenCore 项放到前面。该步骤已在本机解决免 U 盘启动。

确认成功后把 U 盘恢复为备用引导：插回 M720q，在 macOS 执行：

```bash
bash "/Volumes/TAHOE/Restore-USB-Boot.command"
```

若临时 Shell 后还需要回到原 U 盘 OpenCore，可从独立 Shell 启动 U 盘 FS 对应的 `\EFI\BOOT\BOOTx64-before-shell.efi`。保留 U 盘与桌面的原 EFI 备份。

## 目录与维护

| 路径 | 用途 |
| --- | --- |
| `profiles/usb.plist` | 脱敏 USB 配置模板 |
| `profiles/internal.plist` | 脱敏硬盘配置模板，启用引导项注册 |
| `scripts/build.py` | 下载固定依赖、生成身份、构建并验证 EFI |
| `scripts/download_recovery.py` | 调用 macrecovery 获取恢复镜像 |
| `scripts/*.command` | 在 macOS 安装硬盘 EFI、准备 / 恢复独立 Shell |
| `dependencies.json` | 固定下载地址与下载包 SHA-256 |
| `binary-sha256.json` | 本次已验证的 EFI 文件 SHA-256 |
| `docs/TROUBLESHOOTING.md` | 本次安装与免 U 盘启动踩坑记录 |
| `dist/USB` | 仅本地生成，不进入 Git |

更新 EFI 前备份硬盘 EFI，保留该机器的 SMBIOS 四项标识，用相同版本的 ocvalidate 校验，先从备用 U 盘验证。安装更新和音频预发布驱动升级尚未完成回归验证。

本仓库的重建工具已在 Windows 上运行并核对生成文件；硬盘复制工具和独立 Shell 操作已在这台 M720q 上实测。重建工具的 macOS / Linux 分支，以及其他硬件组合，尚未实测。

## 来源

配置与基础组件源自 [Golevka2001/Lenovo-M720Q-OpenCore-EFI](https://github.com/Golevka2001/Lenovo-M720Q-OpenCore-EFI)，固定 commit `a34973abedbef30738098ec7a852f65aad892339` 的 `Tahoe/EFI_No_Broadcom_Fix`。本机调整了 SMBIOS、核显内存参数、Tahoe 音频和硬盘启动流程。原作者使用 i5-9500T / 无线网卡，本仓库的已验证范围以表格为准。

另感谢 [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg)、[VoodooHDA](https://github.com/CloverHackyColor/VoodooHDA)、[WhateverGreen](https://github.com/acidanthera/WhateverGreen)、[USBToolBox](https://github.com/USBToolBox) 和 [Dortania](https://dortania.github.io/)。第三方组件由构建工具从上游获取，权利与许可证归各自项目，本仓库不重新授权这些组件。
