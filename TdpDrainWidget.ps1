param(
    [switch]$DumpSnapshot,
    [int]$RefreshMs = 1500,
    [int]$AutoCloseSeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:widgetBasePath = $PSScriptRoot
try {
    $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($processPath) {
        $processName = [System.IO.Path]::GetFileName($processPath)
        if ($processName -notmatch '^(powershell|pwsh|powershell_ise)\.exe$') {
            $script:widgetBasePath = [System.IO.Path]::GetDirectoryName($processPath)
        }
    }
} catch {
}

if (-not $script:widgetBasePath) {
    $script:widgetBasePath = [Environment]::CurrentDirectory
}

$script:logsPath = Join-Path $script:widgetBasePath 'logs'
if (-not (Test-Path -LiteralPath $script:logsPath)) {
    try {
        New-Item -ItemType Directory -Path $script:logsPath -Force | Out-Null
    } catch {
    }
}
$script:runtimeLogPath = Join-Path $script:logsPath 'widget-runtime.log'

$script:configPath = Join-Path $script:widgetBasePath 'SystemMonitor.config.json'
$script:appIconPath = Join-Path $script:widgetBasePath 'SystemMonitor.ico'
if (-not (Test-Path -LiteralPath $script:appIconPath)) {
    $script:appIconPath = Join-Path $script:widgetBasePath 'assets\SystemMonitor.ico'
}
$script:startupShortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'System Monitor Widget.lnk'
$script:isExiting = $false
$script:appConfig = $null
$script:lastInternetOnline = $null
$script:internetAlertMode = 'none'
$script:internetAlertUntil = [datetime]::MinValue
$script:internetOfflineDetectedAt = $null
$script:internetDesktopAlerted = $false
$script:edgeDockState = [PSCustomObject]@{
    Enabled          = $true
    Hidden           = $false
    PeekWidth        = 44
    MarginRight      = 10
    AutoHideSeconds  = 4
    LastInteractionAt = Get-Date
    IsDragging       = $false
}

$script:internetState = [PSCustomObject]@{
    CheckedAt      = [datetime]::MinValue
    IsOnline       = $false
    Label          = 'Checking'
    ConnectionLabel = 'Detecting network'
    OfflineSince   = $null
}

$script:networkTrafficState = [PSCustomObject]@{
    CheckedAt      = [datetime]::MinValue
    InterfaceId    = $null
    RxBytes        = [int64]0
    TxBytes        = [int64]0
    DownloadBps    = 0.0
    UploadBps      = 0.0
    Interface      = 'No network'
    DisplayLabel   = 'No network'
    LabelCheckedAt = [datetime]::MinValue
}

$script:tdpPresetLevels = @(6, 8, 10, 12)
$script:tdpCustomRange = [PSCustomObject]@{
    MinW = 4
    MaxW = 25
}
$script:fpsLimiterLevels = @(0, 30, 45, 60)
$script:performanceState = [PSCustomObject]@{
    CheckedAt          = [datetime]::MinValue
    RyzenAdjPath       = $null
    IsAvailable        = $false
    CurrentLimitW      = $null
    FastLimitW         = $null
    SlowLimitW         = $null
    LastMessage        = 'TDP controller idle'
    LastError          = $null
    LastApplyAt        = [datetime]::MinValue
    LastAppliedW       = $null
    LastApplySucceeded = $false
}

$script:fanState = [PSCustomObject]@{
    CheckedAt          = [datetime]::MinValue
    Mode               = 'Unknown'
    IsAvailable        = $false
    LastMessage        = 'Fan controller idle'
    CurrentRpm         = $null
    CurrentPwm         = $null
    RequestedMode      = $null
    RequestedPwm       = $null
    ManualHoldEnabled  = $false
    LastEnforceAt      = [datetime]::MinValue
    LastApplyAt        = [datetime]::MinValue
    LastApplyMode      = $null
    LastApplySucceeded = $false
    LastApplyStatus    = 'Idle'
}

$script:fanEcConfig = [PSCustomObject]@{
    AddressPort = 0x4E
    DataPort    = 0x4F
    RpmMsbAddr  = 0x0478
    RpmLsbAddr  = 0x0479
    PwmWriteAddr = 0x047A
    LowPwm      = 1
    MediumPwm   = 140
    MaxPwm      = 244
}

$script:inpOutState = [PSCustomObject]@{
    Initialized = $false
    Available   = $false
    DllPath     = $null
    LastError   = $null
}

$script:refreshPresetLevels = @(60, 120)
$script:refreshRateState = [PSCustomObject]@{
    CheckedAt          = [datetime]::MinValue
    CurrentHz          = $null
    SupportedHz        = @()
    Supports60         = $false
    Supports120        = $false
    LastMessage        = 'Refresh rate idle'
    LastApplyAt        = [datetime]::MinValue
    LastAppliedHz      = $null
    LastApplySucceeded = $false
    LastApplyStatus    = 'Idle'
}

function Write-RuntimeLog {
    param(
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    try {
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
        Add-Content -LiteralPath $script:runtimeLogPath -Value ("[{0}] {1}" -f $timestamp, $Message) -Encoding UTF8
    } catch {
    }
}

function Resolve-LibreHardwareMonitorPath {
    $candidates = @(
        'C:\Program Files (x86)\RivaTuner Statistics Server\Plugins\Client\LHMDataProvider\LibreHardwareMonitorLib.dll',
        'C:\Program Files (x86)\RivaTuner Statistics Server\SDK\Include\LHM\LibreHardwareMonitorLib.dll',
        'C:\Program Files\Handheld Companion\LibreHardwareMonitorLib.dll'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Import-LibreHardwareMonitor {
    $path = Resolve-LibreHardwareMonitorPath
    if (-not $path) {
        return $null
    }

    $alreadyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'LibreHardwareMonitorLib' } |
        Select-Object -First 1

    if (-not $alreadyLoaded) {
        Add-Type -Path $path
    }

    return $path
}

function New-HardwareComputer {
    $libPath = Import-LibreHardwareMonitor
    if (-not $libPath) {
        return $null
    }

    $computer = New-Object LibreHardwareMonitor.Hardware.Computer
    $computer.IsCpuEnabled = $true
    $computer.IsGpuEnabled = $true
    $computer.IsBatteryEnabled = $true
    $computer.IsMotherboardEnabled = $true
    $computer.IsControllerEnabled = $true
    $computer.IsMemoryEnabled = $true
    $computer.IsStorageEnabled = $true
    $computer.Open()
    return $computer
}

function Update-HardwareTree {
    param($Hardware)

    $Hardware.Update()
    foreach ($subHardware in $Hardware.SubHardware) {
        Update-HardwareTree -Hardware $subHardware
    }
}

function Resolve-InpOutDllPath {
    $candidates = @(
        (Join-Path $script:widgetBasePath 'amd\inpoutx64.dll'),
        (Join-Path $script:widgetBasePath 'deps\amd\inpoutx64.dll'),
        (Join-Path $script:widgetBasePath 'inpoutx64.dll')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Ensure-InpOutIo {
    if ($script:inpOutState.Initialized) {
        return [bool]$script:inpOutState.Available
    }

    $script:inpOutState.Initialized = $true
    $dllPath = Resolve-InpOutDllPath
    if (-not $dllPath) {
        $script:inpOutState.Available = $false
        $script:inpOutState.LastError = 'inpoutx64.dll not found in widget folder'
        return $false
    }

    try {
        $kernelType = [type]::GetType('SystemMonitor.Kernel32Bridge, System.Private.CoreLib', $false)
        if (-not $kernelType) {
            $loadedKernelType = [AppDomain]::CurrentDomain.GetAssemblies() |
                ForEach-Object { $_.GetType('SystemMonitor.Kernel32Bridge', $false) } |
                Where-Object { $_ } |
                Select-Object -First 1
            if (-not $loadedKernelType) {
                $kernelCode = @"
using System;
using System.Runtime.InteropServices;
namespace SystemMonitor {
    public static class Kernel32Bridge {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool SetDllDirectory(string lpPathName);
    }
}
"@
                Add-Type -TypeDefinition $kernelCode -Language CSharp -ErrorAction Stop
            }
        }

        [void][SystemMonitor.Kernel32Bridge]::SetDllDirectory([System.IO.Path]::GetDirectoryName($dllPath))

        $ioType = [AppDomain]::CurrentDomain.GetAssemblies() |
            ForEach-Object { $_.GetType('SystemMonitor.InpOutBridge', $false) } |
            Where-Object { $_ } |
            Select-Object -First 1
        if (-not $ioType) {
            $ioCode = @"
using System;
using System.Runtime.InteropServices;
namespace SystemMonitor {
    public static class InpOutBridge {
        [DllImport("inpoutx64.dll", EntryPoint = "Out32")]
        public static extern void Out32(short portAddress, short data);

        [DllImport("inpoutx64.dll", EntryPoint = "Inp32")]
        public static extern short Inp32(short portAddress);
    }
}
"@
            Add-Type -TypeDefinition $ioCode -Language CSharp -ErrorAction Stop
        }

        # Probe call to fail fast if driver access is blocked.
        [void]([SystemMonitor.InpOutBridge]::Inp32([int16]$script:fanEcConfig.DataPort))

        $script:inpOutState.Available = $true
        $script:inpOutState.DllPath = $dllPath
        $script:inpOutState.LastError = $null
        return $true
    } catch {
        $script:inpOutState.Available = $false
        $script:inpOutState.DllPath = $dllPath
        $script:inpOutState.LastError = if ($_.Exception -and $_.Exception.Message) { $_.Exception.Message } else { 'Failed to initialize EC I/O' }
        return $false
    }
}

function Invoke-EcReadByte {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Offset
    )

    if (-not (Ensure-InpOutIo)) {
        return $null
    }

    $addressPort = [int16]$script:fanEcConfig.AddressPort
    $dataPort = [int16]$script:fanEcConfig.DataPort
    try {
        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2E)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16]0x11)
        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2F)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16](($Offset -shr 8) -band 0xFF))

        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2E)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16]0x10)
        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2F)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16]($Offset -band 0xFF))

        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2E)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16]0x12)
        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2F)
        return ([SystemMonitor.InpOutBridge]::Inp32($dataPort) -band 0xFF)
    } catch {
        return $null
    }
}

function Invoke-EcWriteByte {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Offset,
        [Parameter(Mandatory = $true)]
        [int]$Value
    )

    if (-not (Ensure-InpOutIo)) {
        return $false
    }

    $addressPort = [int16]$script:fanEcConfig.AddressPort
    $dataPort = [int16]$script:fanEcConfig.DataPort
    try {
        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2E)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16]0x11)
        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2F)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16](($Offset -shr 8) -band 0xFF))

        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2E)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16]0x10)
        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2F)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16]($Offset -band 0xFF))

        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2E)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16]0x12)
        [SystemMonitor.InpOutBridge]::Out32($addressPort, [int16]0x2F)
        [SystemMonitor.InpOutBridge]::Out32($dataPort, [int16]($Value -band 0xFF))
        return $true
    } catch {
        return $false
    }
}

function Get-DirectFanControllerSnapshot {
    if (-not (Ensure-InpOutIo)) {
        return [PSCustomObject]@{
            IsAvailable = $false
            Mode        = 'Unknown'
            Rpm         = $null
            PwmRaw      = $null
            Message     = if ($script:inpOutState.LastError) { $script:inpOutState.LastError } else { 'EC fan access unavailable' }
        }
    }

    $pwm = Invoke-EcReadByte -Offset $script:fanEcConfig.PwmWriteAddr
    $rpmMsb = Invoke-EcReadByte -Offset $script:fanEcConfig.RpmMsbAddr
    $rpmLsb = Invoke-EcReadByte -Offset $script:fanEcConfig.RpmLsbAddr
    if ($null -eq $pwm -or $null -eq $rpmMsb -or $null -eq $rpmLsb) {
        return [PSCustomObject]@{
            IsAvailable = $false
            Mode        = 'Unknown'
            Rpm         = $null
            PwmRaw      = $null
            Message     = 'Could not read EC fan registers'
        }
    }

    $rpm = (($rpmMsb -shl 8) -bor $rpmLsb)
    $mode = if ($pwm -eq 0) {
        'Auto'
    } elseif ($pwm -ge 220) {
        'Max'
    } elseif ($pwm -ge 130) {
        'Medium'
    } elseif ($pwm -gt 0) {
        'Low'
    } else {
        'Custom'
    }

    return [PSCustomObject]@{
        IsAvailable = $true
        Mode        = $mode
        Rpm         = [int]$rpm
        PwmRaw      = [int]$pwm
        Message     = ('Fan mode: ' + $mode + ' | ' + [int]$rpm + ' rpm')
    }
}

function Get-FanModeTargetPwm {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Low', 'Medium', 'Max', 'Auto')]
        [string]$Mode
    )

    switch ($Mode) {
        'Auto' { return 0 }
        'Low' { return [int]$script:fanEcConfig.LowPwm }
        'Medium' { return [int]$script:fanEcConfig.MediumPwm }
        'Max' { return [int]$script:fanEcConfig.MaxPwm }
    }
}

function Test-FanPwmMatchesMode {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Low', 'Medium', 'Max', 'Auto')]
        [string]$Mode,
        [Nullable[int]]$PwmRaw
    )

    if ($null -eq $PwmRaw) {
        return $false
    }

    switch ($Mode) {
        'Auto' { return $PwmRaw -eq 0 }
        'Low' { return $PwmRaw -gt 0 -and $PwmRaw -le 8 }
        'Medium' { return [Math]::Abs($PwmRaw - [int]$script:fanEcConfig.MediumPwm) -le 12 }
        'Max' { return $PwmRaw -ge 220 }
    }
}

function Set-DirectFanMode {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Low', 'Medium', 'Max', 'Auto')]
        [string]$Mode
    )

    $targetValue = Get-FanModeTargetPwm -Mode $Mode

    $writeOk = Invoke-EcWriteByte -Offset $script:fanEcConfig.PwmWriteAddr -Value $targetValue
    if (-not $writeOk) {
        return [PSCustomObject]@{
            Success = $false
            Message = 'Failed to write EC fan register'
        }
    }

    $snapshot = $null
    $success = $false
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        Start-Sleep -Milliseconds 260
        $snapshot = Get-DirectFanControllerSnapshot
        if (-not $snapshot.IsAvailable) {
            continue
        }

        $success = Test-FanPwmMatchesMode -Mode $Mode -PwmRaw $snapshot.PwmRaw
        if ($success) {
            break
        }
    }

    if (-not $snapshot -or -not $snapshot.IsAvailable) {
        return [PSCustomObject]@{
            Success = $false
            Message = if ($snapshot -and $snapshot.Message) { $snapshot.Message } else { 'Fan snapshot unavailable after apply' }
        }
    }

    $message = if ($success) {
        if ($Mode -eq 'Max' -and [int]$snapshot.Rpm -lt 4200) {
            'Fan mode: Max applied, spin-up in progress | ' + [int]$snapshot.Rpm + ' rpm (pwm ' + [int]$snapshot.PwmRaw + ')'
        } elseif ($Mode -eq 'Low') {
            'Fan mode: Low | ' + [int]$snapshot.Rpm + ' rpm (pwm ' + [int]$snapshot.PwmRaw + ')'
        } else {
            'Fan mode: ' + $Mode + ' | ' + [int]$snapshot.Rpm + ' rpm (pwm ' + [int]$snapshot.PwmRaw + ')'
        }
    } else {
        'Fan apply mismatch (pwm ' + [int]$snapshot.PwmRaw + ', rpm ' + [int]$snapshot.Rpm + ')'
    }

    return [PSCustomObject]@{
        Success = $success
        Message = $message
        Snapshot = $snapshot
    }
}

function Enforce-FanManualHold {
    param(
        [switch]$Force,
        [int]$MinIntervalMs = 1300
    )

    if (-not $script:fanState.ManualHoldEnabled) {
        return $null
    }

    $now = Get-Date
    if (-not $Force -and (($now - $script:fanState.LastEnforceAt).TotalMilliseconds -lt [Math]::Max($MinIntervalMs, 350))) {
        return $null
    }
    $script:fanState.LastEnforceAt = $now

    $targetPwm = if ($null -ne $script:fanState.RequestedPwm) {
        [int]$script:fanState.RequestedPwm
    } elseif ($script:fanState.RequestedMode) {
        Get-FanModeTargetPwm -Mode $script:fanState.RequestedMode
    } else {
        $null
    }

    if ($null -eq $targetPwm) {
        return $null
    }

    $snapshot = Get-DirectFanControllerSnapshot
    if (-not $snapshot.IsAvailable) {
        return $snapshot
    }

    if ([Math]::Abs([int]$snapshot.PwmRaw - $targetPwm) -gt 1) {
        [void](Invoke-EcWriteByte -Offset $script:fanEcConfig.PwmWriteAddr -Value $targetPwm)
        Start-Sleep -Milliseconds 80
        $snapshot = Get-DirectFanControllerSnapshot
    }

    return $snapshot
}

function Read-IniValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([^=]+?)\s*=\s*(.*)\s*$') {
            $values[$matches[1]] = $matches[2]
        }
    }

    return $values
}

function Get-SensorValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable]$Rows,
        [Parameter(Mandatory = $true)]
        [string[]]$HardwareTypes,
        [Parameter(Mandatory = $true)]
        [string]$SensorType,
        [string[]]$PreferredNames = @(),
        [switch]$AllowZero
    )

    $rowsList = @($Rows | Where-Object {
        $_.SensorType -eq $SensorType -and $HardwareTypes -contains $_.HardwareType
    })

    foreach ($name in $PreferredNames) {
        $match = $rowsList | Where-Object { $_.Sensor -like $name } | Select-Object -First 1
        if ($match -and ($AllowZero -or [Math]::Abs([double]$match.Value) -gt 0.01)) {
            return [double]$match.Value
        }
    }

    $fallback = $rowsList | Where-Object { $AllowZero -or [Math]::Abs([double]$_.Value) -gt 0.01 } | Select-Object -First 1
    if ($fallback) {
        return [double]$fallback.Value
    }

    return $null
}

function Get-HardwareSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        $Computer
    )

    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($hardware in $Computer.Hardware) {
        Update-HardwareTree -Hardware $hardware

        foreach ($sensor in $hardware.Sensors) {
            if ($null -ne $sensor.Value) {
                $rows.Add([PSCustomObject]@{
                    Hardware     = ($hardware.Name -replace "`0", '').Trim()
                    HardwareType = $hardware.HardwareType.ToString()
                    Sensor       = ($sensor.Name -replace "`0", '').Trim()
                    SensorType   = $sensor.SensorType.ToString()
                    Value        = [double]$sensor.Value
                    Identifier   = $sensor.Identifier.ToString()
                })
            }
        }

        foreach ($subHardware in $hardware.SubHardware) {
            foreach ($sensor in $subHardware.Sensors) {
                if ($null -ne $sensor.Value) {
                    $rows.Add([PSCustomObject]@{
                        Hardware     = ("{0} > {1}" -f ($hardware.Name -replace "`0", '').Trim(), ($subHardware.Name -replace "`0", '').Trim())
                        HardwareType = $subHardware.HardwareType.ToString()
                        Sensor       = ($sensor.Name -replace "`0", '').Trim()
                        SensorType   = $sensor.SensorType.ToString()
                        Value        = [double]$sensor.Value
                        Identifier   = $sensor.Identifier.ToString()
                    })
                }
            }
        }
    }

    return $rows
}

function Get-InternetConnectionState {
    param(
        [int]$CacheSeconds = 15,
        [int]$TimeoutMs = 700
    )

    $now = Get-Date
    if (($now - $script:internetState.CheckedAt).TotalSeconds -lt $CacheSeconds) {
        return $script:internetState
    }

    if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
        $offlineSince = if ($script:internetState.OfflineSince) { $script:internetState.OfflineSince } else { $now }
        $script:internetState = [PSCustomObject]@{
            CheckedAt       = $now
            IsOnline        = $false
            Label           = 'Offline'
            ConnectionLabel = Get-OfflineDurationText -OfflineSince $offlineSince
            OfflineSince    = $offlineSince
        }
        return $script:internetState
    }

    $targets = @(
        @{ Host = '1.1.1.1'; Port = 443 },
        @{ Host = '8.8.8.8'; Port = 53 }
    )

    $isOnline = $false
    foreach ($target in $targets) {
        $client = $null
        $waitHandle = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $client.BeginConnect($target.Host, $target.Port, $null, $null)
            $waitHandle = $asyncResult.AsyncWaitHandle
            if ($waitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
                $client.EndConnect($asyncResult)
                $isOnline = $true
                break
            }
        } catch {
        } finally {
            if ($waitHandle) {
                $waitHandle.Close()
            }
            if ($client) {
                $client.Close()
            }
        }
    }

    $script:internetState = [PSCustomObject]@{
        CheckedAt       = $now
        IsOnline        = $isOnline
        Label           = if ($isOnline) { 'Online' } else { 'Offline' }
        ConnectionLabel = if ($isOnline) { 'Connected' } else { Get-OfflineDurationText -OfflineSince (if ($script:internetState.OfflineSince) { $script:internetState.OfflineSince } else { $now }) }
        OfflineSince    = if ($isOnline) { $null } else { (if ($script:internetState.OfflineSince) { $script:internetState.OfflineSince } else { $now }) }
    }

    return $script:internetState
}

