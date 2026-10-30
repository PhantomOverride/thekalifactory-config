#!/usr/bin/env zsh
set -euo pipefail

for required_command in findmnt readlink lsblk lvs pvs vgs jq growpart sfdisk partx udevadm cryptsetup pvresize lvextend; do
  if ! command -v "$required_command" >/dev/null; then
    print -u2 "Missing command: $required_command"
    print -u2 "Install cloud-guest-utils, lvm2, cryptsetup-bin, jq, fdisk, util-linux, and udev before retrying."
    exit 1
  fi
done

filesystem="$(findmnt -nro FSTYPE /)"
case "$filesystem" in
  ext4) filesystem_command=resize2fs ;;
  xfs) filesystem_command=xfs_growfs ;;
  *) print -u2 "Unsupported root filesystem: $filesystem (expected ext4 or XFS)."; exit 1 ;;
esac
if ! command -v "$filesystem_command" >/dev/null; then
  print -u2 "Missing command: $filesystem_command (install e2fsprogs for ext4 or xfsprogs for XFS)."
  exit 1
fi

root_device="$(readlink -f -- "$(findmnt -nro SOURCE /)")"
logical_volumes="$(sudo lvs --segments --reportformat json -o lv_path,vg_name,segtype "$root_device")"
if ! printf '%s\n' "$logical_volumes" | jq -e '
  [.report[].seg[]] | length > 0 and all(.[]; .segtype == "linear")
' >/dev/null; then
  print -u2 "Only a normal, linear LVM root logical volume is supported."
  exit 1
fi
root_lv="$(printf '%s\n' "$logical_volumes" | jq -er '[.report[].seg[].lv_path] | unique | select(length == 1) | .[0]')"
volume_group="$(printf '%s\n' "$logical_volumes" | jq -er '[.report[].seg[].vg_name] | unique | select(length == 1) | .[0]')"
physical_volumes="$(sudo pvs --reportformat json -o pv_name,vg_name)"
physical_volume="$(printf '%s\n' "$physical_volumes" | jq -er --arg group "$volume_group" '
  [.report[].pv[] | select(.vg_name == $group)] | select(length == 1) | .[0].pv_name
')" || { print -u2 "The root volume group must have exactly one physical volume."; exit 1; }

layout="$(lsblk --tree --inverse --json --bytes --paths -o PATH,TYPE,FSTYPE,SIZE "$physical_volume")"
if ! printf '%s\n' "$layout" | jq -e '
  .blockdevices | length == 1 and (.[0] |
    .type == "crypt" and (.children | length == 1) and
    (.children[0] | .type == "part" and .fstype == "crypto_LUKS" and
      (.children | length == 1) and (.children[0] | .type == "disk")))
' >/dev/null; then
  print -u2 "Expected root LV -> single LVM PV -> active LUKS mapping -> partition -> disk."
  print -u2 "RAID, multipath, nested encryption, and whole-disk LUKS require manual expansion."
  exit 1
fi
partition="$(printf '%s\n' "$layout" | jq -er '.blockdevices[0].children[0].path')"
disk="$(printf '%s\n' "$layout" | jq -er '.blockdevices[0].children[0].children[0].path')"
partition_number="$(cat "/sys/class/block/${partition:t}/partition")"
[[ "$partition_number" == <-> ]] || { print -u2 "Cannot identify the partition number."; exit 1; }

partition_table="$(sudo sfdisk --json "$disk")"
if ! printf '%s\n' "$partition_table" | jq -e --arg partition "$partition" '
  .partitiontable |
  (.partitions | map(select(.node == $partition))) as $matches |
  (.label == "gpt" or .label == "dos") and .unit == "sectors" and
  (.sectorsize > 0) and ($matches | length == 1) and
  all(.partitions[]; .node == $partition or (.start + .size <= $matches[0].start)) and
  (.label != "dos" or all(.partitions[]; (.type | ascii_downcase) as $type |
    (["5", "05", "f", "0f", "85"] | index($type)) == null))
