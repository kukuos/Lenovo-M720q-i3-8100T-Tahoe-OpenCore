#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

fail() { printf '\n停止：%s\n请把屏幕上的信息发给我，先不要自行格式化。\n' "$*"; exit 1; }
read_plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }
[ "$(uname -s)" = Darwin ] || fail '此工具必须在 M720q 的 macOS 中运行。'
[ "$(uname -m)" = x86_64 ] || fail '此工具只用于当前 Intel macOS 主机。'
[ "$EUID" -ne 0 ] || fail '请从 macOS 桌面的普通账户终端运行，不要先进入 root shell。'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PAYLOAD="$SCRIPT_DIR/HardDisk-Install"
[ -f "$PAYLOAD/SHA256SUMS" ] || fail '找不到安装文件清单。'
[ -f "$PAYLOAD/EFI/BOOT/BOOTx64.efi" ] || fail '缺少 UEFI 启动文件。'
[ -f "$PAYLOAD/EFI/OC/config.plist" ] || fail '缺少 OpenCore 配置。'
/usr/bin/plutil -lint "$PAYLOAD/EFI/OC/config.plist"
[ "$(read_plist "$PAYLOAD/EFI/OC/config.plist" PlatformInfo:Generic:SystemSerialNumber)" != REPLACE_ME ] || fail '配置仍是模板，请先生成本机 SMBIOS。'
(cd "$PAYLOAD" && /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null) || fail '源文件校验失败。'
WORK_DIR=$(mktemp -d /tmp/m720q-efi.XXXXXX)
trap 'rm -f "$WORK_DIR/root.plist" "$WORK_DIR/apfs.plist" "$WORK_DIR/store.plist" "$WORK_DIR/disk.plist" "$WORK_DIR/list.plist" "$WORK_DIR/usb.plist" "$WORK_DIR/efi.plist"; rmdir "$WORK_DIR" 2>/dev/null || true' EXIT
diskutil info -plist / > "$WORK_DIR/root.plist"
ROOT_CONTAINER=$(read_plist "$WORK_DIR/root.plist" APFSContainerReference) || fail '无法确认当前 macOS 的 APFS 容器。'
diskutil apfs list -plist > "$WORK_DIR/apfs.plist"
FOUND_INDEX=''
for ((i=0; i<32; i++)); do
    ref=$(read_plist "$WORK_DIR/apfs.plist" "Containers:$i:ContainerReference") || break
    if [ "$ref" = "$ROOT_CONTAINER" ]; then FOUND_INDEX=$i; break; fi
done
[ -n "$FOUND_INDEX" ] || fail '无法定位正在运行的 macOS 容器。'
STORE=$(read_plist "$WORK_DIR/apfs.plist" "Containers:$FOUND_INDEX:PhysicalStores:0:DeviceIdentifier") || fail '无法确认系统所在物理分区。'
if read_plist "$WORK_DIR/apfs.plist" "Containers:$FOUND_INDEX:PhysicalStores:1:DeviceIdentifier" >/dev/null; then
    fail '检测到多个物理存储，不能自动选择目标。'
fi
[[ "$STORE" =~ ^disk[0-9]+s[0-9]+$ ]] || fail '物理分区标识不符合预期。'
TARGET_DISK=${STORE%s*}
diskutil info -plist "$TARGET_DISK" > "$WORK_DIR/disk.plist"
[ "$(read_plist "$WORK_DIR/disk.plist" Internal)" = true ] || fail '当前 macOS 不在内置硬盘上，停止复制。'
[ "$(read_plist "$WORK_DIR/disk.plist" WholeDisk)" = true ] || fail '目标不是完整物理磁盘。'
DISK_SIZE=$(read_plist "$WORK_DIR/disk.plist" TotalSize) || fail '无法读取目标容量。'
[[ "$DISK_SIZE" =~ ^[0-9]+$ ]] || fail '目标容量无效。'
(( DISK_SIZE >= 120000000000 && DISK_SIZE <= 140000000000 )) || fail '当前系统所在内置盘不是预期的 128 GB 硬盘。'
diskutil list -plist "$TARGET_DISK" > "$WORK_DIR/list.plist"
EFI_DEVICE=''
for ((i=0; i<32; i++)); do
    dev=$(read_plist "$WORK_DIR/list.plist" "AllDisksAndPartitions:0:Partitions:$i:DeviceIdentifier") || break
    kind=$(read_plist "$WORK_DIR/list.plist" "AllDisksAndPartitions:0:Partitions:$i:Content") || continue
    if [ "$kind" = EFI ]; then
        [ -z "$EFI_DEVICE" ] || fail '发现多个 EFI 分区，不能自动选择。'
        EFI_DEVICE=$dev
    fi