function Get-NetworkTrafficState {
    $now = Get-Date
    $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object {
            $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
            $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -and
            $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel
        }

    if (-not $interfaces) {
        $script:networkTrafficState = [PSCustomObject]@{
            CheckedAt      = $now
            InterfaceId    = $null
            RxBytes        = [int64]0
            TxBytes        = [int64]0
            DownloadBps    = 0.0
            UploadBps      = 0.0
            Interface      = 'No network'
            DisplayLabel   = 'No network'
            LabelCheckedAt = $now
        }
        return $script:networkTrafficState
    }

    $preferred = $interfaces | Where-Object { $_.Id -eq $script:networkTrafficState.InterfaceId } | Select-Object -First 1
    if (-not $preferred) {
        $preferred = $interfaces |
            Sort-Object -Property @{ Expression = { [int](($_.GetIPProperties().GatewayAddresses.Count) -gt 0) }; Descending = $true }, @{ Expression = { $_.Speed }; Descending = $true } |
            Select-Object -First 1
    }

    $stats = $preferred.GetIPv4Statistics()
    $elapsed = ($now - $script:networkTrafficState.CheckedAt).TotalSeconds
    $downloadBps = 0.0
    $uploadBps = 0.0

    if ($script:networkTrafficState.InterfaceId -eq $preferred.Id -and $elapsed -gt 0.4) {
        $rxDelta = [Math]::Max(0, $stats.BytesReceived - $script:networkTrafficState.RxBytes)
        $txDelta = [Math]::Max(0, $stats.BytesSent - $script:networkTrafficState.TxBytes)
        $downloadBps = $rxDelta / $elapsed
        $uploadBps = $txDelta / $elapsed
    }

    $displayLabel = $script:networkTrafficState.DisplayLabel
    $needsLabelRefresh = ($script:networkTrafficState.InterfaceId -ne $preferred.Id) -or (($now - $script:networkTrafficState.LabelCheckedAt).TotalSeconds -ge 10)
    if ($needsLabelRefresh) {
        $displayLabel = $preferred.Name
        if ($preferred.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Wireless80211) {
            try {
                $wlanOutput = (netsh wlan show interfaces 2>$null) -join "`n"
                $namePattern = '(?im)^\s*Name\s*:\s*(.+)$'
                $ssidPattern = '(?im)^\s*SSID\s*:\s*(.+)$'
                $nameMatches = [regex]::Matches($wlanOutput, $namePattern)
                $ssidMatches = [regex]::Matches($wlanOutput, $ssidPattern)
                for ($i = 0; $i -lt [Math]::Min($nameMatches.Count, $ssidMatches.Count); $i++) {
                    if ($nameMatches[$i].Groups[1].Value.Trim() -eq $preferred.Name) {
                        $ssid = $ssidMatches[$i].Groups[1].Value.Trim()
                        if ($ssid -and $ssid -ne 'N/A') {
                            $displayLabel = $ssid
                        }
                        break
                    }
                }
                if ($displayLabel -eq $preferred.Name -and $ssidMatches.Count -eq 1) {
                    $ssid = $ssidMatches[0].Groups[1].Value.Trim()
                    if ($ssid -and $ssid -ne 'N/A') {
                        $displayLabel = $ssid
                    }
                }
            } catch {
            }
        }
    }

    $script:networkTrafficState = [PSCustomObject]@{
        CheckedAt      = $now
        InterfaceId    = $preferred.Id
        RxBytes        = [int64]$stats.BytesReceived
        TxBytes        = [int64]$stats.BytesSent
        DownloadBps    = [Math]::Round($downloadBps, 1)
        UploadBps      = [Math]::Round($uploadBps, 1)
        Interface      = $preferred.Name
        DisplayLabel   = $displayLabel
        LabelCheckedAt = if ($needsLabelRefresh) { $now } else { $script:networkTrafficState.LabelCheckedAt }
    }

    return $script:networkTrafficState
}

function Get-PowerSnapshot {
    param($Computer)

    $rows = @()
    if ($Computer) {
        $rows = Get-HardwareSnapshot -Computer $Computer
    }

    $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
    $powerLine = $powerStatus.PowerLineStatus.ToString()
    $internet = Get-InternetConnectionState
    $networkTraffic = Get-NetworkTrafficState

    $batteryRate = Get-SensorValue -Rows $rows -HardwareTypes @('Battery') -SensorType 'Power' -PreferredNames @('Charge Rate')
    $batteryLevel = Get-SensorValue -Rows $rows -HardwareTypes @('Battery') -SensorType 'Level' -PreferredNames @('Charge Level')
    $remainingCapacity = Get-SensorValue -Rows $rows -HardwareTypes @('Battery') -SensorType 'Energy' -PreferredNames @('Remaining Capacity')
    $fullCapacity = Get-SensorValue -Rows $rows -HardwareTypes @('Battery') -SensorType 'Energy' -PreferredNames @('Fully-Charged Capacity')
    $batteryVoltage = Get-SensorValue -Rows $rows -HardwareTypes @('Battery') -SensorType 'Voltage' -PreferredNames @('Voltage')
    $batteryCurrent = Get-SensorValue -Rows $rows -HardwareTypes @('Battery') -SensorType 'Current' -PreferredNames @('Charge Current')

    $cpuPackage = Get-SensorValue -Rows $rows -HardwareTypes @('Cpu') -SensorType 'Power' -PreferredNames @(
        'Package',
        'CPU Package',
        'Package (SMU)',
        'APU STAPM',
        'CPU PPT',
        'Core (SMU)'
    )
    $cpuTemp = Get-SensorValue -Rows $rows -HardwareTypes @('Cpu') -SensorType 'Temperature' -PreferredNames @(
        'Package',
        'CPU Package',
        'Tctl/Tdie',
        'Core (Max)',
        'Cores (Max)',
        'APU'
    )
    $apuStapmLimit = Get-SensorValue -Rows $rows -HardwareTypes @('Cpu') -SensorType 'Power' -PreferredNames @(
        'APU STAPM Limit',
        'PPT LIMIT FAST',
        'PPT LIMIT SLOW',
        'Max Turbo Power (PL2)',
        'Base Power (PL1)'
    )

    $gpuPower = Get-SensorValue -Rows $rows -HardwareTypes @('GpuAmd', 'GpuNvidia', 'GpuIntel') -SensorType 'Power' -PreferredNames @(
        'GPU Core',
        'GPU Package',
        'Package',
        '*GPU*'
    )

    $drainLabel = 'Battery idle'
    $drainValue = $null
    $drainIsCharging = $false
    $batteryEtaSeconds = $null
    $batteryEtaLabel = 'ETA unavailable'
    $batteryEtaStatus = 'Unavailable'

    if ($null -ne $batteryRate) {
        $drainValue = [Math]::Round([Math]::Abs($batteryRate), 1)
        if ($powerLine -eq 'Offline') {
            $drainLabel = 'System drain'
        } elseif ($powerLine -eq 'Online' -and ($batteryLevel -lt 99 -or $powerStatus.BatteryChargeStatus.ToString().Contains('Charging'))) {
            $drainLabel = 'Battery charging'
            $drainIsCharging = $true
        } elseif ($powerLine -eq 'Online') {
            $drainLabel = 'Plugged in'
        }
    }

    if ($powerLine -eq 'Offline') {
        if ($null -ne $remainingCapacity -and $null -ne $batteryRate -and $batteryRate -lt -0.3) {
            $batteryEtaSeconds = [int](($remainingCapacity / 1000) / [Math]::Abs($batteryRate) * 3600)
            $batteryEtaLabel = 'Until empty'
            $batteryEtaStatus = 'Discharging'
        } elseif ($powerStatus.BatteryLifeRemaining -ge 0) {
            $batteryEtaSeconds = [int]$powerStatus.BatteryLifeRemaining
            $batteryEtaLabel = 'Windows estimate'
            $batteryEtaStatus = 'Discharging'
        } else {
            $batteryEtaStatus = 'Estimating'
        }
    } elseif ($powerLine -eq 'Online' -and $null -ne $fullCapacity -and $null -ne $remainingCapacity -and $null -ne $batteryRate -and $batteryRate -gt 0.3) {
        $batteryEtaSeconds = [int]((($fullCapacity - $remainingCapacity) / 1000) / $batteryRate * 3600)
        $batteryEtaLabel = 'To full charge'
        $batteryEtaStatus = 'Charging'
    } elseif ($powerLine -eq 'Online') {
        $batteryEtaStatus = 'Plugged in'
    }

    [PSCustomObject]@{
        Timestamp           = Get-Date
        PowerLineStatus     = $powerLine
        CpuRealtimeW        = if ($null -ne $cpuPackage -and $cpuPackage -gt 0.05) { [Math]::Round($cpuPackage, 1) } else { $null }
        CpuPowerSource      = if ($null -ne $cpuPackage -and $cpuPackage -gt 0.05) { 'LibreHardwareMonitor CPU power sensor' } else { 'CPU power sensor unavailable' }
        CpuPackageW         = if ($null -ne $cpuPackage) { [Math]::Round($cpuPackage, 1) } else { $null }
        CpuTemperatureC     = if ($null -ne $cpuTemp) { [Math]::Round($cpuTemp, 1) } else { $null }
        ApuStapmLimitW      = if ($null -ne $apuStapmLimit) { [Math]::Round($apuStapmLimit, 1) } else { $null }
        GpuPowerW           = if ($null -ne $gpuPower) { [Math]::Round($gpuPower, 1) } else { $null }
        BatteryRateRawW     = if ($null -ne $batteryRate) { [Math]::Round($batteryRate, 1) } else { $null }
        DrainDisplayW       = $drainValue
        DrainLabel          = $drainLabel
        DrainIsCharging     = $drainIsCharging
        BatteryLevel        = if ($null -ne $batteryLevel) { [Math]::Round($batteryLevel, 0) } else { $null }
        RemainingCapacityWh = if ($null -ne $remainingCapacity) { [Math]::Round($remainingCapacity / 1000, 1) } else { $null }
        FullCapacityWh      = if ($null -ne $fullCapacity) { [Math]::Round($fullCapacity / 1000, 1) } else { $null }
        BatteryVoltageV     = if ($null -ne $batteryVoltage) { [Math]::Round($batteryVoltage, 2) } else { $null }
        BatteryCurrentA     = if ($null -ne $batteryCurrent) { [Math]::Round($batteryCurrent, 2) } else { $null }
        BatteryEtaSeconds   = $batteryEtaSeconds
        BatteryEtaLabel     = $batteryEtaLabel
        BatteryEtaStatus    = $batteryEtaStatus
        InternetOnline      = $internet.IsOnline
        InternetStatus      = $internet.Label
        InternetDetail      = if ($internet.IsOnline) { $networkTraffic.DisplayLabel } else { $internet.ConnectionLabel }
        InternetOfflineSince = $internet.OfflineSince
        DownloadBps         = $networkTraffic.DownloadBps
        UploadBps           = $networkTraffic.UploadBps
        NetworkInterface    = $networkTraffic.Interface
        SensorSource        = if ($rows.Count -gt 0) { 'LibreHardwareMonitor' } else { 'Unavailable' }
    }
}

