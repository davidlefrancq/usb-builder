#Requires -RunAsAdministrator
# PoC step 4 (throwaway): create a Hyper-V Generation 2 VM that boots the test VHDX with Secure Boot ON.
#   Disk 1: key1.vhdx (the multiboot key under test), first boot device
#   Disk 2: an empty 64 GB dynamic VHDX, used as the Windows install target
# A vTPM is enabled because Windows 11 Setup requires TPM 2.0.

param(
    [string]$Name = 'usb-builder-key1-test',
    [string]$KeyVhdx = 'E:\Projects\usb-builder-work\vhdx\key1.vhdx',
    [string]$TargetVhdx = 'E:\Projects\usb-builder-work\vhdx\win-target.vhdx',
    [ValidateSet('MicrosoftUEFICertificateAuthority', 'MicrosoftWindows')]
    [string]$Template = 'MicrosoftUEFICertificateAuthority'
)
$ErrorActionPreference = 'Stop'

if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
    throw "VM '$Name' already exists. Remove it first if you want to recreate it."
}
if (-not (Test-Path -LiteralPath $KeyVhdx)) { throw "Key VHDX not found: $KeyVhdx" }
if (-not (Test-Path -LiteralPath $TargetVhdx)) {
    New-VHD -Path $TargetVhdx -SizeBytes 64GB -Dynamic | Out-Null
}

$vm = New-VM -Name $Name -Generation 2 -MemoryStartupBytes 4GB -NoVHD
Set-VM -VM $vm -ProcessorCount 2 -StaticMemory -AutomaticCheckpointsEnabled $false

$keyDisk = Add-VMHardDiskDrive -VM $vm -Path $KeyVhdx -Passthru
Add-VMHardDiskDrive -VM $vm -Path $TargetVhdx
Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate $Template -FirstBootDevice $keyDisk

Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
Enable-VMTPM -VM $vm

$switch = Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue
if ($switch) { Connect-VMNetworkAdapter -VMName $Name -SwitchName $switch.Name }

Get-VMFirmware -VM $vm | Format-List SecureBoot, SecureBootTemplate, BootOrder
Write-Host "VM '$Name' created."