done
[[ "$EFI_DEVICE" =~ ^disk[0-9]+s[0-9]+$ ]] || fail '没有找到当前系统硬盘的 EFI 分区。'
diskutil info -plist "$SCRIPT_DIR" > "$WORK_DIR/usb.plist"
[ "$(read_plist "$WORK_DIR/usb.plist" Internal)" = false ] || fail '请直接从安装 U 盘运行此工具。'
SOURCE_DEVICE=$(read_plist "$WORK_DIR/usb.plist" DeviceIdentifier) || fail '无法确认安装 U 盘。'
[ "$SOURCE_DEVICE" != "$EFI_DEVICE" ] || fail '源和目标不能是同一个分区。'
printf '\n当前系统物理磁盘：%s（约 128 GB）\n引导目标：%s\n只复制引导文件，不格式化、不删除 macOS 数据。\n' "$TARGET_DISK" "$EFI_DEVICE"
diskutil info "$TARGET_DISK"
sudo -v
sudo diskutil mount "$EFI_DEVICE" >/dev/null
diskutil info -plist "$EFI_DEVICE" > "$WORK_DIR/efi.plist"
MOUNT_POINT=$(read_plist "$WORK_DIR/efi.plist" MountPoint) || fail 'EFI 分区没有挂载点。'
[[ "$MOUNT_POINT" == /Volumes/* ]] || fail 'EFI 挂载路径异常。'
[ "$MOUNT_POINT" != "$SCRIPT_DIR" ] || fail '目标不能是安装 U 盘。'
FREE_KB=$(df -k "$MOUNT_POINT" | awk 'END {print $4}')
NEED_KB=$(du -sk "$PAYLOAD/EFI" | awk '{print $1}')
[[ "$FREE_KB" =~ ^[0-9]+$ && "$NEED_KB" =~ ^[0-9]+$ ]] || fail '无法确认剩余空间。'
(( FREE_KB > NEED_KB + 8192 )) || fail 'EFI 分区空间不足。'
BACKUP_DIR="$HOME/Desktop/M720q-EFI-Backup-$(date +%Y%m%d-%H%M%S)-$$"
mkdir "$BACKUP_DIR"
printf '%s\n' "$TARGET_DISK" > "$BACKUP_DIR/target-disk.txt"
printf '%s\n' "$EFI_DEVICE" > "$BACKUP_DIR/target-efi.txt"
if [ -d "$MOUNT_POINT/EFI" ]; then sudo ditto "$MOUNT_POINT/EFI" "$BACKUP_DIR/EFI"; else touch "$BACKUP_DIR/EFI-was-empty"; fi
sudo ditto "$PAYLOAD/EFI/OC" "$MOUNT_POINT/EFI/OC"
sudo ditto "$PAYLOAD/EFI/BOOT" "$MOUNT_POINT/EFI/BOOT"
(cd "$MOUNT_POINT" && /usr/bin/shasum -a 256 -c "$PAYLOAD/SHA256SUMS" > "$BACKUP_DIR/copied-file-check.txt") || fail "硬盘文件校验失败；备份位于 $BACKUP_DIR。保留 U 盘启动。"
/usr/bin/plutil -lint "$MOUNT_POINT/EFI/OC/config.plist"
sync
printf '\n硬盘 EFI 复制及文件校验完成。\n原 EFI 备份：%s\n\n下一步：正常关机，拔掉 U 盘，开机按 F12，选择内置 S500 的 UEFI 启动项。\nOpenCore 第一次从硬盘启动后会尝试注册优先引导项。\n在 OpenCore 中选中 Macintosh HD - Data，按住 Control 再按 Enter，将它设为默认启动。\n等待时间为 10 秒。若仍无法启动，重新插入 U 盘启动，保留备份并反馈结果。\n' "$BACKUP_DIR"