function New-Brush {
    param([Parameter(Mandatory = $true)][string]$Color)
    return [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
}

function Format-Watts {
    param(
        [Nullable[Double]]$Value,
        [switch]$IncludeSign
    )

    if ($null -eq $Value) {
        return '--'
    }

    if ($IncludeSign -and $Value -gt 0) {
        return ('+{0:N1} W' -f $Value)
    }

    return ('{0:N1} W' -f $Value)
}

function Format-Number {
    param(
        [Nullable[Double]]$Value,
        [string]$Unit = ''
    )

    if ($null -eq $Value) {
        return '--'
    }

    if ($Unit) {
        return ('{0:N1} {1}' -f $Value, $Unit)
    }

    return ('{0:N1}' -f $Value)
}

function Format-Duration {
    param([Nullable[Int]]$TotalSeconds)

    if ($null -eq $TotalSeconds -or $TotalSeconds -le 0) {
        return '--'
    }

    $span = [TimeSpan]::FromSeconds($TotalSeconds)
    if ($span.TotalHours -ge 1) {
        return ('{0}h {1}m' -f [Math]::Floor($span.TotalHours), $span.Minutes)
    }

    if ($span.TotalMinutes -ge 1) {
        return ('{0}m' -f [Math]::Ceiling($span.TotalMinutes))
    }

    return ('{0}s' -f [Math]::Ceiling($span.TotalSeconds))
}

function Format-DataRate {
    param([Nullable[Double]]$BytesPerSecond)

    if ($null -eq $BytesPerSecond -or $BytesPerSecond -lt 0) {
        return '--'
    }

    if ($BytesPerSecond -ge 1MB) {
        return ('{0:N1} MB/s' -f ($BytesPerSecond / 1MB))
    }

    if ($BytesPerSecond -ge 1KB) {
        return ('{0:N0} KB/s' -f ($BytesPerSecond / 1KB))
    }

    return ('{0:N0} B/s' -f $BytesPerSecond)
}

function Get-OfflineDurationText {
    param([Nullable[datetime]]$OfflineSince)

    if ($null -eq $OfflineSince) {
        return 'Offline'
    }

    return 'Offline ' + (Format-Duration -TotalSeconds ([int]((Get-Date) - $OfflineSince).TotalSeconds))
}

function Convert-ToConfigBoolean {
    param(
        $Value,
        [bool]$Fallback
    )

    if ($null -eq $Value) {
        return $Fallback
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $parsed = $false
    if ([bool]::TryParse($Value.ToString(), [ref]$parsed)) {
        return $parsed
    }

    return $Fallback
}

function Convert-ToConfigDouble {
    param(
        $Value,
        [double]$Fallback
    )

    if ($null -eq $Value) {
        return $Fallback
    }

    if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal] -or $Value -is [int] -or $Value -is [long]) {
        return [double]$Value
    }

    $parsed = 0.0
    if ([double]::TryParse($Value.ToString(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }

    return $Fallback
}

function Get-StartupEnabled {
    return (Test-Path -LiteralPath $script:startupShortcutPath)
}

function Get-WidgetLaunchTarget {
    $currentProcessPath = $null
    try {
        $currentProcessPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    } catch {
    }

    if ($currentProcessPath -and [System.IO.Path]::GetExtension($currentProcessPath).Equals('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        $processName = [System.IO.Path]::GetFileName($currentProcessPath)
        if ($processName -notmatch '^(powershell|pwsh|powershell_ise)\.exe$') {
            return [PSCustomObject]@{
                TargetPath       = $currentProcessPath
                WorkingDirectory = [System.IO.Path]::GetDirectoryName($currentProcessPath)
            }
        }
    }

    $iconExeV3Path = Join-Path $script:widgetBasePath 'SystemMonitorIconV3.exe'
    if (Test-Path -LiteralPath $iconExeV3Path) {
        return [PSCustomObject]@{
            TargetPath       = $iconExeV3Path
            WorkingDirectory = $script:widgetBasePath
        }
    }

    $iconExeV2Path = Join-Path $script:widgetBasePath 'SystemMonitorIconV2.exe'
    if (Test-Path -LiteralPath $iconExeV2Path) {
        return [PSCustomObject]@{
            TargetPath       = $iconExeV2Path
            WorkingDirectory = $script:widgetBasePath
        }
    }

    $iconExePath = Join-Path $script:widgetBasePath 'SystemMonitorIcon.exe'
    if (Test-Path -LiteralPath $iconExePath) {
        return [PSCustomObject]@{
            TargetPath       = $iconExePath
            WorkingDirectory = $script:widgetBasePath
        }
    }

    $latestExePath = Join-Path $script:widgetBasePath 'SystemMonitorLatest.exe'
    if (Test-Path -LiteralPath $latestExePath) {
        return [PSCustomObject]@{
            TargetPath       = $latestExePath
            WorkingDirectory = $script:widgetBasePath
        }
    }

    $packagedExePath = Join-Path $script:widgetBasePath 'SystemMonitor.exe'
    if (Test-Path -LiteralPath $packagedExePath) {
        return [PSCustomObject]@{
            TargetPath       = $packagedExePath
            WorkingDirectory = $script:widgetBasePath
        }
    }

    return [PSCustomObject]@{
        TargetPath       = (Join-Path $script:widgetBasePath 'Launch-TdpDrainWidget.cmd')
        WorkingDirectory = $script:widgetBasePath
    }
}

function Get-DefaultAppConfig {
    [PSCustomObject]@{
        Left             = 32.0
        Top              = 32.0
        IsPinned         = $true
        IsCompact        = $true
        ShowTdpCustomPanel = $false
        TdpCustomW       = 6
        ShowModesPanel   = $false
        FpsLimiter       = 0
        EnableEdgeSidebar = $true
        EdgeAutoHideSeconds = 4
        EnableInternetNotifications = $true
        StartWithWindows = (Get-StartupEnabled)
    }
}

function Load-AppConfig {
    $config = Get-DefaultAppConfig

    if (Test-Path -LiteralPath $script:configPath) {
        try {
            $loaded = Get-Content -LiteralPath $script:configPath -Raw | ConvertFrom-Json

            if ($loaded.PSObject.Properties.Name -contains 'Left') {
                $config.Left = Convert-ToConfigDouble -Value $loaded.Left -Fallback $config.Left
            }
            if ($loaded.PSObject.Properties.Name -contains 'Top') {
                $config.Top = Convert-ToConfigDouble -Value $loaded.Top -Fallback $config.Top
            }
            if ($loaded.PSObject.Properties.Name -contains 'IsPinned') {
                $config.IsPinned = Convert-ToConfigBoolean -Value $loaded.IsPinned -Fallback $config.IsPinned
            }
            if ($loaded.PSObject.Properties.Name -contains 'IsCompact') {
                $config.IsCompact = Convert-ToConfigBoolean -Value $loaded.IsCompact -Fallback $config.IsCompact
            }
            if ($loaded.PSObject.Properties.Name -contains 'ShowTdpCustomPanel') {
                $config.ShowTdpCustomPanel = Convert-ToConfigBoolean -Value $loaded.ShowTdpCustomPanel -Fallback $config.ShowTdpCustomPanel
            }
            if ($loaded.PSObject.Properties.Name -contains 'TdpCustomW') {
                $customWRaw = Convert-ToConfigDouble -Value $loaded.TdpCustomW -Fallback $config.TdpCustomW
                $config.TdpCustomW = [Math]::Max($script:tdpCustomRange.MinW, [Math]::Min($script:tdpCustomRange.MaxW, [int][Math]::Round($customWRaw)))
            }
            if ($loaded.PSObject.Properties.Name -contains 'ShowModesPanel') {
                $config.ShowModesPanel = Convert-ToConfigBoolean -Value $loaded.ShowModesPanel -Fallback $config.ShowModesPanel
            }
            if ($loaded.PSObject.Properties.Name -contains 'FpsLimiter') {
                $fpsRaw = Convert-ToConfigDouble -Value $loaded.FpsLimiter -Fallback $config.FpsLimiter
                $fpsRounded = [int][Math]::Round($fpsRaw)
                $config.FpsLimiter = if ($script:fpsLimiterLevels -contains $fpsRounded) { $fpsRounded } else { 0 }
            }
            if ($loaded.PSObject.Properties.Name -contains 'EnableEdgeSidebar') {
                $config.EnableEdgeSidebar = Convert-ToConfigBoolean -Value $loaded.EnableEdgeSidebar -Fallback $config.EnableEdgeSidebar
            }
            if ($loaded.PSObject.Properties.Name -contains 'EdgeAutoHideSeconds') {
                $autoHideRaw = Convert-ToConfigDouble -Value $loaded.EdgeAutoHideSeconds -Fallback $config.EdgeAutoHideSeconds
                $config.EdgeAutoHideSeconds = [Math]::Max(2, [Math]::Min(30, [int][Math]::Round($autoHideRaw)))
            }
            if ($loaded.PSObject.Properties.Name -contains 'EnableInternetNotifications') {
                $config.EnableInternetNotifications = Convert-ToConfigBoolean -Value $loaded.EnableInternetNotifications -Fallback $config.EnableInternetNotifications
            }
            if ($loaded.PSObject.Properties.Name -contains 'StartWithWindows') {
                $config.StartWithWindows = Convert-ToConfigBoolean -Value $loaded.StartWithWindows -Fallback $config.StartWithWindows
            }
        } catch {
        }
    }

    $config.StartWithWindows = Get-StartupEnabled
    return $config
}

function Save-AppConfig {
    if (-not $script:appConfig) {
        return
    }

    try {
        $script:appConfig.StartWithWindows = Get-StartupEnabled
        $script:appConfig | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:configPath -Encoding UTF8
    } catch {
    }
}

function Set-StartupEnabled {
    param([bool]$Enabled)

    if ($Enabled) {
        $launchTarget = Get-WidgetLaunchTarget
        if (-not (Test-Path -LiteralPath $launchTarget.TargetPath)) {
            return $false
        }

        try {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($script:startupShortcutPath)
            $shortcut.TargetPath = $launchTarget.TargetPath
            $shortcut.WorkingDirectory = $launchTarget.WorkingDirectory
            $shortcut.WindowStyle = 7
            $shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,109"
            $shortcut.Description = 'Launch System Monitor widget'
            $shortcut.Save()
        } catch {
            return $false
        }

        return $true
    }

    if (Test-Path -LiteralPath $script:startupShortcutPath) {
        try {
            Remove-Item -LiteralPath $script:startupShortcutPath -Force
        } catch {
            return $false
        }
    }

    return $true
}

function Update-WindowPositionConfig {
    param($Window)

    if (-not $script:appConfig -or -not $Window) {
        return
    }

    if ($script:edgeDockState.Enabled) {
        $script:appConfig.Left = [Math]::Round([double](Get-EdgeDockVisibleLeft -Window $Window), 1)
        $script:appConfig.Top = [Math]::Round([double](Get-EdgeDockTargetTop -Window $Window), 1)
        return
    }

    if (-not [double]::IsNaN($Window.Left)) {
        $script:appConfig.Left = [Math]::Round([double]$Window.Left, 1)
    }

    if (-not [double]::IsNaN($Window.Top)) {
        $script:appConfig.Top = [Math]::Round([double]$Window.Top, 1)
    }
}

function Save-AppState {
    param($Window)

    if ($Window) {
        Update-WindowPositionConfig -Window $Window
    }

    if ($script:appConfig) {
        $script:appConfig.IsPinned = $script:isPinned
    }

    Save-AppConfig
}

function Set-PinVisual {
    param(
        $Window,
        [hashtable]$NamedElements,
        [bool]$IsPinned
    )

    $script:isPinned = $IsPinned
    $Window.Topmost = if ($script:edgeDockState.Enabled -and $script:edgeDockState.Hidden) { $true } else { $IsPinned }
    $NamedElements.PinButton.Content = '📌'
    $NamedElements.PinButton.Background = if ($IsPinned) { New-Brush '#33FF5A5A' } else { New-Brush '#18FFFFFF' }
    $NamedElements.PinButton.BorderBrush = if ($IsPinned) { New-Brush '#66FFB3B3' } else { New-Brush '#2EFFFFFF' }
    $NamedElements.PinButton.Foreground = New-Brush '#FFF5F7FB'
    $NamedElements.PinButton.Opacity = if ($IsPinned) { 1.0 } else { 0.72 }
    $NamedElements.PinButton.ToolTip = if ($IsPinned) { 'Pinned on top' } else { 'Not pinned' }

    if ($script:appConfig) {
        $script:appConfig.IsPinned = $IsPinned
    }
}

function Get-EdgeDockWindowWidth {
    param($Window)

    if (-not $Window) {
        return 412.0
    }

    if ($Window.ActualWidth -gt 0) {
        return [double]$Window.ActualWidth
    }
    if ($Window.Width -gt 0) {
        return [double]$Window.Width
    }
    if ($Window.MinWidth -gt 0) {
        return [double]$Window.MinWidth
    }

    return 412.0
}

function Get-EdgeDockWindowHeight {
    param($Window)

    if (-not $Window) {
        return 540.0
    }

    if ($Window.ActualHeight -gt 0) {
        return [double]$Window.ActualHeight
    }
    if ($Window.Height -gt 0) {
        return [double]$Window.Height
    }
    if ($Window.MinHeight -gt 0) {
        return [double]$Window.MinHeight
    }

    return 540.0
}

function Test-WindowVisibleOnAnyScreen {
    param(
        $Window,
        [double]$MinVisibleWidth = 120.0,
        [double]$MinVisibleHeight = 72.0
    )

    if (-not $Window) {
        return $false
    }

    $windowWidth = Get-EdgeDockWindowWidth -Window $Window
    $windowHeight = Get-EdgeDockWindowHeight -Window $Window
    if ($windowWidth -le 1 -or $windowHeight -le 1) {
        return $false
    }

    $windowRect = [System.Drawing.Rectangle]::FromLTRB(
        [int][Math]::Round([double]$Window.Left),
        [int][Math]::Round([double]$Window.Top),
        [int][Math]::Round([double]$Window.Left + $windowWidth),
        [int][Math]::Round([double]$Window.Top + $windowHeight)
    )

    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $intersection = [System.Drawing.Rectangle]::Intersect($windowRect, $screen.WorkingArea)
        if (($intersection.Width -ge $MinVisibleWidth) -and ($intersection.Height -ge $MinVisibleHeight)) {
            return $true
        }
    }

    return $false
}

function Get-EdgeDockScreenRect {
    param($Window)

    $screens = [System.Windows.Forms.Screen]::AllScreens
    if (-not $screens -or $screens.Count -eq 0) {
        return [System.Windows.Forms.SystemInformation]::VirtualScreen
    }

    $windowWidth = Get-EdgeDockWindowWidth -Window $Window
    $windowHeight = Get-EdgeDockWindowHeight -Window $Window
    $windowLeft = [double]::NaN
    $windowTop = [double]::NaN
    if ($Window) {
        $windowLeft = [double]$Window.Left
        $windowTop = [double]$Window.Top
    }

    if (-not [double]::IsNaN($windowLeft) -and -not [double]::IsNaN($windowTop)) {
        $centerX = [int][Math]::Round($windowLeft + ($windowWidth / 2.0))
        $centerY = [int][Math]::Round($windowTop + ($windowHeight / 2.0))
        foreach ($screen in $screens) {
            if ($screen.Bounds.Contains($centerX, $centerY)) {
                return $screen.WorkingArea
            }
        }
    }

    try {
        $cursor = [System.Windows.Forms.Cursor]::Position
        foreach ($screen in $screens) {
            if ($screen.Bounds.Contains($cursor)) {
                return $screen.WorkingArea
            }
        }
    } catch {
    }

    return [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
}

function Get-EdgeDockTargetTop {
    param($Window)

    $screen = Get-EdgeDockScreenRect -Window $Window
    $top = [double]$Window.Top
    if ([double]::IsNaN($top)) {
        $top = $screen.Top + 36
    }

    $windowHeight = Get-EdgeDockWindowHeight -Window $Window
    $maxTop = [double]($screen.Bottom - $windowHeight - 10)
    if ($maxTop -lt $screen.Top) {
        $maxTop = $screen.Top
    }

    if ($top -lt $screen.Top) {
        $top = $screen.Top
    }
    if ($top -gt $maxTop) {
        $top = $maxTop
    }

    return $top
}

function Get-EdgeDockVisibleLeft {
    param($Window)
    $screen = Get-EdgeDockScreenRect -Window $Window
    $windowWidth = Get-EdgeDockWindowWidth -Window $Window
    $left = [double]($screen.Right - $windowWidth - $script:edgeDockState.MarginRight)
    if ($left -lt $screen.Left) {
        $left = [double]$screen.Left
    }
    return $left
}

function Get-EdgeDockHiddenLeft {
    param($Window)
    $screen = Get-EdgeDockScreenRect -Window $Window
    $windowWidth = Get-EdgeDockWindowWidth -Window $Window
    $peekWidth = [double]$script:edgeDockState.PeekWidth
    if ($peekWidth -lt 14) {
        $peekWidth = 14
    }
    $maxPeek = [Math]::Max(14.0, $windowWidth - 20.0)
    if ($peekWidth -gt $maxPeek) {
        $peekWidth = $maxPeek
    }

    # Hidden to right side, keeping only a slim left-side strip visible.
    $left = [double]($screen.Right - $peekWidth)
    $minLeft = [double]($screen.Left - $windowWidth + 8)
    $maxLeft = [double]($screen.Right - 8)
    if ($left -lt $minLeft) {
        $left = $minLeft
    }
    if ($left -gt $maxLeft) {
        $left = $maxLeft
    }
    return $left
}

function Set-EdgeDockActivity {
    $script:edgeDockState.LastInteractionAt = Get-Date
}

function Update-EdgeControlsUi {
    param(
        [hashtable]$NamedElements
    )

    $enabled = [bool]$script:edgeDockState.Enabled
    $hidden = [bool]$script:edgeDockState.Hidden

    if ($NamedElements.ContainsKey('SidebarButton') -and $NamedElements.SidebarButton) {
        $NamedElements.SidebarButton.Background = if ($enabled) { New-Brush '#335B8DFF' } else { New-Brush '#18FFFFFF' }
        $NamedElements.SidebarButton.BorderBrush = if ($enabled) { New-Brush '#6690B8FF' } else { New-Brush '#2EFFFFFF' }
        $NamedElements.SidebarButton.Foreground = New-Brush '#FFF5F7FB'
        $NamedElements.SidebarButton.Opacity = if ($enabled) { 1.0 } else { 0.76 }
        $NamedElements.SidebarButton.ToolTip = if ($enabled) { 'Sidebar mode enabled' } else { 'Sidebar mode disabled' }
    }

    if ($NamedElements.ContainsKey('DockHandleButton') -and $NamedElements.DockHandleButton) {
        $NamedElements.DockHandleButton.Visibility = if ($enabled) { 'Visible' } else { 'Collapsed' }
        $NamedElements.DockHandleButton.Content = if ($hidden) { '◀' } else { '▶' }
        $NamedElements.DockHandleButton.ToolTip = if ($hidden) { 'Open sidebar widget' } else { 'Hide widget to right sidebar' }
        $NamedElements.DockHandleButton.HorizontalAlignment = if ($hidden) { 'Left' } else { 'Right' }
        $NamedElements.DockHandleButton.Margin = if ($hidden) {
            [System.Windows.Thickness]::new(2, 0, 0, 0)
        } else {
            [System.Windows.Thickness]::new(0, 0, 0, 0)
        }
    }
}

function Set-WindowLeftAnimated {
    param(
        $Window,
        [double]$ToLeft,
        [int]$DurationMs = 180
    )

    if (-not $Window) {
        return
    }

    try {
        $duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds([Math]::Max($DurationMs, 70)))
        $animation = [System.Windows.Media.Animation.DoubleAnimation]::new($ToLeft, $duration)
        $ease = [System.Windows.Media.Animation.CubicEase]::new()
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $animation.EasingFunction = $ease
        $Window.BeginAnimation([System.Windows.Window]::LeftProperty, $animation)
    } catch {
        $Window.Left = $ToLeft
    }
}

function Set-EdgeDockPosition {
    param(
        $Window,
        [bool]$Hidden,
        [switch]$Animate
    )

    if (-not $Window -or -not $script:edgeDockState.Enabled) {
        return
    }

    $targetTop = Get-EdgeDockTargetTop -Window $Window
    $targetLeft = if ($Hidden) {
        Get-EdgeDockHiddenLeft -Window $Window
    } else {
        Get-EdgeDockVisibleLeft -Window $Window
    }

    $Window.Top = $targetTop
    if ($Animate) {
        Set-WindowLeftAnimated -Window $Window -ToLeft $targetLeft
    } else {
        $Window.Left = $targetLeft
    }
}

function Show-EdgeDockWidget {
    param(
        $Window,
        [switch]$Animate,
        [switch]$ActivateWindow
    )

    if (-not $Window) {
        return
    }

    if (-not $Window.IsVisible) {
        $Window.Show()
    }

    $Window.WindowState = 'Normal'
    $script:edgeDockState.Hidden = $false
    $Window.ShowInTaskbar = $true
    Set-EdgeDockPosition -Window $Window -Hidden $false -Animate:$Animate
    if (-not (Test-WindowVisibleOnAnyScreen -Window $Window)) {
        Recover-MainWindowPlacement -Window $Window
        if ($script:appConfig) {
            $script:appConfig.EnableEdgeSidebar = $true
        }
        $script:edgeDockState.Enabled = $true
        $script:edgeDockState.Hidden = $false
        Set-EdgeDockPosition -Window $Window -Hidden $false
    }
    $Window.Topmost = $script:isPinned
    Set-EdgeDockActivity
    if ($ActivateWindow) {
        $Window.WindowState = 'Normal'
        $Window.Activate() | Out-Null
    }
}

function Hide-EdgeDockWidget {
    param(
        $Window,
        [switch]$Animate
    )

    if (-not $Window -or -not $Window.IsVisible) {
        return
    }

    $script:edgeDockState.Hidden = $true
    $Window.ShowInTaskbar = $true
    $Window.Topmost = $true
    Set-EdgeDockPosition -Window $Window -Hidden $true -Animate:$Animate
    if (-not (Test-WindowVisibleOnAnyScreen -Window $Window -MinVisibleWidth 28 -MinVisibleHeight 40)) {
        $Window.Left = Get-EdgeDockHiddenLeft -Window $Window
        $Window.Top = Get-EdgeDockTargetTop -Window $Window
    }
    Set-EdgeDockActivity
}

function Set-EdgeSidebarMode {
    param(
        $Window,
        [hashtable]$NamedElements,
        [bool]$Enabled
    )

    if (-not $Window) {
        return
    }

    $script:edgeDockState.Enabled = $Enabled
    $script:edgeDockState.Hidden = $false
    Set-EdgeDockActivity

    if ($Enabled) {
        $Window.ShowInTaskbar = $true
        if ($Window.IsVisible) {
            $Window.WindowState = 'Normal'
            Show-EdgeDockWidget -Window $Window -ActivateWindow
        } else {
            # During startup, the window is not shown yet and will be presented by ShowDialog().
            # Calling Show() here would make ShowDialog throw ("only on hidden windows").
            Set-EdgeDockPosition -Window $Window -Hidden $false
        }
    } else {
        $Window.ShowInTaskbar = $true
        $screen = Get-EdgeDockScreenRect -Window $Window
        $windowWidth = Get-EdgeDockWindowWidth -Window $Window
        if ($Window.Left -gt ($screen.Right - 80)) {
            $Window.Left = $screen.Right - $windowWidth - 24
        }
    }

    $Window.Topmost = $script:isPinned

    if ($script:appConfig) {
        $script:appConfig.EnableEdgeSidebar = $Enabled
    }

    Update-EdgeControlsUi -NamedElements $NamedElements
}

function Update-EdgeDockAutoHide {
    param($Window)

    if (-not $Window -or -not $script:edgeDockState.Enabled -or -not $Window.IsVisible) {
        return
    }

    if ($script:edgeDockState.Hidden) {
        if ($Window.IsMouseOver) {
            Show-EdgeDockWidget -Window $Window -Animate -ActivateWindow
        }
        return
    }

    if ($script:isPinned -or $script:edgeDockState.IsDragging) {
        return
    }

    if ($Window.IsMouseOver -or $Window.IsActive) {
        return
    }

    $idleSeconds = (Get-Date) - $script:edgeDockState.LastInteractionAt
    if ($idleSeconds.TotalSeconds -ge [Math]::Max(2, $script:edgeDockState.AutoHideSeconds)) {
        Hide-EdgeDockWidget -Window $Window -Animate
    }
}

function Set-CompactMode {
    param(
        $Window,
        [hashtable]$NamedElements,
        [bool]$IsCompact
    )

    $NamedElements.SubtitleText.Visibility = if ($IsCompact) { 'Collapsed' } else { 'Visible' }
    if ($NamedElements.ContainsKey('TdpControlPanel') -and $NamedElements.TdpControlPanel) {
        $NamedElements.TdpControlPanel.Visibility = if ($IsCompact) { 'Collapsed' } else { 'Visible' }
    }
    if ($NamedElements.ContainsKey('InternetAlertPanel') -and $NamedElements.InternetAlertPanel -and $IsCompact) {
        $NamedElements.InternetAlertPanel.Visibility = 'Collapsed'
    }
    $NamedElements.FullContentGrid.Visibility = if ($IsCompact) { 'Collapsed' } else { 'Visible' }
    $NamedElements.CompactContentGrid.Visibility = if ($IsCompact) { 'Visible' } else { 'Collapsed' }
    $NamedElements.FooterGrid.Visibility = if ($IsCompact) { 'Collapsed' } else { 'Visible' }
    $NamedElements.FooterSpacerRow.Height = if ($IsCompact) { [System.Windows.GridLength]::new(0) } else { [System.Windows.GridLength]::new(10) }
    $NamedElements.FooterRow.Height = if ($IsCompact) { [System.Windows.GridLength]::new(0) } else { [System.Windows.GridLength]::Auto }
    if ($NamedElements.ContainsKey('MainContentRow') -and $NamedElements.MainContentRow) {
        $NamedElements.MainContentRow.Height = if ($IsCompact) { [System.Windows.GridLength]::Auto } else { [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
    }

    if ($NamedElements.ContainsKey('RootBorder') -and $NamedElements.RootBorder) {
        if ($IsCompact) {
            $NamedElements.RootBorder.Padding = [System.Windows.Thickness]::new(10)
            $NamedElements.RootBorder.CornerRadius = [System.Windows.CornerRadius]::new(20)
        } else {
            $NamedElements.RootBorder.Padding = [System.Windows.Thickness]::new(16)
            $NamedElements.RootBorder.CornerRadius = [System.Windows.CornerRadius]::new(26)
        }
    }

    if ($IsCompact) {
        $Window.Width = 368
        $Window.MinWidth = 368
        $Window.MaxWidth = 368
        $Window.Height = 292
        $Window.MinHeight = 292
        $Window.MaxHeight = 292
    } else {
        $Window.Width = 412
        $Window.MinWidth = 412
        $Window.MaxWidth = 840
        $Window.Height = 540
        $Window.MinHeight = 540
        $Window.MaxHeight = 1200
    }

    if ($NamedElements.ContainsKey('CompactButton') -and $NamedElements.CompactButton) {
        $NamedElements.CompactButton.Background = if ($IsCompact) { New-Brush '#3349D17C' } else { New-Brush '#18FFFFFF' }
        $NamedElements.CompactButton.BorderBrush = if ($IsCompact) { New-Brush '#6675F0A2' } else { New-Brush '#2EFFFFFF' }
        $NamedElements.CompactButton.Foreground = New-Brush '#FFF5F7FB'
        $NamedElements.CompactButton.Opacity = if ($IsCompact) { 1.0 } else { 0.78 }
        $NamedElements.CompactButton.ToolTip = if ($IsCompact) { 'Switch to full mode' } else { 'Switch to compact mode' }
    }

    if ($script:appConfig) {
        $script:appConfig.IsCompact = $IsCompact
    }

    if ($script:edgeDockState.Enabled) {
        Set-EdgeDockPosition -Window $Window -Hidden $script:edgeDockState.Hidden
    }
}

function Apply-WindowPlacement {
    param(
        $Window,
        $Config
    )

    if (-not $Window -or -not $Config) {
        return
    }

    if ($script:edgeDockState.Enabled) {
        $Window.Top = [double]$Config.Top
        $script:edgeDockState.Hidden = $false
        Set-EdgeDockPosition -Window $Window -Hidden $false
        return
    }

    $screen = Get-EdgeDockScreenRect -Window $Window
    $left = [double]$Config.Left
    $top = [double]$Config.Top

    if ($left -lt ($screen.Left - 60) -or $left -gt ($screen.Right - 120)) {
        $left = $screen.Left + 36
    }
    if ($top -lt ($screen.Top - 60) -or $top -gt ($screen.Bottom - 120)) {
        $top = $screen.Top + 36
    }

    $Window.Left = $left
    $Window.Top = $top
}

function Recover-MainWindowPlacement {
    param(
        $Window,
        [hashtable]$NamedElements = $null
    )

    if (-not $Window) {
        return
    }

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $windowWidth = Get-EdgeDockWindowWidth -Window $Window
    $windowHeight = Get-EdgeDockWindowHeight -Window $Window

    $targetLeft = [double]($screen.Left + [Math]::Max(24, [int](($screen.Width - $windowWidth) / 2)))
    $targetTop = [double]($screen.Top + [Math]::Max(24, [int](($screen.Height - $windowHeight) / 4)))

    $script:edgeDockState.Enabled = $false
    $script:edgeDockState.Hidden = $false
    if ($script:appConfig) {
        $script:appConfig.EnableEdgeSidebar = $false
        $script:appConfig.Left = [Math]::Round($targetLeft, 1)
        $script:appConfig.Top = [Math]::Round($targetTop, 1)
    }

    if (-not $Window.IsVisible) {
        $Window.Show()
    }
    $Window.ShowInTaskbar = $true
    $Window.WindowState = 'Normal'
    $Window.Left = $targetLeft
    $Window.Top = $targetTop
    $Window.Topmost = $script:isPinned
    $Window.Activate() | Out-Null

    if ($NamedElements) {
        Update-EdgeControlsUi -NamedElements $NamedElements
    }
}

function Show-MainWindow {
    param($Window)

    if ($script:edgeDockState.Enabled) {
        Show-EdgeDockWidget -Window $Window -Animate -ActivateWindow
        return
    }

    if (-not $Window.IsVisible) {
        $Window.ShowInTaskbar = $true
        $Window.Show()
    } else {
        $Window.ShowInTaskbar = $true
    }

    $Window.WindowState = 'Normal'
    $Window.Activate() | Out-Null
}

function Reveal-MainWindowNow {
    param($Window)

    if (-not $Window) {
        return
    }

    if ($script:edgeDockState.Enabled) {
        Show-EdgeDockWidget -Window $Window -Animate -ActivateWindow
        if (-not (Test-WindowVisibleOnAnyScreen -Window $Window)) {
            Recover-MainWindowPlacement -Window $Window
        }
    } else {
        if (-not $Window.IsVisible) {
            $Window.Show()
        }
        $Window.ShowInTaskbar = $true
        $Window.WindowState = 'Normal'

        $screen = Get-EdgeDockScreenRect -Window $Window
        $windowWidth = Get-EdgeDockWindowWidth -Window $Window
        $windowHeight = Get-EdgeDockWindowHeight -Window $Window
        $maxLeft = [double]($screen.Right - $windowWidth - 8)
        $maxTop = [double]($screen.Bottom - $windowHeight - 8)
        if ($Window.Left -lt ($screen.Left - 120) -or $Window.Left -gt ($screen.Right + 60)) {
            $Window.Left = $screen.Left + 80
        }
        if ($Window.Top -lt ($screen.Top - 120) -or $Window.Top -gt ($screen.Bottom + 60)) {
            $Window.Top = $screen.Top + 80
        }
        if ($Window.Left -lt $screen.Left) {
            $Window.Left = [double]$screen.Left
        }
        if ($Window.Left -gt $maxLeft) {
            $Window.Left = $maxLeft
        }
        if ($Window.Top -lt $screen.Top) {
            $Window.Top = [double]$screen.Top
        }
        if ($Window.Top -gt $maxTop) {
            $Window.Top = $maxTop
        }
        if (-not (Test-WindowVisibleOnAnyScreen -Window $Window)) {
            Recover-MainWindowPlacement -Window $Window
        }
    }

    $Window.WindowState = 'Normal'
    $Window.Topmost = $script:isPinned
    $Window.Activate() | Out-Null
}

function Ensure-MainWindowVisible {
    param(
        $Window,
        [hashtable]$NamedElements = $null
    )

    if (-not $Window) {
        return
    }

    try {
        Reveal-MainWindowNow -Window $Window
    } catch {
    }

    if ((-not $Window.IsVisible) -or (-not (Test-WindowVisibleOnAnyScreen -Window $Window))) {
        Recover-MainWindowPlacement -Window $Window -NamedElements $NamedElements
    }

    if (-not $Window.IsVisible) {
        $Window.Show()
    }
    $Window.ShowInTaskbar = $true
    $Window.WindowState = 'Normal'
    $Window.Topmost = $script:isPinned
    $Window.Activate() | Out-Null

    if ($NamedElements) {
        Update-EdgeControlsUi -NamedElements $NamedElements
    }
}

function Hide-MainWindow {
    param($Window)

    if (-not $Window.IsVisible) {
        return
    }

    Save-AppState -Window $Window
    $Window.ShowInTaskbar = $false
    $Window.Hide()
}

function Update-TrayMenu {
    param(
        $Window,
        $ShowHideMenuItem,
        $CompactMenuItem,
        $NotificationMenuItem,
        $StartupMenuItem,
        $SidebarMenuItem = $null
    )

    $ShowHideMenuItem.Text = 'Show now'

    if ($script:appConfig) {
        $CompactMenuItem.Checked = [bool]$script:appConfig.IsCompact
        $NotificationMenuItem.Checked = [bool]$script:appConfig.EnableInternetNotifications
        if ($SidebarMenuItem) {
            $SidebarMenuItem.Checked = [bool]$script:edgeDockState.Enabled
        }
    }
    $StartupMenuItem.Checked = Get-StartupEnabled
}

function Exit-WidgetApplication {
    param($Window)

    $script:isExiting = $true
    Save-AppState -Window $Window
    $Window.Close()
}

function Get-CurrentProcessExecutablePath {
    try {
        return [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    } catch {
        return $null
    }
}

function Get-AppNotifyIcon {
    $processPath = Get-CurrentProcessExecutablePath
    if ($processPath) {
        $processName = [System.IO.Path]::GetFileName($processPath)
        if ($processName -notmatch '^(powershell|pwsh|powershell_ise)\.exe$') {
            try {
                $processIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($processPath)
                if ($processIcon) {
                    return $processIcon
                }
            } catch {
            }
        }
    }

    if (Test-Path -LiteralPath $script:appIconPath) {
        try {
            return New-Object System.Drawing.Icon($script:appIconPath)
        } catch {
        }
    }

    return [System.Drawing.SystemIcons]::Information
}

function Set-WindowIcon {
    param($Window)

    try {
        $processPath = Get-CurrentProcessExecutablePath
        if ($processPath) {
            $processName = [System.IO.Path]::GetFileName($processPath)
            if ($processName -notmatch '^(powershell|pwsh|powershell_ise)\.exe$') {
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($processPath)
                if ($icon) {
                    $Window.Icon = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                        $icon.Handle,
                        [System.Windows.Int32Rect]::Empty,
                        [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
                    )
                    return
                }
            }
        }
    } catch {
    }

    if (-not (Test-Path -LiteralPath $script:appIconPath)) {
        return
    }

    try {
        $iconUri = [Uri]::new($script:appIconPath)
        $Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconUri)
    } catch {
    }
}

function Set-InternetAlertVisual {
    param(
        [hashtable]$NamedElements,
        [string]$Mode,
        [string]$Title = '',
        [string]$Message = ''
    )

    if ($Mode -eq 'none') {
        $NamedElements.InternetAlertPanel.Visibility = 'Collapsed'
        $NamedElements.InternetAlertTitle.Text = ''
        $NamedElements.InternetAlertMessage.Text = ''
        return
    }

    $NamedElements.InternetAlertPanel.Visibility = 'Visible'
    $NamedElements.InternetAlertTitle.Text = $Title
    $NamedElements.InternetAlertMessage.Text = $Message

    switch ($Mode) {
        'offline' {
            $NamedElements.InternetAlertPanel.Background = New-Brush '#E0471717'
            $NamedElements.InternetAlertPanel.BorderBrush = New-Brush '#88FF8B8B'
            $NamedElements.InternetAlertTitle.Foreground = New-Brush '#FFFFE5E5'
            $NamedElements.InternetAlertMessage.Foreground = New-Brush '#FFF9D0D0'
        }
        'restored' {
            $NamedElements.InternetAlertPanel.Background = New-Brush '#DE143E2A'
            $NamedElements.InternetAlertPanel.BorderBrush = New-Brush '#8858D68D'
            $NamedElements.InternetAlertTitle.Foreground = New-Brush '#FFE7FFF0'
            $NamedElements.InternetAlertMessage.Foreground = New-Brush '#FFD4FBE1'
        }
        default {
            $NamedElements.InternetAlertPanel.Background = New-Brush '#CC1F2B3D'
            $NamedElements.InternetAlertPanel.BorderBrush = New-Brush '#6679A7D3'
            $NamedElements.InternetAlertTitle.Foreground = New-Brush '#FFF5F7FB'
            $NamedElements.InternetAlertMessage.Foreground = New-Brush '#FFD6E8F9'
        }
    }
}

function Show-InternetBalloonTip {
    param(
        $NotifyIcon,
        [string]$Title,
        [string]$Message,
        [System.Windows.Forms.ToolTipIcon]$Icon = [System.Windows.Forms.ToolTipIcon]::Info,
        [int]$TimeoutMs = 4000
    )

    if (-not $script:appConfig.EnableInternetNotifications) {
        return
    }

    try {
        $NotifyIcon.BalloonTipTitle = $Title
        $NotifyIcon.BalloonTipText = $Message
        $NotifyIcon.BalloonTipIcon = $Icon
        $NotifyIcon.ShowBalloonTip($TimeoutMs)
    } catch {
    }
}

function Update-InternetAlertState {
    param(
        $Snapshot,
        [hashtable]$NamedElements,
        $NotifyIcon
    )

    $now = Get-Date
    $isOnline = [bool]$Snapshot.InternetOnline
    $detail = if ($Snapshot.InternetDetail) { $Snapshot.InternetDetail } else { 'Unknown network' }

    if ($null -eq $script:lastInternetOnline) {
        $script:lastInternetOnline = $isOnline
        if (-not $isOnline) {
            $script:internetAlertMode = 'offline'
            $script:internetOfflineDetectedAt = if ($Snapshot.InternetOfflineSince) { $Snapshot.InternetOfflineSince } else { $now }
            $script:internetDesktopAlerted = $false
        }
    } elseif ($script:lastInternetOnline -ne $isOnline) {
        if ($isOnline) {
            $script:internetAlertMode = 'restored'
            $script:internetAlertUntil = $now.AddSeconds(8)
            if ($script:internetDesktopAlerted) {
                Show-InternetBalloonTip -NotifyIcon $NotifyIcon -Title 'System Monitor' -Message ('Da ket noi lai: ' + $detail) -Icon ([System.Windows.Forms.ToolTipIcon]::Info) -TimeoutMs 3500
            }
            $script:internetOfflineDetectedAt = $null
            $script:internetDesktopAlerted = $false
        } else {
            $script:internetAlertMode = 'offline'
            $script:internetAlertUntil = [datetime]::MaxValue
            $script:internetOfflineDetectedAt = $now
            $script:internetDesktopAlerted = $false
        }

        $script:lastInternetOnline = $isOnline
    }

    if (-not $isOnline) {
        $offlineSince = if ($Snapshot.InternetOfflineSince) { $Snapshot.InternetOfflineSince } elseif ($script:internetOfflineDetectedAt) { $script:internetOfflineDetectedAt } else { $now }
        $offlineSeconds = [Math]::Max(0, [int](($now - $offlineSince).TotalSeconds))
        if (-not $script:internetOfflineDetectedAt) {
            $script:internetOfflineDetectedAt = $offlineSince
        }

        if (-not $script:internetDesktopAlerted -and $offlineSeconds -ge 4) {
            Show-InternetBalloonTip -NotifyIcon $NotifyIcon -Title 'System Monitor' -Message ('Mat ket noi Internet ' + (Format-Duration -TotalSeconds $offlineSeconds)) -Icon ([System.Windows.Forms.ToolTipIcon]::Warning) -TimeoutMs 4000
            $script:internetDesktopAlerted = $true
        }

        Set-InternetAlertVisual -NamedElements $NamedElements -Mode 'offline' -Title 'Internet disconnected' -Message (Get-OfflineDurationText -OfflineSince $Snapshot.InternetOfflineSince)
        return
    }

    if ($script:internetAlertMode -eq 'restored') {
        if ($now -gt $script:internetAlertUntil) {
            $script:internetAlertMode = 'none'
            Set-InternetAlertVisual -NamedElements $NamedElements -Mode 'none'
            return
        }

        Set-InternetAlertVisual -NamedElements $NamedElements -Mode 'restored' -Title 'Internet restored' -Message $detail
        return
    }

    $script:internetAlertMode = 'none'
    Set-InternetAlertVisual -NamedElements $NamedElements -Mode 'none'
}

function Resolve-RyzenAdjPath {
    $candidates = @(
        (Join-Path $script:widgetBasePath 'amd\ryzenadj.exe'),
        (Join-Path $script:widgetBasePath 'ryzenadj.exe'),
        (Join-Path $script:widgetBasePath 'deps\amd\ryzenadj.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Get-RyzenAdjMetricValue {
    param(
        [string]$OutputText,
        [string]$MetricName
    )

    if (-not $OutputText -or -not $MetricName) {
        return $null
    }

    $escapedName = [regex]::Escape($MetricName)
    $match = [regex]::Match($OutputText, "(?im)^\|\s*$escapedName\s*\|\s*([0-9]+(?:\.[0-9]+)?)\s*\|")
    if (-not $match.Success) {
        return $null
    }

    $parsedValue = 0.0
    if ([double]::TryParse($match.Groups[1].Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedValue)) {
        return [Math]::Round($parsedValue, 1)
    }

    return $null
}

function Get-RyzenAdjInfoSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RyzenAdjPath
    )

    $output = & $RyzenAdjPath --info 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = ($output -join "`n")

    $stapmLimit = Get-RyzenAdjMetricValue -OutputText $outputText -MetricName 'STAPM LIMIT'
    $fastLimit = Get-RyzenAdjMetricValue -OutputText $outputText -MetricName 'PPT LIMIT FAST'
    $slowLimit = Get-RyzenAdjMetricValue -OutputText $outputText -MetricName 'PPT LIMIT SLOW'

    $isAvailable = ($null -ne $stapmLimit) -and ($exitCode -eq 0)
    $message = if ($isAvailable) {
        'TDP controller ready'
    } elseif ($outputText -match '(?i)Driver not found|Unable to init') {
        'TDP driver unavailable'
    } elseif ($outputText -match '(?i)check permission|not writeable|access') {
        'Run widget as administrator'
    } elseif ($outputText) {
        ($outputText -split "`n" | Select-Object -First 1).Trim()
    } else {
        'TDP controller unavailable'
    }

    return [PSCustomObject]@{
        IsAvailable   = $isAvailable
        Message       = $message
        Output        = $outputText
        ExitCode      = $exitCode
        StapmLimitW   = $stapmLimit
        FastLimitW    = $fastLimit
        SlowLimitW    = $slowLimit
    }
}

function Refresh-PerformanceState {
    param(
        [int]$CacheSeconds = 8,
        [switch]$Force
    )

    $now = Get-Date
    if (-not $Force -and (($now - $script:performanceState.CheckedAt).TotalSeconds -lt [Math]::Max($CacheSeconds, 1))) {
        return $script:performanceState
    }

    $ryzenAdjPath = Resolve-RyzenAdjPath
    if (-not $ryzenAdjPath) {
        $script:performanceState = [PSCustomObject]@{
            CheckedAt          = $now
            RyzenAdjPath       = $null
            IsAvailable        = $false
            CurrentLimitW      = $null
            FastLimitW         = $null
            SlowLimitW         = $null
            LastMessage        = 'ryzenadj not found'
            LastError          = 'ryzenadj not found'
            LastApplyAt        = $script:performanceState.LastApplyAt
            LastAppliedW       = $script:performanceState.LastAppliedW
            LastApplySucceeded = $false
        }
        return $script:performanceState
    }

    $info = Get-RyzenAdjInfoSnapshot -RyzenAdjPath $ryzenAdjPath
    $lastMessage = $info.Message
    if ($info.IsAvailable -and $script:performanceState.LastApplySucceeded -and $script:performanceState.LastAppliedW -and ($now - $script:performanceState.LastApplyAt).TotalSeconds -lt 25) {
        $lastMessage = ('Applied {0}W' -f [int]$script:performanceState.LastAppliedW)
    }

    $script:performanceState = [PSCustomObject]@{
        CheckedAt          = $now
        RyzenAdjPath       = $ryzenAdjPath
        IsAvailable        = $info.IsAvailable
        CurrentLimitW      = $info.StapmLimitW
        FastLimitW         = $info.FastLimitW
        SlowLimitW         = $info.SlowLimitW
        LastMessage        = $lastMessage
        LastError          = if ($info.IsAvailable) { $null } else { $info.Message }
        LastApplyAt        = $script:performanceState.LastApplyAt
        LastAppliedW       = $script:performanceState.LastAppliedW
        LastApplySucceeded = $script:performanceState.LastApplySucceeded
    }

    return $script:performanceState
}

function Ensure-DisplayApiTypes {
    $existingType = [type]::GetType('SystemMonitor.NativeDisplay, System.Private.CoreLib', $false)
    if ($existingType) {
        return $true
    }

    $alreadyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
        ForEach-Object { $_.GetType('SystemMonitor.NativeDisplay', $false) } |
        Where-Object { $_ } |
        Select-Object -First 1
    if ($alreadyLoaded) {
        return $true
    }

    $displayApiCode = @"
using System;
using System.Runtime.InteropServices;
namespace SystemMonitor {
    public static class NativeDisplay {
        public const int ENUM_CURRENT_SETTINGS = -1;
        public const int DM_DISPLAYFREQUENCY = 0x400000;
        public const int CDS_TEST = 0x00000002;
        public const int DISP_CHANGE_SUCCESSFUL = 0;
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int ChangeDisplaySettings(ref DEVMODE lpDevMode, int dwFlags);
    }
}
"@

    try {
        Add-Type -TypeDefinition $displayApiCode -Language CSharp -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Convert-DisplayChangeResultToMessage {
    param([int]$ResultCode)

    switch ($ResultCode) {
        0 { return 'Applied refresh rate' }
        1 { return 'Display change requires restart' }
        -1 { return 'Display change failed' }
        -2 { return 'Refresh rate mode not supported' }
        -3 { return 'Display settings were not updated' }
        -4 { return 'Invalid display change flags' }
        -5 { return 'Invalid display mode parameters' }
        -6 { return 'Display change is not supported in current mode' }
        default { return ('Display API error {0}' -f $ResultCode) }
    }
}

function Get-DisplayModeSnapshot {
    if (-not (Ensure-DisplayApiTypes)) {
        return $null
    }

    $typeName = 'SystemMonitor.NativeDisplay+DEVMODE'
    $size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]$typeName)
    $deviceName = [System.Windows.Forms.Screen]::PrimaryScreen.DeviceName
    $current = New-Object $typeName
    $current.dmSize = $size

    if (-not [SystemMonitor.NativeDisplay]::EnumDisplaySettings($deviceName, [SystemMonitor.NativeDisplay]::ENUM_CURRENT_SETTINGS, [ref]$current)) {
        return $null
    }

    $supported = New-Object 'System.Collections.Generic.List[int]'
    $index = 0
    while ($true) {
        $mode = New-Object $typeName
        $mode.dmSize = $size
        if (-not [SystemMonitor.NativeDisplay]::EnumDisplaySettings($deviceName, $index, [ref]$mode)) {
            break
        }

        if ($mode.dmPelsWidth -eq $current.dmPelsWidth -and
            $mode.dmPelsHeight -eq $current.dmPelsHeight -and
            $mode.dmBitsPerPel -eq $current.dmBitsPerPel -and
            $mode.dmDisplayFrequency -gt 0) {
            if (-not $supported.Contains([int]$mode.dmDisplayFrequency)) {
                $supported.Add([int]$mode.dmDisplayFrequency)
            }
        }

        $index++
    }

    if ($supported.Count -eq 0 -and $current.dmDisplayFrequency -gt 0) {
        $supported.Add([int]$current.dmDisplayFrequency)
    }

    $supportedSorted = @($supported | Sort-Object)
    return [PSCustomObject]@{
        Width       = [int]$current.dmPelsWidth
        Height      = [int]$current.dmPelsHeight
        BitsPerPel  = [int]$current.dmBitsPerPel
        CurrentHz   = if ($current.dmDisplayFrequency -gt 0) { [int]$current.dmDisplayFrequency } else { $null }
        SupportedHz = $supportedSorted
    }
}

function Refresh-RefreshRateState {
    param(
        [int]$CacheSeconds = 8,
        [switch]$Force
    )

    $now = Get-Date
    if (-not $Force -and (($now - $script:refreshRateState.CheckedAt).TotalSeconds -lt [Math]::Max($CacheSeconds, 1))) {
        return $script:refreshRateState
    }

    $snapshot = Get-DisplayModeSnapshot
    if (-not $snapshot -or $null -eq $snapshot.CurrentHz) {
        $script:refreshRateState = [PSCustomObject]@{
            CheckedAt          = $now
            CurrentHz          = $null
            SupportedHz        = @()
            Supports60         = $false
            Supports120        = $false
            LastMessage        = 'Refresh rate unavailable'
            LastApplyAt        = $script:refreshRateState.LastApplyAt
            LastAppliedHz      = $script:refreshRateState.LastAppliedHz
            LastApplySucceeded = $false
            LastApplyStatus    = if ($script:refreshRateState.LastApplyStatus) { $script:refreshRateState.LastApplyStatus } else { 'Error' }
        }
        return $script:refreshRateState
    }

    $supportedHz = @($snapshot.SupportedHz)
    $supports60 = $supportedHz -contains 60
    $supports120 = $supportedHz -contains 120
    $recentApply = ($now - $script:refreshRateState.LastApplyAt).TotalSeconds -lt 25 -and $script:refreshRateState.LastApplyAt -gt [datetime]::MinValue
    $defaultMessage = 'Refresh {0}Hz' -f $snapshot.CurrentHz
    if (-not $supports120) {
        $defaultMessage += ' (120Hz unavailable)'
    }
    $lastMessage = if ($recentApply -and $script:refreshRateState.LastMessage) { $script:refreshRateState.LastMessage } else { $defaultMessage }

    $script:refreshRateState = [PSCustomObject]@{
        CheckedAt          = $now
        CurrentHz          = [int]$snapshot.CurrentHz
        SupportedHz        = $supportedHz
        Supports60         = $supports60
        Supports120        = $supports120
        LastMessage        = $lastMessage
        LastApplyAt        = $script:refreshRateState.LastApplyAt
        LastAppliedHz      = $script:refreshRateState.LastAppliedHz
        LastApplySucceeded = $script:refreshRateState.LastApplySucceeded
        LastApplyStatus    = if ($script:refreshRateState.LastApplyStatus) { $script:refreshRateState.LastApplyStatus } else { 'Idle' }
    }

    return $script:refreshRateState
}

function Invoke-RefreshRatePreset {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(60, 120)]
        [int]$Hz
    )

    $state = Refresh-RefreshRateState -Force
    if ($null -eq $state.CurrentHz) {
        $script:refreshRateState.LastApplySucceeded = $false
        $script:refreshRateState.LastApplyStatus = 'Error'
        $script:refreshRateState.LastAppliedHz = $Hz
        $script:refreshRateState.LastApplyAt = Get-Date
        $script:refreshRateState.LastMessage = 'Refresh rate API unavailable'
        return [PSCustomObject]@{ Success = $false; Message = 'Refresh rate API unavailable' }
    }

    if (-not ($state.SupportedHz -contains $Hz)) {
        $script:refreshRateState.LastApplySucceeded = $false
        $script:refreshRateState.LastApplyStatus = 'Error'
        $script:refreshRateState.LastAppliedHz = $Hz
        $script:refreshRateState.LastApplyAt = Get-Date
        $script:refreshRateState.LastMessage = ('{0}Hz not supported on current display mode' -f $Hz)
        return [PSCustomObject]@{ Success = $false; Message = $script:refreshRateState.LastMessage }
    }

    if ($state.CurrentHz -eq $Hz) {
        $script:refreshRateState.LastApplySucceeded = $true
        $script:refreshRateState.LastApplyStatus = 'Applied'
        $script:refreshRateState.LastAppliedHz = $Hz
        $script:refreshRateState.LastApplyAt = Get-Date
        $script:refreshRateState.LastMessage = ('Refresh already {0}Hz' -f $Hz)
        return [PSCustomObject]@{ Success = $true; Message = $script:refreshRateState.LastMessage }
    }

    if (-not (Ensure-DisplayApiTypes)) {
        $script:refreshRateState.LastApplySucceeded = $false
        $script:refreshRateState.LastApplyStatus = 'Error'
        $script:refreshRateState.LastAppliedHz = $Hz
        $script:refreshRateState.LastApplyAt = Get-Date
        $script:refreshRateState.LastMessage = 'Display API unavailable'
        return [PSCustomObject]@{ Success = $false; Message = 'Display API unavailable' }
    }

    $typeName = 'SystemMonitor.NativeDisplay+DEVMODE'
    $size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]$typeName)
    $deviceName = [System.Windows.Forms.Screen]::PrimaryScreen.DeviceName
    $devmode = New-Object $typeName
    $devmode.dmSize = $size
    if (-not [SystemMonitor.NativeDisplay]::EnumDisplaySettings($deviceName, [SystemMonitor.NativeDisplay]::ENUM_CURRENT_SETTINGS, [ref]$devmode)) {
        $script:refreshRateState.LastApplySucceeded = $false
        $script:refreshRateState.LastApplyStatus = 'Error'
        $script:refreshRateState.LastAppliedHz = $Hz
        $script:refreshRateState.LastApplyAt = Get-Date
        $script:refreshRateState.LastMessage = 'Could not read current display mode'
        return [PSCustomObject]@{ Success = $false; Message = 'Could not read current display mode' }
    }

    $devmode.dmDisplayFrequency = $Hz
    $devmode.dmFields = $devmode.dmFields -bor [SystemMonitor.NativeDisplay]::DM_DISPLAYFREQUENCY
    $testResult = [SystemMonitor.NativeDisplay]::ChangeDisplaySettings([ref]$devmode, [SystemMonitor.NativeDisplay]::CDS_TEST)
    if ($testResult -ne [SystemMonitor.NativeDisplay]::DISP_CHANGE_SUCCESSFUL) {
        $message = Convert-DisplayChangeResultToMessage -ResultCode $testResult
        $script:refreshRateState.LastApplySucceeded = $false
        $script:refreshRateState.LastApplyStatus = 'Error'
        $script:refreshRateState.LastAppliedHz = $Hz
        $script:refreshRateState.LastApplyAt = Get-Date
        $script:refreshRateState.LastMessage = $message
        return [PSCustomObject]@{ Success = $false; Message = $message }
    }

    $applyResult = [SystemMonitor.NativeDisplay]::ChangeDisplaySettings([ref]$devmode, 0)
    Start-Sleep -Milliseconds 220
    $refreshed = Refresh-RefreshRateState -Force
    $success = ($applyResult -eq [SystemMonitor.NativeDisplay]::DISP_CHANGE_SUCCESSFUL) -and ($refreshed.CurrentHz -eq $Hz)
    $message = if ($success) { 'Refresh applied {0}Hz' -f $Hz } else { Convert-DisplayChangeResultToMessage -ResultCode $applyResult }

    $script:refreshRateState.LastApplySucceeded = $success
    $script:refreshRateState.LastApplyStatus = if ($success) { 'Applied' } else { 'Error' }
    $script:refreshRateState.LastAppliedHz = $Hz
    $script:refreshRateState.LastApplyAt = Get-Date
    $script:refreshRateState.LastMessage = $message

    return [PSCustomObject]@{
        Success = $success
        Message = $message
    }
}

