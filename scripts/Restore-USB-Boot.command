#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
[ "$(uname -s)" = Darwin ] || exit 1
part=$(diskutil list | awk '$2=="EFI" && $3=="TAHOE" {print $NF}')
[[ "$part" =~ ^disk[0-9]+s[0-9]+$ ]] || { echo '无法确认唯一的 TAHOE EFI 分区。'; exit 1; }
sudo diskutil mount "$part"
u=/Volumes/TAHOE
[ "$(diskutil info -plist "$u" | plutil -extract Internal raw -o - -)" = false ] || exit 1
[ -f "$u/EFI/BOOT/BOOTx64-before-shell.efi" ] || { echo '没有找到原启动文件备份。'; exit 1; }
cp "$u/EFI/BOOT/BOOTx64-before-shell.efi" "$u/EFI/BOOT/BOOTx64.efi"
cmp "$u/EFI/BOOT/BOOTx64-before-shell.efi" "$u/EFI/BOOT/BOOTx64.efi"
sync
echo 'U 盘正常 OpenCore 入口已恢复。'
