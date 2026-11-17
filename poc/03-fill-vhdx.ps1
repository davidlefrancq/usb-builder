#Requires -RunAsAdministrator
# PoC step 3 (throwaway): fill the test VHDX built by step 1.
#   P1 ESP-MENU   : Ubuntu signed shim + Ubuntu signed "disk" GRUB + generated grub.cfg, then typed as ESP
#   P2 WIN11      : Windows ISO content, install.wim split into .swm, autounattend.xml
#   P3 UBUNTU     : full Ubuntu ISO content
#   P4 CLONEZILLA : full Clonezilla zip content
# Touches only the VHDX file given in -Path. Never touches a physical disk.

param(
    [string]$Path = 'E:\Projects\usb-builder-work\vhdx\key1.vhdx',
    [string]$Work = 'E:\Projects\usb-builder-work',
    [string]$WindowsIso = 'E:\Projects\usb-builder-work\iso\windows\Windows11_Client_x64_fr-fr_26300_9457.iso'
)
$ErrorActionPreference = 'Stop'
$EspGptType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$Fat32MaxFileBytes = 4GB - 1

function Copy-Tree([string]$Source, [string]$Destination, [string[]]$ExcludeFiles = @()) {
    $exclude = if ($ExcludeFiles) { @('/XF') + $ExcludeFiles } else { @() }
    # /A-:R drops the read-only attribute that files copied from an ISO carry.
    robocopy $Source $Destination /E /A-:R /R:1 /W:1 /NFL /NDL /NJH /NP @exclude | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE): $Source -> $Destination" }
    Write-Host "Copied: $Source -> $Destination"
}

function Get-FatUuid([char]$Letter) {
    $serial = (Get-CimInstance Win32_Volume -Filter "DriveLetter='${Letter}:'").SerialNumber
    '{0:x4}-{1:x4}' -f ($serial -shr 16), ($serial -band 0xFFFF)
}

function Write-TextFile([string]$FilePath, [string]$Text) {
    New-Item -ItemType Directory -Force -Path (Split-Path $FilePath) | Out-Null
    [IO.File]::WriteAllText($FilePath, $Text, (New-Object Text.UTF8Encoding $false))
}

$disk = Mount-VHD -Path $Path -Passthru | Get-Disk
try {
    # Make sure every partition has a drive letter, then index them by volume label.
    Get-Partition -DiskNumber $disk.Number | Where-Object { -not $_.DriveLetter } |
        ForEach-Object { Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $_.PartitionNumber -AssignDriveLetter }
    $part = @{}
    Get-Partition -DiskNumber $disk.Number | ForEach-Object { $part[($_ | Get-Volume).FileSystemLabel] = $_ }
    foreach ($label in 'ESP-MENU', 'WIN11', 'UBUNTU', 'CLONEZILLA') {
        if (-not $part.ContainsKey($label)) { throw "Partition '$label' not found on the VHDX." }
    }
    $esp = "$($part['ESP-MENU'].DriveLetter):"
    $win = "$($part['WIN11'].DriveLetter):"
    $ubu = "$($part['UBUNTU'].DriveLetter):"
    $cz  = "$($part['CLONEZILLA'].DriveLetter):"

    # P3 and P4: copied as is from the verified extractions.
    Copy-Tree "$Work\extract\ubuntu-full" "$ubu\"
    Copy-Tree "$Work\extract\clonezilla-full" "$cz\"

    # P2: Windows. install.wim is larger than the FAT32 file limit, so it is split into .swm parts.
    $iso = Mount-DiskImage -ImagePath $WindowsIso -PassThru
    try {
        $src = "$(($iso | Get-Volume).DriveLetter):"
        Copy-Tree "$src\" "$win\" -ExcludeFiles 'install.wim'
        $wim = Get-Item "$src\sources\install.wim"
        if ($wim.Length -gt $Fat32MaxFileBytes) {
            # DISM is denied access when it reads install.wim straight from the read-only ISO:
            # work on a writable copy in the work folder, then delete it.
            $tmpDir = "$Work\tmp"
            New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
            $tmpWim = Join-Path $tmpDir 'install.wim'
            Copy-Item $wim.FullName $tmpWim -Force
            Set-ItemProperty -Path $tmpWim -Name IsReadOnly -Value $false
            try {
                Split-WindowsImage -ImagePath $tmpWim -SplitImagePath "$win\sources\install.swm" -FileSize 3800 -CheckIntegrity | Out-Null
            }
            finally {
                Remove-Item $tmpWim -Force
            }
            Write-Host 'Split: install.wim -> install*.swm'
        }
        else {
            Copy-Item $wim.FullName "$win\sources\"
        }
    }
    finally {
        Dismount-DiskImage -ImagePath $WindowsIso | Out-Null
    }
    Copy-Item "$PSScriptRoot\autounattend.xml" "$win\autounattend.xml"

    # P1: menu. Each entry finds its partition by FAT serial, then chainloads that system's own signed loader.
    $grubCfg = @"
set timeout=10
set default=0

menuentry "Installer Windows 11" {
    search --no-floppy --fs-uuid --set=root $(Get-FatUuid $win[0])
    chainloader /efi/boot/bootx64.efi
}

menuentry "Ubuntu (live)" {
    search --no-floppy --fs-uuid --set=root $(Get-FatUuid $ubu[0])
    chainloader /EFI/boot/bootx64.efi
}

menuentry "Clonezilla" {
    search --no-floppy --fs-uuid --set=root $(Get-FatUuid $cz[0])
    chainloader /EFI/boot/bootx64.efi
}
"@ -replace "`r`n", "`n"
    New-Item -ItemType Directory -Force -Path "$esp\EFI\BOOT" | Out-Null
    Copy-Item "$Work\extract\ubuntu\EFI\boot\bootx64.efi" "$esp\EFI\BOOT\BOOTX64.EFI"
    Copy-Item "$Work\extract\ubuntu-pool\grub-signed\usr\lib\grub\x86_64-efi-signed\grubx64.efi.signed" "$esp\EFI\BOOT\grubx64.efi"
    Write-TextFile "$esp\EFI\ubuntu\grub.cfg" $grubCfg
    Write-Host "Menu written: $esp\EFI\ubuntu\grub.cfg"
    Write-Host $grubCfg

    # P1 becomes a real ESP only now: Windows no longer gives a drive letter to an ESP.
    $p1 = $part['ESP-MENU']
    Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $p1.PartitionNumber -AccessPath "$esp\"
    Set-Partition -DiskNumber $disk.Number -PartitionNumber $p1.PartitionNumber -GptType $EspGptType
    Write-Host 'P1 typed as EFI System Partition.'
}
finally {
    Dismount-VHD -Path $Path
}