' >/dev/null; then
  print -u2 "Only a final GPT partition or final primary DOS partition without extended partitions is supported."
  print -u2 "No partitions will be moved or deleted."
  exit 1
fi
original_start="$(printf '%s\n' "$partition_table" | jq -er --arg partition "$partition" '
  .partitiontable.partitions[] | select(.node == $partition) | .start
')"

echo "Disk: $disk"
echo "LUKS partition: $partition (partition $partition_number)"
echo "Active mapping / LVM physical volume: $physical_volume"
echo "Root logical volume: $root_lv ($filesystem)"
lsblk --bytes --paths -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS "$disk"

partition_growth=false
if growth_preview="$(sudo growpart --dry-run "$disk" "$partition_number" 2>&1)"; then
  partition_growth=true
  echo "Contiguous unallocated space is available after $partition:"
  printf '%s\n' "$growth_preview"
else
  grow_exit_code=$?
  if [[ "$grow_exit_code" -ne 1 || "$growth_preview" != *NOCHANGE:* ]]; then
    print -u2 -- "$growth_preview"
    print -u2 "Partition growth check failed. No changes were made."
    exit 1
  fi
  echo "No usable trailing space for partition growth (growpart's minimum-growth threshold applies)."
  echo "The encryption, LVM, and filesystem layers may still need expansion."
fi

echo
echo "This will use all available space in the root volume group for $root_lv."
echo "Other logical volumes, including swap, will not be moved or resized."
echo "Back up important data first; a partition-table backup alone cannot restore lost data."
read "reply?Type GROW to expand, or press Enter to skip: "
if [[ "$reply" != GROW ]]; then
  echo "Storage expansion skipped."
  exit 0
fi

if [[ "$partition_growth" == true ]]; then
  backup_directory="$(sudo mktemp -d /var/backups/root-storage-grow.XXXXXXXX)"
  table_dump="$(sudo sfdisk --dump "$disk")"
  printf '%s\n' "$table_dump" | sudo tee "$backup_directory/partition-table.sfdisk" >/dev/null
  echo "Partition-table backup: $backup_directory/partition-table.sfdisk"
  sudo growpart "$disk" "$partition_number"
fi

updated_table="$(sudo sfdisk --json "$disk")"
expected_partition_bytes="$(printf '%s\n' "$updated_table" | jq -er --arg partition "$partition" --argjson start "$original_start" '
  .partitiontable | .sectorsize as $sector_size |
  .partitions[] | select(.node == $partition and .start == $start) | .size * $sector_size
')"
if ! sudo partx --update --nr "$partition_number" "$disk"; then
  print -u2 "The kernel could not reload the partition. Reboot and rerun this helper before continuing."
  exit 1
fi
sudo udevadm settle
actual_partition_bytes="$(lsblk --bytes --nodeps --noheadings -o SIZE "$partition")"
if (( actual_partition_bytes != expected_partition_bytes )); then
  print -u2 "The kernel partition size is stale. Reboot and rerun this helper before continuing."
  exit 1
fi

sudo cryptsetup resize "$physical_volume"
sudo pvresize "$physical_volume"
group_metadata="$(sudo vgs --reportformat json -o vg_free_count "$volume_group")"
free_extents="$(printf '%s\n' "$group_metadata" | jq -er '.report[0].vg[0].vg_free_count | tonumber')"
if (( free_extents > 0 )); then
  sudo lvextend -l +100%FREE "$root_lv"
else
  echo "No free LVM extents remain; checking filesystem size anyway."
fi
if [[ "$filesystem" == ext4 ]]; then
  sudo resize2fs "$root_lv"
else
  sudo xfs_growfs /
fi

echo "Root storage expansion completed."
lsblk --bytes --paths -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS "$disk"
df -h /