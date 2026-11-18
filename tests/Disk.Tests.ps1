# Checks the disk safety rules with fake disk objects. Touches no real disk.
# Usage: powershell -ExecutionPolicy Bypass -File tests\Disk.Tests.ps1

$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot '..\UsbBuilder.psm1') -Force -PassThru

function New-FakeDisk([string]$Bus = 'USB', [uint64]$Size = 64GB, [switch]$System, [switch]$ReadOnly) {
    [pscustomobject]@{ BusType = $Bus; Size = $Size; IsSystem = [bool]$System; IsBoot = $false; IsReadOnly = [bool]$ReadOnly }
}

$cases = @(
    @{ Name = 'Clé USB amovible 64 Go';        Disk = (New-FakeDisk);                 Media = 'Removable Media';         Allowed = $true }
    @{ Name = 'Disque système (même en USB)';  Disk = (New-FakeDisk -System);         Media = 'Removable Media';         Allowed = $false }
    @{ Name = 'Disque SATA';                   Disk = (New-FakeDisk -Bus 'SATA');     Media = 'Fixed hard disk media';   Allowed = $false }
    @{ Name = 'Disque NVMe';                   Disk = (New-FakeDisk -Bus 'NVMe');     Media = 'Fixed hard disk media';   Allowed = $false }
    @{ Name = 'Disque USB externe (non amovible)'; Disk = (New-FakeDisk);             Media = 'External hard disk media'; Allowed = $false }
    @{ Name = 'Clé USB de 256 Go';             Disk = (New-FakeDisk -Size 256GB);     Media = 'Removable Media';         Allowed = $false }
    @{ Name = 'Clé USB en lecture seule';      Disk = (New-FakeDisk -ReadOnly);       Media = 'Removable Media';         Allowed = $false }
)

$failed = 0
$results = foreach ($c in $cases) {
    # The rule function is internal to the module: call it inside the module scope.
    $refusal = & $module { param($d, $m) Get-UsbBuilderDiskRefusal -Disk $d -MediaType $m } $c.Disk $c.Media
    $ok = ($null -eq $refusal) -eq $c.Allowed
    if (-not $ok) { $failed++ }
    [pscustomobject]@{
        Result  = if ($ok) { 'OK' } else { 'ECHEC' }
        Case    = $c.Name
        Refusal = $refusal
    }
}
$results | Format-Table -AutoSize | Out-Host
Write-Host "$($cases.Count - $failed)/$($cases.Count) OK"
if ($failed) { exit 1 }
