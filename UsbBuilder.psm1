# usb-builder: build and maintain a Secure Boot multiboot USB key from Windows.
# Windows PowerShell 5.1. Linux-side checks run in WSL (Ubuntu-24.04).

Set-StrictMode -Version Latest

Get-ChildItem -Path (Join-Path $PSScriptRoot 'lib') -Filter '*.ps1' | ForEach-Object { . $_.FullName }

Export-ModuleMember -Function @(
    'Get-UsbBuilderDiskStatus'
    'Select-UsbBuilderDisk'
)