function Refresh-FanState {
    param(
        [int]$CacheSeconds = 2,
        [switch]$Force
    )

    $now = Get-Date
    if (-not $Force -and (($now - $script:fanState.CheckedAt).TotalSeconds -lt [Math]::Max($CacheSeconds, 1))) {
        return $script:fanState
    }

    $holdSnapshot = Enforce-FanManualHold
    $snapshot = if ($holdSnapshot) { $holdSnapshot } else { Get-DirectFanControllerSnapshot }
    $mode = if ($script:fanState.ManualHoldEnabled -and $script:fanState.RequestedMode) {
        $script:fanState.RequestedMode
    } else {
        $snapshot.Mode
    }
    $isAvailable = [bool]$snapshot.IsAvailable
    $recentApply = $script:fanState.LastApplyAt -gt [datetime]::MinValue -and (($now - $script:fanState.LastApplyAt).TotalSeconds -lt 25)
    $message = if ($recentApply -and $script:fanState.LastMessage) {
        $script:fanState.LastMessage
    } elseif ($isAvailable) {
        if ($script:fanState.ManualHoldEnabled -and $script:fanState.RequestedMode) {
            'Fan mode: ' + $mode + ' | ' + [int]$snapshot.Rpm + ' rpm (manual hold)'
        } else {
            'Fan mode: ' + $mode + ' | ' + [int]$snapshot.Rpm + ' rpm'
        }
    } else {
        if ($snapshot.Message) { $snapshot.Message } else { 'Fan controller unavailable' }
    }

    $script:fanState = [PSCustomObject]@{
        CheckedAt          = $now
        Mode               = $mode
        IsAvailable        = $isAvailable
        LastMessage        = $message
        CurrentRpm         = $snapshot.Rpm
        CurrentPwm         = $snapshot.PwmRaw
        RequestedMode      = $script:fanState.RequestedMode
        RequestedPwm       = $script:fanState.RequestedPwm
        ManualHoldEnabled  = $script:fanState.ManualHoldEnabled
        LastEnforceAt      = $script:fanState.LastEnforceAt
        LastApplyAt        = $script:fanState.LastApplyAt
        LastApplyMode      = $script:fanState.LastApplyMode
        LastApplySucceeded = $script:fanState.LastApplySucceeded
        LastApplyStatus    = if ($script:fanState.LastApplyStatus) { $script:fanState.LastApplyStatus } else { 'Idle' }
    }

    return $script:fanState
}

