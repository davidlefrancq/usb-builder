# Disk selection and safety rules.
# The tool never picks a disk on its own: the user types the number, then confirms.

$script:MaxDiskBytes = 128GB

function Get-UsbBuilderDiskRefusal {
    # Returns why a disk must not be written to, or $null when it is allowed.
    # Pure function (no system call) so the rules stay easy to read and to test.
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Disk,
        [string] $MediaType
    )
    if ($Disk.IsSystem -or $Disk.IsBoot) { return 'disque système ou de démarrage' }
    if ($Disk.BusType -ne 'USB') { return "pas un disque USB (bus : $($Disk.BusType))" }
    if ($MediaType -ne 'Removable Media') { return "pas un support amovible ($MediaType)" }
    if ($Disk.Size -gt $script:MaxDiskBytes) { return 'plus de 128 Go' }
    if ($Disk.IsReadOnly) { return 'en lecture seule' }
    return $null
}

function Get-UsbBuilderDiskStatus {
    # Lists every disk with the reason it is refused (empty = allowed). Diagnostic view.
    [OutputType([pscustomobject])]
    param()
    $mediaTypes = @{}
    Get-CimInstance Win32_DiskDrive | ForEach-Object { $mediaTypes[[int]$_.Index] = $_.MediaType }

    Get-Disk | Sort-Object Number | ForEach-Object {
        [pscustomobject]@{
            Number  = $_.Number
            Model   = $_.FriendlyName
            SizeGB  = [math]::Round($_.Size / 1GB, 1)
            Refusal = Get-UsbBuilderDiskRefusal -Disk $_ -MediaType $mediaTypes[[int]$_.Number]
            Disk    = $_
        }
    }
}

function Select-UsbBuilderDisk {
    # Shows the allowed USB disks, asks for a number, then for an explicit confirmation of $Action.
    # Returns the chosen disk, re-checked right before returning.
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param(
        [Parameter(Mandatory)] [string] $Action
    )
    $candidates = @(Get-UsbBuilderDiskStatus | Where-Object { -not $_.Refusal })
    if ($candidates.Count -eq 0) {
        throw 'Aucune clé USB utilisable. Branchez la clé, puis relancez.'
    }
    $candidates | Format-Table Number, Model, SizeGB -AutoSize | Out-Host

    $answer = (Read-Host 'Numéro du disque').Trim()
    $chosen = $candidates | Where-Object { "$($_.Number)" -eq $answer }
    if (-not $chosen) { throw "Numéro refusé : '$answer'." }

    Write-Host ''
    Write-Host "Disque $($chosen.Number) : $($chosen.Model), $($chosen.SizeGB) Go"
    Write-Host "Action : $Action"
    if ((Read-Host 'Tapez OUI pour confirmer') -cne 'OUI') { throw 'Annulé.' }

    # The disk list may have changed while the user was reading: check the same disk again.
    $now = Get-UsbBuilderDiskStatus | Where-Object Number -eq $chosen.Number
    if (-not $now -or $now.Disk.UniqueId -ne $chosen.Disk.UniqueId) {
        throw 'Le disque a changé depuis la sélection. Annulé.'
    }
    if ($now.Refusal) { throw "Disque refusé : $($now.Refusal)." }
    return $now.Disk
}
