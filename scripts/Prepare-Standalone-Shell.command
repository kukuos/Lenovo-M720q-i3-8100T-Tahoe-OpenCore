#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[ "$(uname -s)" = Darwin ] || { echo '请在 M720q 的 macOS 中运行。'; exit 1; }
USB_PART=$(diskutil list | awk '$2=="EFI" && $3=="TAHOE" {print $NF}')
[[ "$USB_PART" =~ ^disk[0-9]+s[0-9]+$ ]] || { echo '未找到唯一的 TAHOE EFI 分区，请提供 diskutil list 输出。'; exit 1; }
sudo diskutil mount "$USB_PART"
USB=/Volumes/TAHOE
[ "$(diskutil info -plist "$USB" | plutil -extract Internal raw -o - -)" = false ] || { echo '目标不是外置 U 盘，停止。'; exit 1; }
[ -f "$USB/com.apple.recovery.boot/BaseSystem.dmg" ]
[ -f "$USB/EFI/OC/Tools/OpenShell.efi" ]
[ -f "$USB/EFI/BOOT/BOOTx64.efi" ]
if [ ! -f "$USB/EFI/BOOT/BOOTx64-before-shell.efi" ]; then
    cp "$USB/EFI/BOOT/BOOTx64.efi" "$USB/EFI/BOOT/BOOTx64-before-shell.efi"
fi
cp "$USB/EFI/OC/Tools/OpenShell.efi" "$USB/EFI/BOOT/BOOTx64.efi"
cmp "$USB/EFI/OC/Tools/OpenShell.efi" "$USB/EFI/BOOT/BOOTx64.efi"
sync
echo '已准备独立 Shell，原 U 盘启动文件保留为 BOOTx64-before-shell.efi。'
echo '关机后从 U 盘的 UEFI 项启动，按 Esc 跳过 startup.nsh，运行 map -r 并确认内置 EFI 的 FS 编号。'
echo '从独立 Shell 运行内置盘 EFI/BOOT/BOOTx64.efi，避免 OpenCore 重复启动。'