function Invoke-FanModePreset {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Low', 'Medium', 'Max', 'Auto')]
        [string]$Mode
    )

    $script:fanState.LastApplySucceeded = $false
    $script:fanState.LastApplyStatus = 'Pending'
    $script:fanState.LastApplyMode = $Mode
    $script:fanState.LastApplyAt = Get-Date
    $script:fanState.LastMessage = 'Applying fan mode ' + $Mode + '...'

    $targetPwm = Get-FanModeTargetPwm -Mode $Mode
    $apply = Set-DirectFanMode -Mode $Mode
    $success = [bool]$apply.Success
    $message = if ($apply.Message) { $apply.Message } else { if ($success) { 'Fan mode: ' + $Mode } else { 'Fan mode apply failed' } }

    $script:fanState.LastApplySucceeded = $success
    $script:fanState.LastApplyStatus = if ($success) { 'Applied' } else { 'Error' }
    $script:fanState.LastApplyMode = $Mode
    $script:fanState.LastApplyAt = Get-Date
    $script:fanState.LastMessage = $message
    if ($success) {
        $script:fanState.RequestedMode = $Mode
        $script:fanState.RequestedPwm = $targetPwm
        $script:fanState.ManualHoldEnabled = $Mode -ne 'Auto'
        $script:fanState.LastEnforceAt = [datetime]::MinValue
        if ($script:fanState.ManualHoldEnabled) {
            [void](Enforce-FanManualHold -Force)
        }
    }

    if ($apply.Snapshot) {
        $script:fanState.CurrentRpm = $apply.Snapshot.Rpm
        $script:fanState.CurrentPwm = $apply.Snapshot.PwmRaw
        $script:fanState.Mode = if ($success) { $Mode } else { $apply.Snapshot.Mode }
        $script:fanState.IsAvailable = $true
    }

    return [PSCustomObject]@{
        Success = $success
        Message = $message
    }
}

function Invoke-TdpPreset {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Watts,
        [int]$TempC = 85
    )

    $Watts = [Math]::Max($script:tdpCustomRange.MinW, [Math]::Min($script:tdpCustomRange.MaxW, [int]$Watts))

    $state = Refresh-PerformanceState -Force
    if (-not $state.RyzenAdjPath) {
        $script:performanceState.LastApplySucceeded = $false
        $script:performanceState.LastAppliedW = $Watts
        $script:performanceState.LastApplyAt = Get-Date
        $script:performanceState.LastMessage = 'ryzenadj not found'
        return [PSCustomObject]@{ Success = $false; Message = 'ryzenadj not found' }
    }

    $mw = $Watts * 1000
    $args = @(
        "--stapm-limit=$mw",
        "--fast-limit=$mw",
        "--slow-limit=$mw",
        "--tctl-temp=$TempC"
    )

    $output = & $state.RyzenAdjPath @args 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = ($output -join "`n")
    $reportedSuccess = ($exitCode -eq 0) -and ($outputText -match '(?i)sucessfully set|successfully set')

    $refreshed = Refresh-PerformanceState -Force
    $applied = $false
    if ($null -ne $refreshed.CurrentLimitW) {
        $applied = [Math]::Abs($refreshed.CurrentLimitW - $Watts) -le 0.6
    }

    $success = $reportedSuccess -and $applied
    $message = if ($success) {
        'Applied {0}W' -f $Watts
    } elseif ($outputText -match '(?i)permission|access|not writeable') {
        'Run widget as administrator'
    } elseif ($outputText -match '(?i)Driver not found|Unable to init') {
        'TDP driver unavailable'
    } elseif ($outputText) {
        ($outputText -split "`n" | Select-Object -First 1).Trim()
    } else {
        'Failed to apply TDP preset'
    }

    $script:performanceState.LastApplySucceeded = $success
    $script:performanceState.LastAppliedW = $Watts
    $script:performanceState.LastApplyAt = Get-Date
    $script:performanceState.LastMessage = $message
    if (-not $success) {
        $script:performanceState.LastError = $message
    }

    return [PSCustomObject]@{
        Success = $success
        Message = $message
    }
}

function Set-TdpPresetVisual {
    param(
        [hashtable]$NamedElements,
        [Nullable[Double]]$CurrentLimitW
    )

    foreach ($preset in $script:tdpPresetLevels) {
        $buttonName = 'TdpPreset{0}Button' -f $preset
        if (-not $NamedElements.ContainsKey($buttonName)) {
            continue
        }

        $button = $NamedElements[$buttonName]
        if (-not $button) {
            continue
        }

        $isActive = ($null -ne $CurrentLimitW) -and ([Math]::Abs($CurrentLimitW - $preset) -le 0.6)
        $button.Background = if ($isActive) { New-Brush '#3358D68D' } else { New-Brush '#14FFFFFF' }
        $button.BorderBrush = if ($isActive) { New-Brush '#6676F0A5' } else { New-Brush '#2DFFFFFF' }
        $button.Foreground = if ($isActive) { New-Brush '#FFF6FFF9' } else { New-Brush '#FFDDECF9' }
    }

    if ($NamedElements.ContainsKey('TdpCustomToggleButton') -and $NamedElements.TdpCustomToggleButton) {
        $isPresetMatch = $false
        if ($null -ne $CurrentLimitW) {
            foreach ($preset in $script:tdpPresetLevels) {
                if ([Math]::Abs($CurrentLimitW - $preset) -le 0.6) {
                    $isPresetMatch = $true
                    break
                }
            }
        }

        $isCustomActive = ($null -ne $CurrentLimitW) -and (-not $isPresetMatch)
        $isPanelOpen = if ($script:appConfig) { [bool]$script:appConfig.ShowTdpCustomPanel } else { $false }
        $NamedElements.TdpCustomToggleButton.Background = if ($isPanelOpen -or $isCustomActive) { New-Brush '#335B8DFF' } else { New-Brush '#14FFFFFF' }
        $NamedElements.TdpCustomToggleButton.BorderBrush = if ($isPanelOpen -or $isCustomActive) { New-Brush '#6690B8FF' } else { New-Brush '#2DFFFFFF' }
        $NamedElements.TdpCustomToggleButton.Foreground = New-Brush '#FFF5F7FB'
    }
}

function Set-TdpCustomPanelState {
    param(
        [hashtable]$NamedElements,
        [bool]$IsVisible
    )

    if ($NamedElements.ContainsKey('TdpCustomPanel') -and $NamedElements.TdpCustomPanel) {
        $NamedElements.TdpCustomPanel.Visibility = if ($IsVisible) { 'Visible' } else { 'Collapsed' }
    }
    if ($NamedElements.ContainsKey('TdpCustomApplyButton') -and $NamedElements.TdpCustomApplyButton) {
        $NamedElements.TdpCustomApplyButton.Visibility = if ($IsVisible) { 'Visible' } else { 'Collapsed' }
    }

    if ($script:appConfig) {
        $script:appConfig.ShowTdpCustomPanel = $IsVisible
    }
}

function Set-ModesPanelState {
    param(
        [hashtable]$NamedElements,
        [bool]$IsVisible
    )

    if ($NamedElements.ContainsKey('ModesPanel') -and $NamedElements.ModesPanel) {
        $NamedElements.ModesPanel.Visibility = if ($IsVisible) { 'Visible' } else { 'Collapsed' }
    }

    if ($NamedElements.ContainsKey('ModesToggleButton') -and $NamedElements.ModesToggleButton) {
        $NamedElements.ModesToggleButton.Background = if ($IsVisible) { New-Brush '#335B8DFF' } else { New-Brush '#14FFFFFF' }
        $NamedElements.ModesToggleButton.BorderBrush = if ($IsVisible) { New-Brush '#6690B8FF' } else { New-Brush '#2DFFFFFF' }
        $NamedElements.ModesToggleButton.Foreground = New-Brush '#FFF5F7FB'
    }

    if ($script:appConfig) {
        $script:appConfig.ShowModesPanel = $IsVisible
    }
}

function Set-FpsPresetVisual {
    param(
        [hashtable]$NamedElements,
        [int]$FpsLimiter
    )

    $buttonMap = @{
        0  = 'FpsOffButton'
        30 = 'Fps30Button'
        45 = 'Fps45Button'
        60 = 'Fps60Button'
    }

    foreach ($fps in $buttonMap.Keys) {
        $buttonName = $buttonMap[$fps]
        if (-not $NamedElements.ContainsKey($buttonName)) {
            continue
        }

        $button = $NamedElements[$buttonName]
        if (-not $button) {
            continue
        }

        $isActive = ($FpsLimiter -eq $fps)
        $button.Background = if ($isActive) { New-Brush '#3358D68D' } else { New-Brush '#14FFFFFF' }
        $button.BorderBrush = if ($isActive) { New-Brush '#6676F0A5' } else { New-Brush '#2DFFFFFF' }
        $button.Foreground = if ($isActive) { New-Brush '#FFF6FFF9' } else { New-Brush '#FFDDECF9' }
    }
}

function Set-FanPresetVisual {
    param(
        [hashtable]$NamedElements,
        [string]$Mode
    )

    foreach ($preset in @('Low', 'Medium', 'Max', 'Auto')) {
        $buttonName = 'Fan{0}Button' -f $preset
        if (-not $NamedElements.ContainsKey($buttonName)) {
            continue
        }

        $button = $NamedElements[$buttonName]
        if (-not $button) {
            continue
        }

        $isActive = $Mode -eq $preset
        $button.Background = if ($isActive) { New-Brush '#3347B7FF' } else { New-Brush '#14FFFFFF' }
        $button.BorderBrush = if ($isActive) { New-Brush '#6689D8FF' } else { New-Brush '#2DFFFFFF' }
        $button.Foreground = if ($isActive) { New-Brush '#FFF7FCFF' } else { New-Brush '#FFDDECF9' }
    }
}

