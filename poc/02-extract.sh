#!/usr/bin/env bash
# PoC step 2 (throwaway): extract the full content of the verified Ubuntu ISO and Clonezilla zip,
# then check FAT32 constraints (no file >= 4 GiB, no symlink). Writes only under the work folder.
set -euo pipefail

WORK=/mnt/e/Projects/usb-builder-work
UBUNTU_ISO=$WORK/iso/ubuntu/ubuntu-26.04.1-desktop-amd64.iso
CZ_ZIP=$WORK/iso/clonezilla/clonezilla-live-3.3.3-37-amd64.zip

extract() { # $1 = archive, $2 = destination folder
    if [ -e "$2" ]; then
        echo "Already extracted, skipped: $2"
        return
    fi
    7z x "$1" -o"$2" >/dev/null
    rm -rf "$2/[BOOT]"   # El Torito boot images exposed by 7z, not part of the file tree
    echo "Extracted: $2"
}

report() { # $1 = folder
    echo "== $1"
    echo "Total size: $(du -sh "$1" | cut -f1)"
    echo "Largest files:"
    find "$1" -type f -printf '%s\t%P\n' | sort -rn | head -n 3 |
        awk -F'\t' '{ printf "  %.2f GiB  %s\n", $1 / 1073741824, $2 }' || true   # head closes the pipe early (SIGPIPE)
    local big links
    big=$(find "$1" -type f -size +4194303k | wc -l)
    links=$(find "$1" -type l | wc -l)
    echo "Files >= 4 GiB (FAT32 limit): $big"
    echo "Symlinks (not storable on FAT32): $links"
    find "$1" -type l -printf '  link: %P -> %l\n'
}

extract "$UBUNTU_ISO" "$WORK/extract/ubuntu-full"
extract "$CZ_ZIP" "$WORK/extract/clonezilla-full"
report "$WORK/extract/ubuntu-full"
report "$WORK/extract/clonezilla-full"
