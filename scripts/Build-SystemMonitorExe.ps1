param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\dist\SystemMonitor.exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scriptPath = Join-Path $repoRoot 'TdpDrainWidget.ps1'
$iconPath = Join-Path $repoRoot 'assets\SystemMonitor.ico'
$outputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = Split-Path -Parent $outputPath

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Source script not found: $scriptPath"
}

if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "Icon not found: $iconPath"
}

if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    throw "ps2exe is not installed. Install it with: Install-Module ps2exe -Scope CurrentUser"
}

Import-Module ps2exe

Invoke-ps2exe `
    -inputFile $scriptPath `
    -outputFile $outputPath `
    -iconFile $iconPath `
    -title 'System Monitor' `
    -description 'Desktop system monitor widget' `
    -company 'Open Source' `
    -product 'System Monitor' `
    -version '1.0.0.0' `
    -noConsole `
    -STA `
    -DPIAware

Write-Host "Built: $outputPath"