function Set-RefreshPresetVisual {
    param(
        [hashtable]$NamedElements,
        [Nullable[int]]$CurrentHz,
        [bool]$Supports60,
        [bool]$Supports120
    )

    foreach ($preset in $script:refreshPresetLevels) {
        $buttonName = 'Hz{0}Button' -f $preset
        if (-not $NamedElements.ContainsKey($buttonName)) {
            continue
        }

        $button = $NamedElements[$buttonName]
        if (-not $button) {
            continue
        }

        $isSupported = if ($preset -eq 60) { $Supports60 } else { $Supports120 }
        $isActive = $isSupported -and ($null -ne $CurrentHz) -and ($CurrentHz -eq $preset)

        $button.IsEnabled = $isSupported
        $button.Opacity = if ($isSupported) { 1.0 } else { 0.45 }
        $button.ToolTip = if ($isSupported) { ('Switch to {0}Hz' -f $preset) } else { ('{0}Hz not supported now' -f $preset) }
        $button.Background = if ($isActive) { New-Brush '#3364D8FF' } else { New-Brush '#14FFFFFF' }
        $button.BorderBrush = if ($isActive) { New-Brush '#6691E3FF' } else { New-Brush '#2DFFFFFF' }
        $button.Foreground = if ($isSupported) { New-Brush '#FFE9F6FF' } else { New-Brush '#AAC8D9E5' }
    }
}

function Update-TdpControlsUi {
    param(
        [hashtable]$NamedElements,
        $Snapshot
    )

    $tdpState = $script:performanceState
    $fanState = $script:fanState
    $refreshState = $script:refreshRateState
    $fpsLimiter = if ($script:appConfig) { [int]$script:appConfig.FpsLimiter } else { 0 }

    $NamedElements.TdpCurrentText.Text = if ($null -ne $tdpState.CurrentLimitW) {
        'Limit {0:N1}W' -f $tdpState.CurrentLimitW
    } else {
        'Limit --'
    }

    $NamedElements.TdpStatusText.Text = if ($tdpState.LastMessage) { $tdpState.LastMessage } else { 'TDP status unavailable' }
    $NamedElements.TdpStatusText.Foreground = if ($tdpState.LastApplySucceeded -and ($tdpState.LastMessage -like 'Applied*')) {
        New-Brush '#FF8EE7B3'
    } elseif (-not $tdpState.IsAvailable) {
        New-Brush '#FFFFB2B2'
    } else {
        New-Brush '#CBEAF5FF'
    }

    if ($NamedElements.ContainsKey('TdpCustomPanel') -and $NamedElements.TdpCustomPanel) {
        $customVisible = if ($script:appConfig) { [bool]$script:appConfig.ShowTdpCustomPanel } else { $false }
        Set-TdpCustomPanelState -NamedElements $NamedElements -IsVisible $customVisible
    }
    if ($NamedElements.ContainsKey('TdpCustomSlider') -and $NamedElements.TdpCustomSlider) {
        $NamedElements.TdpCustomSlider.Minimum = [double]$script:tdpCustomRange.MinW
        $NamedElements.TdpCustomSlider.Maximum = [double]$script:tdpCustomRange.MaxW
        $selectedW = [int][Math]::Round([double]$NamedElements.TdpCustomSlider.Value)
        $selectedW = [Math]::Max($script:tdpCustomRange.MinW, [Math]::Min($script:tdpCustomRange.MaxW, $selectedW))
        if ($script:appConfig) {
            $script:appConfig.TdpCustomW = $selectedW
        }

        if ($NamedElements.ContainsKey('TdpCustomValueText') -and $NamedElements.TdpCustomValueText) {
            $NamedElements.TdpCustomValueText.Text = '{0}W' -f $selectedW
        }

        if ($NamedElements.ContainsKey('TdpCustomApplyButton') -and $NamedElements.TdpCustomApplyButton) {
            $isActive = ($null -ne $tdpState.CurrentLimitW) -and ([Math]::Abs($tdpState.CurrentLimitW - $selectedW) -le 0.6)
            $NamedElements.TdpCustomApplyButton.Background = if ($isActive) { New-Brush '#3358D68D' } else { New-Brush '#14FFFFFF' }
            $NamedElements.TdpCustomApplyButton.BorderBrush = if ($isActive) { New-Brush '#6676F0A5' } else { New-Brush '#2DFFFFFF' }
            $NamedElements.TdpCustomApplyButton.Foreground = if ($isActive) { New-Brush '#FFF6FFF9' } else { New-Brush '#FFDDECF9' }
        }
    }

    if ($NamedElements.ContainsKey('ModesPanel') -and $NamedElements.ModesPanel) {
        $showModes = if ($script:appConfig) { [bool]$script:appConfig.ShowModesPanel } else { $false }
        Set-ModesPanelState -NamedElements $NamedElements -IsVisible $showModes
    }
    if ($NamedElements.ContainsKey('FpsCurrentText') -and $NamedElements.FpsCurrentText) {
        $NamedElements.FpsCurrentText.Text = if ($fpsLimiter -gt 0) { ('{0} fps' -f $fpsLimiter) } else { 'Off' }
    }
    if ($NamedElements.ContainsKey('FpsStatusText') -and $NamedElements.FpsStatusText) {
        $NamedElements.FpsStatusText.Text = if ($fpsLimiter -gt 0) { ('FPS limiter profile active: {0} fps' -f $fpsLimiter) } else { 'FPS limiter off' }
        $NamedElements.FpsStatusText.Foreground = if ($fpsLimiter -gt 0) { New-Brush '#FF9DD4FF' } else { New-Brush '#BFE4F6FF' }
    }
    if ($NamedElements.ContainsKey('ModesSummaryText') -and $NamedElements.ModesSummaryText) {
        if ($fpsLimiter -gt 0) {
            $NamedElements.ModesSummaryText.Text = 'Active mode: FPS ' + $fpsLimiter
            $NamedElements.ModesSummaryText.Foreground = New-Brush '#FF9DD4FF'
            $NamedElements.ModesSummaryText.Visibility = 'Visible'
        } else {
            $NamedElements.ModesSummaryText.Visibility = 'Collapsed'
        }
    }

    if ($NamedElements.ContainsKey('FanStatusText') -and $NamedElements.FanStatusText) {
        $NamedElements.FanStatusText.Text = if ($fanState.LastMessage) { $fanState.LastMessage } else { 'Fan status unavailable' }
        $NamedElements.FanStatusText.Foreground = if ($fanState.LastApplyStatus -eq 'Applied') {
            New-Brush '#FF9DD4FF'
        } elseif ($fanState.LastApplyStatus -eq 'Pending') {
            New-Brush '#FFFFD88D'
        } elseif ($fanState.LastApplyStatus -eq 'Error') {
            New-Brush '#FFFFB2B2'
        } elseif (-not $fanState.IsAvailable) {
            New-Brush '#FFFFB2B2'
        } else {
            New-Brush '#BFE4F6FF'
        }
    }

    if ($NamedElements.ContainsKey('CpuTempCardText') -and $NamedElements.CpuTempCardText) {
        $NamedElements.CpuTempCardText.Text = if ($Snapshot -and $null -ne $Snapshot.CpuTemperatureC) {
            '{0:N1}C' -f $Snapshot.CpuTemperatureC
        } else {
            '--C'
        }
    }

    if ($NamedElements.ContainsKey('HzCurrentText') -and $NamedElements.HzCurrentText) {
        $NamedElements.HzCurrentText.Text = if ($null -ne $refreshState.CurrentHz) {
            '{0} Hz' -f [int]$refreshState.CurrentHz
        } else {
            '-- Hz'
        }
    }

    if ($NamedElements.ContainsKey('HzStatusText') -and $NamedElements.HzStatusText) {
        $NamedElements.HzStatusText.Text = if ($refreshState.LastMessage) { $refreshState.LastMessage } else { 'Refresh rate unavailable' }
        $NamedElements.HzStatusText.Foreground = if ($refreshState.LastApplyStatus -eq 'Applied') {
            New-Brush '#FF9BDCF0'
        } elseif ($refreshState.LastApplyStatus -eq 'Error') {
            New-Brush '#FFFFB2B2'
        } else {
            New-Brush '#BFE4F6FF'
        }
    }

    Set-TdpPresetVisual -NamedElements $NamedElements -CurrentLimitW $tdpState.CurrentLimitW
    Set-FanPresetVisual -NamedElements $NamedElements -Mode $fanState.Mode
    Set-FpsPresetVisual -NamedElements $NamedElements -FpsLimiter $fpsLimiter
    Set-RefreshPresetVisual -NamedElements $NamedElements -CurrentHz $refreshState.CurrentHz -Supports60 $refreshState.Supports60 -Supports120 $refreshState.Supports120
    Update-EdgeControlsUi -NamedElements $NamedElements
}

function Add-HistoryPoint {
    param(
        [System.Collections.Generic.List[Double]]$History,
        [Nullable[Double]]$Value,
        [int]$Limit = 36
    )

    if ($null -eq $Value) {
        return
    }

    $History.Add([double]$Value)
    while ($History.Count -gt $Limit) {
        $History.RemoveAt(0)
    }
}

function Update-Sparkline {
    param(
        [System.Windows.Controls.Canvas]$Canvas,
        [System.Collections.Generic.List[Double]]$History,
        [string]$StrokeColor,
        [string]$FillColor
    )

    $Canvas.Children.Clear()
    if ($History.Count -lt 2) {
        return
    }

    $width = if ($Canvas.ActualWidth -gt 0) { $Canvas.ActualWidth } else { $Canvas.Width }
    $height = if ($Canvas.ActualHeight -gt 0) { $Canvas.ActualHeight } else { $Canvas.Height }

    if ($width -le 0 -or $height -le 0) {
        return
    }

    $min = ($History | Measure-Object -Minimum).Minimum
    $max = ($History | Measure-Object -Maximum).Maximum
    if ([Math]::Abs($max - $min) -lt 0.01) {
        $max = $min + 1
    }

    $count = $History.Count - 1
    $polyline = New-Object System.Windows.Shapes.Polyline
    $polyline.Stroke = New-Brush -Color $StrokeColor
    $polyline.StrokeThickness = 2.6
    $polyline.StrokeLineJoin = 'Round'
    $polyline.StrokeStartLineCap = 'Round'
    $polyline.StrokeEndLineCap = 'Round'

    $polygon = New-Object System.Windows.Shapes.Polygon
    $polygon.Fill = New-Brush -Color $FillColor

    $polygon.Points.Add([System.Windows.Point]::new(0, $height))

    for ($index = 0; $index -lt $History.Count; $index++) {
        $x = if ($count -eq 0) { 0 } else { ($index / $count) * $width }
        $normalized = ($History[$index] - $min) / ($max - $min)
        $y = $height - ($normalized * ($height - 4)) - 2
        $point = [System.Windows.Point]::new($x, $y)
        $polyline.Points.Add($point)
        $polygon.Points.Add($point)
    }

    $polygon.Points.Add([System.Windows.Point]::new($width, $height))

    [void]$Canvas.Children.Add($polygon)
    [void]$Canvas.Children.Add($polyline)
}

$script:appConfig = Load-AppConfig
$script:appConfig.TdpCustomW = [Math]::Max($script:tdpCustomRange.MinW, [Math]::Min($script:tdpCustomRange.MaxW, [int]$script:appConfig.TdpCustomW))
$script:appConfig.FpsLimiter = if ($script:fpsLimiterLevels -contains [int]$script:appConfig.FpsLimiter) { [int]$script:appConfig.FpsLimiter } else { 0 }
$script:edgeDockState.Enabled = [bool]$script:appConfig.EnableEdgeSidebar
$script:edgeDockState.AutoHideSeconds = [Math]::Max(2, [Math]::Min(30, [int]$script:appConfig.EdgeAutoHideSeconds))
$script:edgeDockState.LastInteractionAt = Get-Date
$script:appConfig.EnableEdgeSidebar = $script:edgeDockState.Enabled
$script:appConfig.EdgeAutoHideSeconds = $script:edgeDockState.AutoHideSeconds
$computer = New-HardwareComputer

