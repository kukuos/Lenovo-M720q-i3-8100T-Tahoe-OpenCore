# 实机排错记录

日期：2026-10-09。设备：M720q / i3-8100T / UHD 630 / HDMI / 128GB SSD。这里只记录本次遇到的问题和实际结果，不把一次成功扩大为所有机器通用结论。

| 现象 | 本次处理 / 结论 |
| --- | --- |
| BIOS 不显示首次制作的 U 盘 | 从 MBR/FAT32 改为 GPT/FAT32 EFI 系统分区后可启动；未单独证明最初根因 |
| 恢复启动 panic | 临时 `-igfxvesa` 后进入恢复环境；后续必须删除以恢复核显加速 |
| `An error occurred preparing the software update` | 原 Macmini8,1 换成 Tahoe 支持的 iMac20,1 后继续安装成功；该提示有多种可能原因 |
| 账户创建 / 窗口拖动很卡 | 删除 `-igfxvesa`，配合核显 framebuffer 内存补丁，最终确认 UHD 630 / Metal 3 / 1080p60 |
| 声音输出没有设备 | 停用 AppleALC，EFI 注入 VoodooHDA 3.6.9-alpha；扬声器和耳机实测出声 |
| 睡眠后 HDMI 黑屏 | 后续实测系统确实睡眠；短按电源后移动鼠标恢复显示，没有再添加猜测性的显卡唤醒补丁 |
| 退出 UU 远程后服务仍在 | UI 退出不等于后台退出；以 `pmset -g assertions` 看实际睡眠阻止项，不仅凭进程是否存在判断 |

## 找不到安装工具

```text
bash: /Volumes/TAHOE/Install-Internal-EFI.command: No such file or directory
```

当时 `diskutil list` 可见 U 盘，`ls /Volumes` 却没有 TAHOE。原因是 EFI 分区没有挂载，不是工具被删除。先查实际外置磁盘编号，再 `sudo diskutil mount diskXs1`。编号可能随插拔和重启变化，不能照抄之前的 disk4s1。

## 工具误报不是完整物理盘

```text
停止：目标不是完整物理磁盘。
```

工具初版使用了错误的 plist 键 `Whole`；`diskutil info -plist` 的实际键为 **WholeDisk**。普通文本输出的 `Whole: Yes` 不代表 plist 也叫 Whole。源 config 校验已通过，但停止发生在目标挂载 / 引导复制前。

修复为：

```bash
[ "$(read_plist "$WORK_DIR/disk.plist" WholeDisk)" = true ] || fail '目标不是完整物理磁盘。'
```

当前仓库脚本已修复。不要删除物理盘检查绕过报错。用户随后确认：内置盘约 128GB、目标 EFI、配置校验和复制后的全部文件校验都成功，原 EFI 已备份到桌面。

## 旧 Windows Boot Manager

F12 只有旧 Windows 项，启动后 `Windows/system32/winload.efi` 缺失、错误 `0xc0000225`。这说明 BIOS 启动了残留 Windows 引导，不能据此推断 macOS 安装损坏。

关闭兼容模块、设为仅 UEFI 后仍只见 Windows。本机需要先从独立 USB Shell 启动硬盘的 OpenCore，再由硬盘版 `LauncherOption=Full` 注册引导项。

## Shell 中启动报“不识别”

`ls FS1:\EFI\BOOT\BOOTx64.efi` 已显示文件，但启动命令误写成 `PS1:`。改为 **FS1:** 后能找到启动文件。路径使用英文标点，反斜杠 `\`，不要输入提示符 `Shell>`。

## Already started / Halting on critical error

```text
OCM: Failed to start image - Already started
BS: Failed to start OpenCore image - Already started
Halting on critical error
```

错误入口：U 盘 OpenCore → Tools/OpenShell → 再启动硬盘 OpenCore。此时 OpenCore 已加载，另一份 OpenCore 不能重复启动。

正确入口：临时将 USB 的 `EFI/BOOT/BOOTx64.efi` 换为 OpenShell（先备份），直接从 USB UEFI 进入独立 Shell，然后启动内置 EFI 的 `BOOTx64.efi`。具体准备、定位分区和恢复 U 盘步骤见 README。

本次独立 Shell 映射为 USB FS0、内置 NVMe EFI FS1，执行硬盘入口后进入桌面。用户随后明确确认拔掉 U 盘也可以进入 macOS 桌面。**免 U 盘启动实测成功**。配置等待 10 秒；不需要继续覆盖 Microsoft 启动文件或抹掉系统。

## 复用边界

不同 SSD 容量、BIOS、声卡、视频接口和 USB 布局不自动等同于本机。安装脚本的约 128GB 限制为有意保留，避免选错目标。构建脚本生成的新 SMBIOS 只留在本地，不能提交带个人标识的 dist、日志或桌面 EFI 备份。
