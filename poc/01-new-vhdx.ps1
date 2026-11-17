#Requires -RunAsAdministrator
# PoC step 1 (throwaway): create the test VHDX for Key 1 with one GPT partition per system.
# Touches only the VHDX file given in -Path. Never touches a physical disk.

param(
    [string]$Path = 'E:\Projects\usb-builder-work\vhdx\key1.vhdx',
    [uint64]$SizeBytes = 64GB
)
$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $Path) {
    throw "VHDX already exists: $Path. Delete it first if you want to rebuild."
}

# P1 is created as basic data so it can be formatted and filled; step 3 switches it to ESP type.
$layout = @(
    [pscustomobject]@{ Label = 'ESP-MENU';   Size = 200MB }
    [pscustomobject]@{ Label = 'WIN11';      Size = 10GB }
    [pscustomobject]@{ Label = 'UBUNTU';     Size = 7GB }
    [pscustomobject]@{ Label = 'CLONEZILLA'; Size = 1GB }
)

New-VHD -Path $Path -SizeBytes $SizeBytes -Dynamic | Out-Null
$disk = Mount-VHD -Path $Path -Passthru | Get-Disk
try {
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT

    # Initialize-Disk adds a Microsoft Reserved partition on fixed disks; a USB key has none.
    Get-Partition -DiskNumber $disk.Number |
        Where-Object Type -eq 'Reserved' |
        Remove-Partition -Confirm:$false

    foreach ($p in $layout) {
        New-Partition -DiskNumber $disk.Number -Size $p.Size -AssignDriveLetter |
            Format-Volume -FileSystem FAT32 -NewFileSystemLabel $p.Label -Confirm:$false |
            Out-Null
    }

    # Report: partition number, label, letter, size and FAT serial (= GRUB fs-uuid).
    Get-Partition -DiskNumber $disk.Number | ForEach-Object {
        $vol = $_ | Get-Volume
        $cim = Get-CimInstance Win32_Volume -Filter "DriveLetter='$($_.DriveLetter):'"
        [pscustomobject]@{
            Number = $_.PartitionNumber
            Label  = $vol.FileSystemLabel
            Letter = $_.DriveLetter
            SizeMB = [math]::Round($_.Size / 1MB)
            FsUuid = '{0:x4}-{1:x4}' -f ($cim.SerialNumber -shr 16), ($cim.SerialNumber -band 0xFFFF)
        }
    } | Format-Table -AutoSize
}
finally {
    Dismount-VHD -Path $Path
}