try {
    if ($DumpSnapshot) {
        Get-PowerSnapshot -Computer $computer | ConvertTo-Json -Depth 4
        return
    }
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="System Monitor"
        Width="412"
        Height="540"
        MinWidth="412"
        MinHeight="540"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize"
        Topmost="True"
        ShowInTaskbar="True">
    <Grid>
    <Border x:Name="RootBorder"
            CornerRadius="26"
            Padding="16"
            BorderBrush="#3AF3F6FF"
            BorderThickness="1">
        <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#F4151A2B" Offset="0"/>
                <GradientStop Color="#F40F1622" Offset="1"/>
            </LinearGradientBrush>
        </Border.Background>
        <Border.Effect>
            <DropShadowEffect BlurRadius="28" ShadowDepth="0" Color="#CC000000" Opacity="0.58"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition x:Name="MainContentRow" Height="*"/>
                <RowDefinition x:Name="FooterSpacerRow" Height="10"/>
                <RowDefinition x:Name="FooterRow" Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel x:Name="TitleStack"
                            Grid.Row="0"
                            Grid.Column="0"
                            Margin="0,0,0,2">
                    <TextBlock Text="System Monitor"
                               Foreground="#FFF5F7FB"
                               FontFamily="Bahnschrift SemiBold"
                               FontSize="20"/>
                    <TextBlock x:Name="SubtitleText"
                               Text="TDP, battery flow, internet"
                               Foreground="#8DE8EEF9"
                               FontFamily="Segoe UI Variable Text"
                               FontSize="10.5"/>
                </StackPanel>

                <Button x:Name="CompactButton"
                        Grid.Row="0"
                        Grid.Column="2"
                        Width="34"
                        Height="34"
                        Background="#3349D17C"
                        BorderBrush="#6675F0A2"
                        Foreground="#FFF5F7FB"
                        FontSize="13"
                        FontFamily="Bahnschrift SemiBold"
                        Content="C"
                        ToolTip="Switch to compact mode"/>

                <Button x:Name="PinButton"
                        Grid.Row="0"
                        Grid.Column="4"
                        Width="34"
                        Height="34"
                        Background="#33FF5A5A"
                        BorderBrush="#66FFB3B3"
                        Foreground="#FFF5F7FB"
                        FontSize="15"
                        FontFamily="Segoe UI Emoji"
                        Content="📌"
                        ToolTip="Pin on top"/>

                <Button x:Name="SidebarButton"
                        Grid.Row="0"
                        Grid.Column="6"
                        Width="34"
                        Height="34"
                        Background="#18FFFFFF"
                        BorderBrush="#2EFFFFFF"
                        Foreground="#FFF5F7FB"
                        FontSize="13"
                        FontFamily="Segoe UI Symbol"
                        Content="⇆"
                        ToolTip="Toggle right sidebar mode"/>

                <Button x:Name="CloseButton"
                        Grid.Row="0"
                        Grid.Column="8"
                        Width="34"
                        Height="34"
                        Background="#18FFFFFF"
                        BorderBrush="#2EFFFFFF"
                        Foreground="#FFF5F7FB"
                        FontSize="13"
                        FontFamily="Bahnschrift SemiBold"
                        Content="X"
                        ToolTip="Exit application"/>

                <StackPanel Grid.Row="1"
                            Grid.Column="0"
                            Grid.ColumnSpan="9"
                            Orientation="Horizontal"
                            Margin="0,7,0,0">
                    <Border x:Name="InternetBadge"
                            Padding="10,7"
                            CornerRadius="14"
                            Background="#1427D799"
                            BorderBrush="#2AFFFFFF"
                            BorderThickness="1"
                            Margin="0,0,8,0">
                        <StackPanel Orientation="Horizontal">
                            <Ellipse x:Name="InternetDot"
                                     Width="8"
                                     Height="8"
                                     Margin="0,0,7,0"
                                     VerticalAlignment="Center"
                                     Fill="#FF58D68D"/>
                            <TextBlock x:Name="InternetText"
                                       Foreground="#FFF8FBFF"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="10.5"
                                       Text="Online"/>
                        </StackPanel>
                    </Border>

                    <Border x:Name="NetworkSpeedBadge"
                            Padding="10,7"
                            CornerRadius="14"
                            Background="#14FFFFFF"
                            BorderBrush="#2AFFFFFF"
                            BorderThickness="1"
                            MaxWidth="236">
                        <StackPanel>
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="↓"
                                           Foreground="#FF4DD0E1"
                                           FontFamily="Bahnschrift SemiBold"
                                           FontSize="11"
                                           Margin="0,0,4,0"/>
                                <TextBlock x:Name="DownloadSpeedText"
                                           Foreground="#FFF8FBFF"
                                           FontFamily="Bahnschrift SemiBold"
                                           FontSize="9.5"
                                           Text="--"/>
                                <TextBlock Text="  "
                                           FontSize="9.5"/>
                                <TextBlock Text="↑"
                                           Foreground="#FFFF6B6B"
                                           FontFamily="Bahnschrift SemiBold"
                                           FontSize="11"
                                           Margin="0,0,4,0"/>
                                <TextBlock x:Name="UploadSpeedText"
                                           Foreground="#FFF8FBFF"
                                           FontFamily="Bahnschrift SemiBold"
                                           FontSize="9.5"
                                           Text="--"/>
                            </StackPanel>
                            <TextBlock x:Name="NetworkNameText"
                                       Margin="0,4,0,0"
                                       Foreground="#A8F5F7FB"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="9"
                                       Text="Detecting network"
                                       TextTrimming="CharacterEllipsis"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>

            <Border x:Name="TdpControlPanel"
                    Grid.Row="1"
                    Margin="0,8,0,0"
                    Padding="11,8"
                    CornerRadius="14"
                    Background="#14FFFFFF"
                    BorderBrush="#2AFFFFFF"
                    BorderThickness="1">
                <StackPanel>
                    <Grid VerticalAlignment="Center">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="8"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock Text="TDP CONTROL"
                                   Foreground="#BCEFF8FF"
                                   FontFamily="Bahnschrift SemiBold"
                                   FontSize="9.8"
                                   VerticalAlignment="Center"/>
                        <Border Grid.Column="2"
                                Padding="7,2"
                                CornerRadius="10"
                                Background="#1227D799"
                                BorderBrush="#2AFFFFFF"
                                BorderThickness="1"
                                VerticalAlignment="Center">
                            <TextBlock x:Name="TdpCurrentText"
                                       Foreground="#FFF8FBFF"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="9.6"
                                       Text="Limit --"/>
                        </Border>
                        <StackPanel Grid.Column="3"
                                    Orientation="Horizontal"
                                    HorizontalAlignment="Right">
                            <Button x:Name="TdpPreset6Button"
                                    Margin="8,0,0,0"
                                    Padding="8,2"
                                    MinWidth="40"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Bahnschrift SemiBold"
                                    FontSize="10"
                                    Content="6W"/>
                            <Button x:Name="TdpPreset8Button"
                                    Margin="6,0,0,0"
                                    Padding="8,2"
                                    MinWidth="40"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Bahnschrift SemiBold"
                                    FontSize="10"
                                    Content="8W"/>
                            <Button x:Name="TdpPreset10Button"
                                    Margin="6,0,0,0"
                                    Padding="8,2"
                                    MinWidth="44"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Bahnschrift SemiBold"
                                    FontSize="10"
                                    Content="10W"/>
                            <Button x:Name="TdpPreset12Button"
                                    Margin="6,0,0,0"
                                    Padding="8,2"
                                    MinWidth="44"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Bahnschrift SemiBold"
                                    FontSize="10"
                                    Content="12W"/>
                            <Button x:Name="TdpCustomToggleButton"
                                    Margin="6,0,0,0"
                                    Padding="8,2"
                                    MinWidth="56"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Bahnschrift SemiBold"
                                    FontSize="10"
                                    Content="Custom"/>
                            <Button x:Name="ModesToggleButton"
                                    Margin="6,0,0,0"
                                    Padding="6,2"
                                    MinWidth="34"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Segoe UI Symbol"
                                    FontSize="11"
                                    Content="⋯"
                                    ToolTip="More modes"/>
                        </StackPanel>
                    </Grid>
                    <TextBlock x:Name="TdpStatusText"
                               Margin="0,6,0,0"
                               Foreground="#CBEAF5FF"
                               FontFamily="Segoe UI Variable Text"
                               FontSize="9.2"
                               Text="TDP controller idle"/>
                    <TextBlock x:Name="ModesSummaryText"
                               Margin="0,4,0,0"
                               Foreground="#9DD4FF"
                               FontFamily="Segoe UI Variable Text"
                               FontSize="9.1"
                               Visibility="Collapsed"
                               Text="Active mode: FPS 60"/>
                    <Grid x:Name="TdpCustomPanel"
                          Margin="0,6,0,0"
                          VerticalAlignment="Center"
                          Visibility="Collapsed">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="8"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="8"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="CUSTOM 4-25W"
                                   Foreground="#BCEFF8FF"
                                   FontFamily="Bahnschrift SemiBold"
                                   FontSize="9.3"
                                   VerticalAlignment="Center"/>
                        <Slider x:Name="TdpCustomSlider"
                                Grid.Column="2"
                                VerticalAlignment="Center"
                                Minimum="4"
                                Maximum="25"
                                Value="6"
                                TickFrequency="1"
                                IsSnapToTickEnabled="True"/>
                        <TextBlock x:Name="TdpCustomValueText"
                                   Grid.Column="4"
                                   Foreground="#FFF8FBFF"
                                   FontFamily="Bahnschrift SemiBold"
                                   FontSize="9.5"
                                   VerticalAlignment="Center"
                                   Text="6W"/>
                        <Button x:Name="TdpCustomApplyButton"
                                Grid.Column="6"
                                Padding="8,2"
                                MinWidth="64"
                                HorizontalAlignment="Right"
                                Background="#14FFFFFF"
                                BorderBrush="#2DFFFFFF"
                                Foreground="#FFDDECF9"
                                FontFamily="Bahnschrift SemiBold"
                                FontSize="9.3"
                                Visibility="Collapsed"
                                Content="Apply"/>
                    </Grid>
                    <Border Margin="0,7,0,0"
                            Height="1"
                            Background="#1EFFFFFF"/>
                    <Grid Margin="0,7,0,0"
                          VerticalAlignment="Center">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="FAN PROFILE"
                                   Foreground="#BCEFF8FF"
                                   FontFamily="Bahnschrift SemiBold"
                                   FontSize="9.8"
                                   VerticalAlignment="Center"/>
                        <StackPanel Grid.Column="1"
                                    Orientation="Horizontal"
                                    HorizontalAlignment="Right">
                            <Button x:Name="FanLowButton"
                                    Margin="8,0,0,0"
                                    Padding="8,2"
                                    MinWidth="44"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Bahnschrift SemiBold"
                                    FontSize="9.8"
                                    Content="Low"/>
                            <Button x:Name="FanMediumButton"
                                    Margin="6,0,0,0"
                                    Padding="8,2"
                                    MinWidth="58"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Bahnschrift SemiBold"
                                    FontSize="9.8"
                                    Content="Medium"/>
                            <Button x:Name="FanMaxButton"
                                    Margin="6,0,0,0"
                                    Padding="8,2"
                                    MinWidth="44"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Bahnschrift SemiBold"
                                    FontSize="9.8"
                                    Content="Max"/>
                            <Button x:Name="FanAutoButton"
                                    Margin="6,0,0,0"
                                    Padding="8,2"
                                    MinWidth="45"
                                    Background="#14FFFFFF"
                                    BorderBrush="#2DFFFFFF"
                                    Foreground="#FFDDECF9"
                                    FontFamily="Bahnschrift SemiBold"
                                    FontSize="9.8"
                                    Content="Auto"/>
                        </StackPanel>
                    </Grid>
                    <TextBlock x:Name="FanStatusText"
                               Margin="0,6,0,0"
                               Foreground="#BFE4F6FF"
                               FontFamily="Segoe UI Variable Text"
                               FontSize="9.2"
                               Text="Fan controller idle"/>
                    <Border Margin="0,7,0,0"
                            Height="1"
                            Background="#1EFFFFFF"/>
                    <StackPanel x:Name="ModesPanel"
                                Margin="0,7,0,0"
                                Visibility="Collapsed">
                        <Grid VerticalAlignment="Center">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="FPS LIMITER"
                                       Foreground="#BCEFF8FF"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="9.8"
                                       VerticalAlignment="Center"/>
                            <Border Grid.Column="2"
                                    Padding="7,2"
                                    CornerRadius="10"
                                    Background="#13338BC0"
                                    BorderBrush="#2AFFFFFF"
                                    BorderThickness="1"
                                    VerticalAlignment="Center">
                                <TextBlock x:Name="FpsCurrentText"
                                           Foreground="#FFF8FBFF"
                                           FontFamily="Bahnschrift SemiBold"
                                           FontSize="9.5"
                                           Text="Off"/>
                            </Border>
                            <StackPanel Grid.Column="3"
                                        Orientation="Horizontal"
                                        HorizontalAlignment="Right">
                                <Button x:Name="FpsOffButton"
                                        Margin="8,0,0,0"
                                        Padding="8,2"
                                        MinWidth="42"
                                        Background="#14FFFFFF"
                                        BorderBrush="#2DFFFFFF"
                                        Foreground="#FFDDECF9"
                                        FontFamily="Bahnschrift SemiBold"
                                        FontSize="9.8"
                                        Content="Off"/>
                                <Button x:Name="Fps30Button"
                                        Margin="6,0,0,0"
                                        Padding="8,2"
                                        MinWidth="42"
                                        Background="#14FFFFFF"
                                        BorderBrush="#2DFFFFFF"
                                        Foreground="#FFDDECF9"
                                        FontFamily="Bahnschrift SemiBold"
                                        FontSize="9.8"
                                        Content="30"/>
                                <Button x:Name="Fps45Button"
                                        Margin="6,0,0,0"
                                        Padding="8,2"
                                        MinWidth="42"
                                        Background="#14FFFFFF"
                                        BorderBrush="#2DFFFFFF"
                                        Foreground="#FFDDECF9"
                                        FontFamily="Bahnschrift SemiBold"
                                        FontSize="9.8"
                                        Content="45"/>
                                <Button x:Name="Fps60Button"
                                        Margin="6,0,0,0"
                                        Padding="8,2"
                                        MinWidth="42"
                                        Background="#14FFFFFF"
                                        BorderBrush="#2DFFFFFF"
                                        Foreground="#FFDDECF9"
                                        FontFamily="Bahnschrift SemiBold"
                                        FontSize="9.8"
                                        Content="60"/>
                            </StackPanel>
                        </Grid>
                        <TextBlock x:Name="FpsStatusText"
                                   Margin="0,6,0,0"
                                   Foreground="#BFE4F6FF"
                                   FontFamily="Segoe UI Variable Text"
                                   FontSize="9.2"
                                   Text="FPS limiter off"/>
                        <Border Margin="0,7,0,0"
                                Height="1"
                                Background="#1EFFFFFF"/>
                        <Grid Margin="0,7,0,0"
                              VerticalAlignment="Center">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="REFRESH RATE"
                                       Foreground="#BCEFF8FF"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="9.8"
                                       VerticalAlignment="Center"/>
                            <Border Grid.Column="2"
                                    Padding="7,2"
                                    CornerRadius="10"
                                    Background="#13218BC0"
                                    BorderBrush="#2AFFFFFF"
                                    BorderThickness="1"
                                    VerticalAlignment="Center">
                                <TextBlock x:Name="HzCurrentText"
                                           Foreground="#FFF8FBFF"
                                           FontFamily="Bahnschrift SemiBold"
                                           FontSize="9.5"
                                           Text="-- Hz"/>
                            </Border>
                            <StackPanel Grid.Column="3"
                                        Orientation="Horizontal"
                                        HorizontalAlignment="Right">
                                <Button x:Name="Hz60Button"
                                        Margin="8,0,0,0"
                                        Padding="8,2"
                                        MinWidth="48"
                                        Background="#14FFFFFF"
                                        BorderBrush="#2DFFFFFF"
                                        Foreground="#FFDDECF9"
                                        FontFamily="Bahnschrift SemiBold"
                                        FontSize="9.8"
                                        Content="60Hz"/>
                                <Button x:Name="Hz120Button"
                                        Margin="6,0,0,0"
                                        Padding="8,2"
                                        MinWidth="52"
                                        Background="#14FFFFFF"
                                        BorderBrush="#2DFFFFFF"
                                        Foreground="#FFDDECF9"
                                        FontFamily="Bahnschrift SemiBold"
                                        FontSize="9.8"
                                        Content="120Hz"/>
                            </StackPanel>
                        </Grid>
                        <TextBlock x:Name="HzStatusText"
                                   Margin="0,6,0,0"
                                   Foreground="#BFE4F6FF"
                                   FontFamily="Segoe UI Variable Text"
                                   FontSize="9.2"
                                   Text="Refresh rate idle"/>
                    </StackPanel>
                </StackPanel>
            </Border>

            <Border x:Name="InternetAlertPanel"
                    Grid.Row="2"
                    Margin="0,10,0,0"
                    Padding="12,8"
                    CornerRadius="16"
                    Background="#E0471717"
                    BorderBrush="#88FF8B8B"
                    BorderThickness="1"
                    VerticalAlignment="Top"
                    Visibility="Collapsed"
                    Panel.ZIndex="12">
                <StackPanel>
                    <TextBlock x:Name="InternetAlertTitle"
                               Foreground="#FFFFE5E5"
                               FontFamily="Bahnschrift SemiBold"
                               FontSize="11"
                               Text="Internet disconnected"/>
                    <TextBlock x:Name="InternetAlertMessage"
                               Margin="0,3,0,0"
                               Foreground="#FFF9D0D0"
                               FontFamily="Segoe UI Variable Text"
                               FontSize="9.5"
                               Text="Offline 1m"/>
                </StackPanel>
            </Border>

            <Grid x:Name="FullContentGrid" Grid.Row="2">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="1.08*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="1*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0"
                        CornerRadius="22"
                        Padding="16"
                        BorderBrush="#26FFFFFF"
                        BorderThickness="1">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <GradientStop Color="#FF223A66" Offset="0"/>
                            <GradientStop Color="#FF0C8A84" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="54"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <TextBlock x:Name="TdpBadge"
                                   Text="CPU POWER"
                                   Foreground="#CFF9FFFF"
                                   FontFamily="Bahnschrift SemiBold"
                                   FontSize="11"/>
                        <TextBlock x:Name="CpuTempCardText"
                                   Grid.Row="0"
                                   HorizontalAlignment="Right"
                                   Text="--C"
                                   Foreground="#FFF8D479"
                                   FontFamily="Bahnschrift SemiBold"
                                   FontSize="16"/>

                        <TextBlock x:Name="TdpValueText"
                                   Grid.Row="1"
                                   Margin="0,6,0,0"
                                   Text="--"
                                   Foreground="#FFFFFFFF"
                                   FontFamily="Bahnschrift SemiBold"
                                   FontSize="30"/>

                        <TextBlock x:Name="TdpMetaText"
                                   Grid.Row="2"
                                   Margin="0,6,0,0"
                                   TextWrapping="Wrap"
                                   Foreground="#DDF4FBFF"
                                   FontFamily="Segoe UI Variable Text"
                                   FontSize="10.5"/>

                        <TextBlock x:Name="CpuGpuText"
                                   Grid.Row="3"
                                   Margin="0,7,0,0"
                                   Foreground="#BFEFF8FF"
                                   FontFamily="Segoe UI Variable Text"
                                   FontSize="10.5"/>

                        <Canvas x:Name="TdpSpark"
                                Grid.Row="4"
                                Height="40"
                                Margin="0,12,0,0"/>
                    </Grid>
                </Border>

                <Grid Grid.Column="2">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="10"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0"
                            CornerRadius="20"
                            Padding="14"
                            Background="#16FFFFFF"
                            BorderBrush="#26FFFFFF"
                            BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>

                            <TextBlock Text="POWER FLOW"
                                       Foreground="#A8F5F7FB"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="11"/>

                            <TextBlock x:Name="DrainValueText"
                                       Grid.Row="1"
                                       Margin="0,6,0,0"
                                       Text="--"
                                       Foreground="#FFF9FCFF"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="19"/>

                            <TextBlock x:Name="DrainLabelText"
                                       Grid.Row="2"
                                       Margin="0,6,0,0"
                                       Foreground="#D8EEF7FF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="10.5"/>

                            <Canvas x:Name="DrainSpark"
                                    Grid.Row="3"
                                    Height="28"
                                    Margin="0,10,0,0"/>
                        </Grid>
                    </Border>

                    <Border Grid.Row="2"
                            CornerRadius="20"
                            Padding="14"
                            Background="#14FFFFFF"
                            BorderBrush="#26FFFFFF"
                            BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <TextBlock Text="BATTERY ETA"
                                       Foreground="#A8F5F7FB"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="11"/>

                            <TextBlock x:Name="BatteryText"
                                       Grid.Row="1"
                                       Margin="0,7,0,0"
                                       Foreground="#FFF8FBFF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="10.2"
                                       TextWrapping="Wrap"/>

                            <TextBlock x:Name="EtaText"
                                       Grid.Row="2"
                                       Margin="0,5,0,0"
                                       Foreground="#FFF8D479"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="10.4"/>

                            <TextBlock x:Name="BatteryMetaText"
                                       Grid.Row="3"
                                       Margin="0,6,0,0"
                                       Foreground="#C8EAF4FF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="8.9"
                                       TextWrapping="Wrap"/>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>

            <Grid x:Name="CompactContentGrid"
                  Grid.Row="2"
                  VerticalAlignment="Top"
                  Visibility="Collapsed">
                <Border CornerRadius="22"
                        Padding="14"
                        BorderBrush="#26FFFFFF"
                        BorderThickness="1">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <GradientStop Color="#FF223A66" Offset="0"/>
                            <GradientStop Color="#FF0C8A84" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1.26*"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="0.88*"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="0.88*"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="0.92*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel>
                            <TextBlock Text="CPU POWER"
                                       Foreground="#CFF9FFFF"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="10.5"/>
                            <TextBlock x:Name="CompactCpuValueText"
                                       Margin="0,5,0,0"
                                       Text="--"
                                       Foreground="#FFFFFFFF"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="26"/>
                            <TextBlock x:Name="CompactCpuMetaText"
                                       Margin="0,4,0,0"
                                       Foreground="#DDF4FBFF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="9.5"
                                       TextWrapping="NoWrap"
                                       TextTrimming="CharacterEllipsis"/>
                        </StackPanel>

                        <StackPanel Grid.Column="2">
                            <TextBlock Text="FLOW"
                                       Foreground="#A8F5F7FB"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="10.5"/>
                            <TextBlock x:Name="CompactDrainValueText"
                                       Margin="0,6,0,0"
                                       Foreground="#FFF8FBFF"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="15"/>
                            <TextBlock x:Name="CompactDrainLabelText"
                                       Margin="0,5,0,0"
                                       Foreground="#D8EEF7FF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="9.5"
                                       TextWrapping="NoWrap"
                                       TextTrimming="CharacterEllipsis"/>
                        </StackPanel>

                        <StackPanel Grid.Column="4">
                            <TextBlock Text="ETA"
                                       Foreground="#A8F5F7FB"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="10.5"/>
                            <TextBlock x:Name="CompactEtaText"
                                       Margin="0,6,0,0"
                                       Foreground="#FFF8D479"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="15"
                                       TextWrapping="NoWrap"
                                       TextTrimming="CharacterEllipsis"/>
                            <TextBlock x:Name="CompactBatteryText"
                                       Margin="0,5,0,0"
                                       Foreground="#C8EAF4FF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="9.5"
                                       TextWrapping="NoWrap"
                                       TextTrimming="CharacterEllipsis"/>
                        </StackPanel>

                        <StackPanel Grid.Column="6">
                            <TextBlock Text="BATTERY"
                                       Foreground="#A8F5F7FB"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="10.5"/>
                            <TextBlock x:Name="CompactBatteryLevelText"
                                       Margin="0,6,0,0"
                                       Foreground="#FFF8FBFF"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="15"/>
                            <TextBlock x:Name="CompactBatteryMetaText"
                                       Margin="0,5,0,0"
                                       Foreground="#C8EAF4FF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="9.5"
                                       TextWrapping="NoWrap"
                                       TextTrimming="CharacterEllipsis"/>
                        </StackPanel>
                    </Grid>
                </Border>
            </Grid>

            <Grid x:Name="FooterGrid" Grid.Row="4">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock x:Name="SourceText"
                           Foreground="#73F5F7FB"
                           FontFamily="Segoe UI Variable Text"
                           FontSize="9.5"
                           TextTrimming="CharacterEllipsis"/>

                <TextBlock Grid.Column="1"
                           x:Name="UpdatedText"
                           Foreground="#8AF5F7FB"
                           FontFamily="Segoe UI Variable Text"
                           FontSize="9.5"
                           Text=""/>
            </Grid>
        </Grid>
    </Border>
    <Button x:Name="DockHandleButton"
            HorizontalAlignment="Right"
            VerticalAlignment="Center"
            Width="30"
            Height="138"
            Margin="0,0,0,0"
            Background="#3E6FA8FF"
            BorderBrush="#90C4FFFF"
            BorderThickness="1"
            Foreground="#FFF5F7FB"
            FontFamily="Bahnschrift SemiBold"
            FontSize="13"
            Content="▶"
            Visibility="Collapsed"
            ToolTip="Hide widget to right sidebar"/>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $namedElements = @{}
    foreach ($name in @(
        'RootBorder',
        'TitleStack',
        'SubtitleText',
        'CompactButton',
        'PinButton',
        'SidebarButton',
        'CloseButton',
        'DockHandleButton',
        'InternetBadge',
        'InternetDot',
        'InternetText',
        'NetworkSpeedBadge',
        'TdpControlPanel',
        'TdpCurrentText',
        'TdpStatusText',
        'TdpPreset6Button',
        'TdpPreset8Button',
        'TdpPreset10Button',
        'TdpPreset12Button',
        'TdpCustomToggleButton',
        'ModesToggleButton',
        'ModesSummaryText',
        'TdpCustomPanel',
        'TdpCustomSlider',
        'TdpCustomValueText',
        'TdpCustomApplyButton',
        'ModesPanel',
        'FpsCurrentText',
        'FpsOffButton',
        'Fps30Button',
        'Fps45Button',
        'Fps60Button',
        'FpsStatusText',
        'FanLowButton',
        'FanMediumButton',
        'FanAutoButton',
        'FanMaxButton',
        'FanStatusText',
        'CpuTempCardText',
        'HzCurrentText',
        'Hz60Button',
        'Hz120Button',
        'HzStatusText',
        'InternetAlertPanel',
        'InternetAlertTitle',
        'InternetAlertMessage',
        'DownloadSpeedText',
        'UploadSpeedText',
        'NetworkNameText',
        'FullContentGrid',
        'CompactContentGrid',
        'FooterGrid',
        'FooterSpacerRow',
        'FooterRow',
        'MainContentRow',
        'TdpBadge',
        'TdpValueText',
        'TdpMetaText',
        'CpuGpuText',
        'TdpSpark',
        'DrainValueText',
        'DrainLabelText',
        'DrainSpark',
        'BatteryText',
        'EtaText',
        'BatteryMetaText',
        'CompactCpuValueText',
        'CompactCpuMetaText',
        'CompactDrainValueText',
        'CompactDrainLabelText',
        'CompactEtaText',
        'CompactBatteryText',
        'CompactBatteryLevelText',
        'CompactBatteryMetaText',
        'UpdatedText',
        'SourceText'
    )) {
        $namedElements[$name] = $window.FindName($name)
    }

    $tdpHistory = New-Object 'System.Collections.Generic.List[Double]'
    $drainHistory = New-Object 'System.Collections.Generic.List[Double]'
    $script:isPinned = [bool]$script:appConfig.IsPinned

    Set-WindowIcon -Window $window
    Apply-WindowPlacement -Window $window -Config $script:appConfig
    Set-PinVisual -Window $window -NamedElements $namedElements -IsPinned $script:isPinned
    Set-CompactMode -Window $window -NamedElements $namedElements -IsCompact ([bool]$script:appConfig.IsCompact)
    Set-EdgeSidebarMode -Window $window -NamedElements $namedElements -Enabled ([bool]$script:edgeDockState.Enabled)

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $notifyIcon.Icon = Get-AppNotifyIcon
    $notifyIcon.Text = 'System Monitor'
    $notifyIcon.Visible = $true

    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $showHideMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Show now'
    $compactMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Compact mode'
    $compactMenuItem.CheckOnClick = $true
    $sidebarMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Right sidebar mode'
    $sidebarMenuItem.CheckOnClick = $true
    $recoverWindowMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Recover window (safe mode)'
    $notificationMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Desktop internet alerts'
    $notificationMenuItem.CheckOnClick = $true
    $startupMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Start with Windows'
    $startupMenuItem.CheckOnClick = $true
    $exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Exit'

    [void]$trayMenu.Items.Add($showHideMenuItem)
    [void]$trayMenu.Items.Add($compactMenuItem)
    [void]$trayMenu.Items.Add($sidebarMenuItem)
    [void]$trayMenu.Items.Add($recoverWindowMenuItem)
    [void]$trayMenu.Items.Add($notificationMenuItem)
    [void]$trayMenu.Items.Add($startupMenuItem)
    [void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$trayMenu.Items.Add($exitMenuItem)
    $notifyIcon.ContextMenuStrip = $trayMenu
    Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    $initialSnapshot = Get-PowerSnapshot -Computer $computer
    Refresh-PerformanceState -Force | Out-Null
    Refresh-FanState -Force | Out-Null
    Refresh-RefreshRateState -Force | Out-Null
    if ($namedElements.ContainsKey('TdpCustomSlider') -and $namedElements.TdpCustomSlider) {
        $namedElements.TdpCustomSlider.Minimum = [double]$script:tdpCustomRange.MinW
        $namedElements.TdpCustomSlider.Maximum = [double]$script:tdpCustomRange.MaxW
        $namedElements.TdpCustomSlider.Value = [double]$script:appConfig.TdpCustomW
    }
    Set-TdpCustomPanelState -NamedElements $namedElements -IsVisible ([bool]$script:appConfig.ShowTdpCustomPanel)
    Set-ModesPanelState -NamedElements $namedElements -IsVisible ([bool]$script:appConfig.ShowModesPanel)
    Update-TdpControlsUi -NamedElements $namedElements -Snapshot $initialSnapshot

    $applyTdpPresetAction = {
        param([int]$Watts)
        $result = Invoke-TdpPreset -Watts $Watts
        $snapshotAfterApply = Get-PowerSnapshot -Computer $computer
        Refresh-FanState | Out-Null
        Refresh-RefreshRateState | Out-Null
        Update-TdpControlsUi -NamedElements $namedElements -Snapshot $snapshotAfterApply
        if (-not $result.Success) {
            try {
                $notifyIcon.ShowBalloonTip(3200, 'System Monitor', ('TDP {0}W failed: {1}' -f $Watts, $result.Message), [System.Windows.Forms.ToolTipIcon]::Warning)
            } catch {
            }
        }
    }

    $applyFanPresetAction = {
        param([string]$Mode)
        $result = Invoke-FanModePreset -Mode $Mode
        $snapshotAfterApply = Get-PowerSnapshot -Computer $computer
        Refresh-RefreshRateState | Out-Null
        Update-TdpControlsUi -NamedElements $namedElements -Snapshot $snapshotAfterApply
        if (-not $result.Success) {
            try {
                $notifyIcon.ShowBalloonTip(3200, 'System Monitor', ('Fan ' + $Mode + ' failed: ' + $result.Message), [System.Windows.Forms.ToolTipIcon]::Warning)
            } catch {
            }
        }
    }

    $applyRefreshRatePresetAction = {
        param([int]$Hz)
        $result = Invoke-RefreshRatePreset -Hz $Hz
        $snapshotAfterApply = Get-PowerSnapshot -Computer $computer
        Refresh-FanState | Out-Null
        Update-TdpControlsUi -NamedElements $namedElements -Snapshot $snapshotAfterApply
        if (-not $result.Success) {
            try {
                $notifyIcon.ShowBalloonTip(3200, 'System Monitor', ('Refresh ' + $Hz + 'Hz failed: ' + $result.Message), [System.Windows.Forms.ToolTipIcon]::Warning)
            } catch {
            }
        }
    }

    $window.Add_MouseLeftButtonDown({
        param($sender, $e)

        $source = $e.OriginalSource
        while ($source) {
            if ($source -is [System.Windows.Controls.Primitives.ButtonBase] -or
                $source -is [System.Windows.Controls.Slider] -or
                $source -is [System.Windows.Controls.Primitives.Thumb]) {
                return
            }
            $source = [System.Windows.Media.VisualTreeHelper]::GetParent($source)
        }

        if ($script:edgeDockState.Enabled) {
            Set-EdgeDockActivity
            if ($script:edgeDockState.Hidden) {
                Show-EdgeDockWidget -Window $window -Animate -ActivateWindow
                Update-EdgeControlsUi -NamedElements $namedElements
                return
            }
        }

        try {
            $script:edgeDockState.IsDragging = $true
            $window.DragMove()
            Save-AppState -Window $window
        } catch {
        } finally {
            $script:edgeDockState.IsDragging = $false
        }
    })

    $namedElements.CloseButton.Add_Click({
        Hide-MainWindow -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })
    $namedElements.PinButton.Add_Click({
        Set-PinVisual -Window $window -NamedElements $namedElements -IsPinned (-not $script:isPinned)
        Save-AppState -Window $window
    })
    $namedElements.SidebarButton.Add_Click({
        Set-EdgeSidebarMode -Window $window -NamedElements $namedElements -Enabled (-not [bool]$script:edgeDockState.Enabled)
        if ($script:edgeDockState.Enabled) {
            Ensure-MainWindowVisible -Window $window -NamedElements $namedElements
        }
        Save-AppState -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })
    $namedElements.DockHandleButton.Add_Click({
        if (-not $script:edgeDockState.Enabled) {
            return
        }
        if ($script:edgeDockState.Hidden) {
            Show-EdgeDockWidget -Window $window -Animate -ActivateWindow
        } else {
            Hide-EdgeDockWidget -Window $window -Animate
        }
        Update-EdgeControlsUi -NamedElements $namedElements
        Save-AppState -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })
    $namedElements.TdpPreset6Button.Add_Click({
        & $applyTdpPresetAction 6
    })
    $namedElements.TdpPreset8Button.Add_Click({
        & $applyTdpPresetAction 8
    })
    $namedElements.TdpPreset10Button.Add_Click({
        & $applyTdpPresetAction 10
    })
    $namedElements.TdpPreset12Button.Add_Click({
        & $applyTdpPresetAction 12
    })
    $namedElements.TdpCustomToggleButton.Add_Click({
        $nextVisible = -not [bool]$script:appConfig.ShowTdpCustomPanel
        Set-TdpCustomPanelState -NamedElements $namedElements -IsVisible $nextVisible
        Save-AppState -Window $window
        Update-TdpControlsUi -NamedElements $namedElements -Snapshot (Get-PowerSnapshot -Computer $computer)
    })
    $namedElements.ModesToggleButton.Add_Click({
        $nextVisible = -not [bool]$script:appConfig.ShowModesPanel
        Set-ModesPanelState -NamedElements $namedElements -IsVisible $nextVisible
        Save-AppState -Window $window
        Update-TdpControlsUi -NamedElements $namedElements -Snapshot (Get-PowerSnapshot -Computer $computer)
    })
    $namedElements.TdpCustomSlider.Add_ValueChanged({
        $selectedW = [int][Math]::Round([double]$namedElements.TdpCustomSlider.Value)
        $selectedW = [Math]::Max($script:tdpCustomRange.MinW, [Math]::Min($script:tdpCustomRange.MaxW, $selectedW))
        if ($script:appConfig) {
            $script:appConfig.TdpCustomW = $selectedW
        }
        if ($namedElements.ContainsKey('TdpCustomValueText') -and $namedElements.TdpCustomValueText) {
            $namedElements.TdpCustomValueText.Text = '{0}W' -f $selectedW
        }
    })
    $namedElements.TdpCustomApplyButton.Add_Click({
        $selectedW = [int][Math]::Round([double]$namedElements.TdpCustomSlider.Value)
        $selectedW = [Math]::Max($script:tdpCustomRange.MinW, [Math]::Min($script:tdpCustomRange.MaxW, $selectedW))
        & $applyTdpPresetAction $selectedW
    })
    $namedElements.FpsOffButton.Add_Click({
        if ($script:appConfig) {
            $script:appConfig.FpsLimiter = 0
        }
        Save-AppState -Window $window
        Update-TdpControlsUi -NamedElements $namedElements -Snapshot (Get-PowerSnapshot -Computer $computer)
    })
    $namedElements.Fps30Button.Add_Click({
        if ($script:appConfig) {
            $script:appConfig.FpsLimiter = 30
        }
        Save-AppState -Window $window
        Update-TdpControlsUi -NamedElements $namedElements -Snapshot (Get-PowerSnapshot -Computer $computer)
    })
    $namedElements.Fps45Button.Add_Click({
        if ($script:appConfig) {
            $script:appConfig.FpsLimiter = 45
        }
        Save-AppState -Window $window
        Update-TdpControlsUi -NamedElements $namedElements -Snapshot (Get-PowerSnapshot -Computer $computer)
    })
    $namedElements.Fps60Button.Add_Click({
        if ($script:appConfig) {
            $script:appConfig.FpsLimiter = 60
        }
        Save-AppState -Window $window
        Update-TdpControlsUi -NamedElements $namedElements -Snapshot (Get-PowerSnapshot -Computer $computer)
    })
    $namedElements.FanLowButton.Add_Click({
        & $applyFanPresetAction 'Low'
    })
    $namedElements.FanMediumButton.Add_Click({
        & $applyFanPresetAction 'Medium'
    })
    $namedElements.FanAutoButton.Add_Click({
        & $applyFanPresetAction 'Auto'
    })
    $namedElements.FanMaxButton.Add_Click({
        & $applyFanPresetAction 'Max'
    })
    $namedElements.Hz60Button.Add_Click({
        & $applyRefreshRatePresetAction 60
    })
    $namedElements.Hz120Button.Add_Click({
        & $applyRefreshRatePresetAction 120
    })
    $namedElements.CompactButton.Add_Click({
        $nextCompactState = -not [bool]$script:appConfig.IsCompact
        Set-CompactMode -Window $window -NamedElements $namedElements -IsCompact $nextCompactState
        $compactMenuItem.Checked = $nextCompactState
        Save-AppState -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })

    $showHideMenuItem.Add_Click({
        Ensure-MainWindowVisible -Window $window -NamedElements $namedElements
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })

    $compactMenuItem.Add_Click({
        Set-CompactMode -Window $window -NamedElements $namedElements -IsCompact $compactMenuItem.Checked
        Save-AppState -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })

    $sidebarMenuItem.Add_Click({
        Set-EdgeSidebarMode -Window $window -NamedElements $namedElements -Enabled $sidebarMenuItem.Checked
        if ($script:edgeDockState.Enabled) {
            Ensure-MainWindowVisible -Window $window -NamedElements $namedElements
        }
        Save-AppState -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })

    $recoverWindowMenuItem.Add_Click({
        Recover-MainWindowPlacement -Window $window -NamedElements $namedElements
        Save-AppState -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })

    $notificationMenuItem.Add_Click({
        if ($script:appConfig) {
            $script:appConfig.EnableInternetNotifications = $notificationMenuItem.Checked
        }
        Save-AppConfig
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })

    $startupMenuItem.Add_Click({
        $success = Set-StartupEnabled -Enabled $startupMenuItem.Checked
        if (-not $success) {
            [System.Windows.Forms.MessageBox]::Show('Could not update Windows startup shortcut.', 'System Monitor') | Out-Null
        }
        if ($script:appConfig) {
            $script:appConfig.StartWithWindows = Get-StartupEnabled
        }
        Save-AppConfig
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })

    $exitMenuItem.Add_Click({
        Exit-WidgetApplication -Window $window
    })

    $notifyIcon.Add_DoubleClick({
        Ensure-MainWindowVisible -Window $window -NamedElements $namedElements
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
    })
    $notifyIcon.Add_MouseClick({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            Ensure-MainWindowVisible -Window $window -NamedElements $namedElements
            Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
        }
    })

    $window.Add_Closing({
        param($sender, $e)

        if (-not $script:isExiting) {
            $e.Cancel = $true
            Hide-MainWindow -Window $window
            Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem -SidebarMenuItem $sidebarMenuItem
            return
        }

        Save-AppState -Window $window
    })

    $window.Add_Closed({
        if ($notifyIcon) {
            $notifyIcon.Visible = $false
            $notifyIcon.Dispose()
        }
        if ($trayMenu) {
            $trayMenu.Dispose()
        }
    })

    $window.Dispatcher.Add_UnhandledException({
        param($sender, $e)
        try {
            $exMessage = if ($e.Exception) { $e.Exception.ToString() } else { 'Unknown dispatcher exception' }
            Write-RuntimeLog -Message ('DispatcherUnhandledException: ' + $exMessage)
            if ($namedElements -and $namedElements.ContainsKey('SourceText') -and $namedElements.SourceText) {
                $namedElements.SourceText.Text = 'Recovered from UI error'
            }
        } catch {
        }
        $e.Handled = $true
    })

    $renderFrame = {
        try {
            $snapshot = Get-PowerSnapshot -Computer $computer
            $performance = Refresh-PerformanceState
            Enforce-FanManualHold | Out-Null
            Refresh-FanState | Out-Null
            Refresh-RefreshRateState | Out-Null
            Update-TdpControlsUi -NamedElements $namedElements -Snapshot $snapshot

            Add-HistoryPoint -History $tdpHistory -Value $snapshot.CpuRealtimeW
            Add-HistoryPoint -History $drainHistory -Value $snapshot.DrainDisplayW

            $namedElements.TdpValueText.Text = if ($null -ne $snapshot.CpuRealtimeW) { ('{0:N1} W' -f $snapshot.CpuRealtimeW) } else { '--' }
            $namedElements.TdpBadge.Text = 'CPU POWER'
            $namedElements.TdpMetaText.Text = if ($null -ne $snapshot.CpuRealtimeW) {
                if ($null -ne $performance.CurrentLimitW) {
                    'Realtime CPU package power. TDP limit {0:N1}W.' -f $performance.CurrentLimitW
                } else {
                    'Realtime CPU package power.'
                }
            } else {
                'Current backend does not expose CPU package/APU STAPM like HWMonitor.'
            }
            $namedElements.CompactCpuValueText.Text = $namedElements.TdpValueText.Text
            $namedElements.CompactCpuMetaText.Text = if ($null -ne $snapshot.CpuRealtimeW) {
                if ($null -ne $performance.CurrentLimitW) {
                    'Realtime package power / {0:N1}W limit' -f $performance.CurrentLimitW
                } else {
                    'Realtime package power'
                }
            } else {
                'CPU power sensor unavailable'
            }

            $cpuText = if ($null -ne $snapshot.CpuPackageW) { Format-Watts -Value $snapshot.CpuPackageW } else { 'N/A' }
            $gpuText = if ($null -ne $snapshot.GpuPowerW) { Format-Watts -Value $snapshot.GpuPowerW } else { 'N/A' }
            $namedElements.CpuGpuText.Text = 'CPU {0}  |  GPU {1}' -f $cpuText, $gpuText

            $namedElements.DrainValueText.Text = if ($null -ne $snapshot.DrainDisplayW) {
                if ($snapshot.DrainIsCharging) { ('+{0:N1} W' -f $snapshot.DrainDisplayW) } else { ('{0:N1} W' -f $snapshot.DrainDisplayW) }
            } else {
                '--'
            }
            $namedElements.DrainLabelText.Text = if ($null -ne $snapshot.BatteryRateRawW) {
                '{0} | {1}' -f $snapshot.DrainLabel, $snapshot.PowerLineStatus
            } else {
                'Battery power sensor unavailable'
            }
            $namedElements.CompactDrainValueText.Text = $namedElements.DrainValueText.Text
            $namedElements.CompactDrainLabelText.Text = if ($null -ne $snapshot.BatteryRateRawW) {
                $snapshot.DrainLabel
            } else {
                'Sensor unavailable'
            }

            $namedElements.BatteryText.Text = if ($null -ne $snapshot.BatteryLevel) {
                '{0:N0}% battery | {1} left' -f $snapshot.BatteryLevel, (Format-Number -Value $snapshot.RemainingCapacityWh -Unit 'Wh')
            } else {
                'Battery level unavailable'
            }

            $namedElements.EtaText.Text = switch ($snapshot.BatteryEtaStatus) {
                'Discharging' { 'Empty ~ ' + (Format-Duration -TotalSeconds $snapshot.BatteryEtaSeconds) }
                'Charging' { 'Full in ' + (Format-Duration -TotalSeconds $snapshot.BatteryEtaSeconds) }
                'Plugged in' { 'Plugged in' }
                'Estimating' { 'Estimating...' }
                default { 'ETA unavailable' }
            }
            $namedElements.CompactEtaText.Text = $namedElements.EtaText.Text
            $namedElements.CompactBatteryText.Text = $namedElements.BatteryText.Text

            $voltText = if ($null -ne $snapshot.BatteryVoltageV) { Format-Number -Value $snapshot.BatteryVoltageV -Unit 'V' } else { 'N/A' }
            $currentText = if ($null -ne $snapshot.BatteryCurrentA) { Format-Number -Value $snapshot.BatteryCurrentA -Unit 'A' } else { 'N/A' }
            $fullText = if ($null -ne $snapshot.FullCapacityWh) { Format-Number -Value $snapshot.FullCapacityWh -Unit 'Wh full' } else { 'full cap N/A' }
            $namedElements.BatteryMetaText.Text = '{0} | {1} | {2}' -f $voltText, $currentText, $fullText
            $namedElements.CompactBatteryLevelText.Text = if ($null -ne $snapshot.BatteryLevel) {
                '{0:N0}%' -f $snapshot.BatteryLevel
            } else {
                '--'
            }
            $namedElements.CompactBatteryMetaText.Text = if ($null -ne $snapshot.RemainingCapacityWh) {
                Format-Number -Value $snapshot.RemainingCapacityWh -Unit 'Wh left'
            } else {
                'Battery data unavailable'
            }

            $namedElements.InternetText.Text = $snapshot.InternetStatus
            $namedElements.InternetDot.Fill = if ($snapshot.InternetOnline) { New-Brush '#FF58D68D' } else { New-Brush '#FFFF6B6B' }
            $namedElements.InternetBadge.Background = if ($snapshot.InternetOnline) { New-Brush '#1427D799' } else { New-Brush '#14D64545' }
            $namedElements.InternetBadge.BorderBrush = if ($snapshot.InternetOnline) { New-Brush '#2AFFFFFF' } else { New-Brush '#33FFB3B3' }
            $namedElements.DownloadSpeedText.Text = Format-DataRate -BytesPerSecond $snapshot.DownloadBps
            $namedElements.UploadSpeedText.Text = Format-DataRate -BytesPerSecond $snapshot.UploadBps
            $namedElements.NetworkNameText.Text = if ($snapshot.InternetOnline) { $snapshot.InternetDetail } else { Get-OfflineDurationText -OfflineSince $snapshot.InternetOfflineSince }
            $namedElements.NetworkSpeedBadge.ToolTip = 'Adapter: ' + $snapshot.NetworkInterface
            Update-InternetAlertState -Snapshot $snapshot -NamedElements $namedElements -NotifyIcon $notifyIcon

            $namedElements.UpdatedText.Text = 'Updated ' + $snapshot.Timestamp.ToString('HH:mm:ss')
            $namedElements.SourceText.Text = 'Data: {0}' -f $snapshot.SensorSource

            Update-Sparkline -Canvas $namedElements.TdpSpark -History $tdpHistory -StrokeColor '#FFF2FAFF' -FillColor '#2CF2FAFF'
            Update-Sparkline -Canvas $namedElements.DrainSpark -History $drainHistory -StrokeColor '#FFFFC857' -FillColor '#22FFC857'
        } catch {
            $errText = if ($_.Exception) { $_.Exception.ToString() } else { $_.ToString() }
            Write-RuntimeLog -Message ('RenderFrameError: ' + $errText)
            try {
                if ($namedElements -and $namedElements.ContainsKey('SourceText') -and $namedElements.SourceText) {
                    $namedElements.SourceText.Text = 'Recovered after runtime error'
                }
                if ($namedElements -and $namedElements.ContainsKey('UpdatedText') -and $namedElements.UpdatedText) {
                    $namedElements.UpdatedText.Text = 'Updated ' + (Get-Date).ToString('HH:mm:ss')
                }
            } catch {
            }
        }
    }

    & $renderFrame

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max($RefreshMs, 750))
    $timer.Add_Tick($renderFrame)
    $timer.Start()

    if ($AutoCloseSeconds -gt 0) {
        $closeTimer = New-Object System.Windows.Threading.DispatcherTimer
        $closeTimer.Interval = [TimeSpan]::FromSeconds($AutoCloseSeconds)
        $closeTimer.Add_Tick({
            $closeTimer.Stop()
            $script:isExiting = $true
            $window.Close()
        })
        $closeTimer.Start()
    }

    [void]$window.ShowDialog()
}
finally {
    if ($computer) {
        $computer.Close()
    }
}




