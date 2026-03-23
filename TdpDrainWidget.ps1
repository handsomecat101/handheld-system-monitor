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

function Get-ActiveMotionAssistantProfilePath {
    $baseDir = 'C:\Users\PC\Desktop\MotionAssistant_1208_Release\MotionAssistant\Profiles'
    $globalPath = Join-Path $baseDir 'Global.ini'
    $profileName = 'default'

    if (Test-Path -LiteralPath $globalPath) {
        foreach ($line in Get-Content -LiteralPath $globalPath) {
            if ($line -match '^lastFile=(.+)$' -and $matches[1]) {
                $profileName = $matches[1].Trim()
                break
            }
        }
    }

    $profilePath = Join-Path (Join-Path $baseDir 'General') ($profileName + '.ini')
    if (Test-Path -LiteralPath $profilePath) {
        return $profilePath
    }

    $fallback = Join-Path (Join-Path $baseDir 'General') 'default.ini'
    if (Test-Path -LiteralPath $fallback) {
        return $fallback
    }

    return $null
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
    $Window.Topmost = $IsPinned
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

function Set-CompactMode {
    param(
        $Window,
        [hashtable]$NamedElements,
        [bool]$IsCompact
    )

    $NamedElements.SubtitleText.Visibility = if ($IsCompact) { 'Collapsed' } else { 'Visible' }
    $NamedElements.FullContentGrid.Visibility = if ($IsCompact) { 'Collapsed' } else { 'Visible' }
    $NamedElements.CompactContentGrid.Visibility = if ($IsCompact) { 'Visible' } else { 'Collapsed' }
    $NamedElements.FooterGrid.Visibility = if ($IsCompact) { 'Collapsed' } else { 'Visible' }
    $NamedElements.FooterSpacerRow.Height = if ($IsCompact) { [System.Windows.GridLength]::new(0) } else { [System.Windows.GridLength]::new(10) }
    $NamedElements.FooterRow.Height = if ($IsCompact) { [System.Windows.GridLength]::new(0) } else { [System.Windows.GridLength]::Auto }

    $Window.Height = if ($IsCompact) { 184 } else { 286 }
    $Window.MinHeight = if ($IsCompact) { 184 } else { 286 }
    $Window.Width = 412
    $Window.MinWidth = 412

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
}

function Apply-WindowPlacement {
    param(
        $Window,
        $Config
    )

    if (-not $Window -or -not $Config) {
        return
    }

    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
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

function Show-MainWindow {
    param($Window)

    if (-not $Window.IsVisible) {
        $Window.ShowInTaskbar = $true
        $Window.Show()
    } else {
        $Window.ShowInTaskbar = $true
    }

    $Window.WindowState = 'Normal'
    $Window.Activate() | Out-Null
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
        $StartupMenuItem
    )

    if ($Window.IsVisible) {
        $ShowHideMenuItem.Text = 'Hide widget'
    } else {
        $ShowHideMenuItem.Text = 'Show widget'
    }

    if ($script:appConfig) {
        $CompactMenuItem.Checked = [bool]$script:appConfig.IsCompact
        $NotificationMenuItem.Checked = [bool]$script:appConfig.EnableInternetNotifications
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
        Height="286"
        MinWidth="412"
        MinHeight="286"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize"
        Topmost="True"
        ShowInTaskbar="True">
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
                <RowDefinition Height="12"/>
                <RowDefinition Height="*"/>
                <RowDefinition x:Name="FooterSpacerRow" Height="10"/>
                <RowDefinition x:Name="FooterRow" Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel x:Name="TitleStack">
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

                <Border x:Name="InternetBadge"
                        Grid.Column="1"
                        Padding="10,7"
                        CornerRadius="14"
                        Background="#1427D799"
                        BorderBrush="#2AFFFFFF"
                        BorderThickness="1">
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
                        Grid.Column="3"
                        Padding="10,7"
                        CornerRadius="14"
                        Background="#14FFFFFF"
                        BorderBrush="#2AFFFFFF"
                        BorderThickness="1">
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
                                   Text="Detecting network"/>
                    </StackPanel>
                </Border>

                <Button x:Name="CompactButton"
                        Grid.Column="5"
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
                        Grid.Column="7"
                        Width="34"
                        Height="34"
                        Background="#33FF5A5A"
                        BorderBrush="#66FFB3B3"
                        Foreground="#FFF5F7FB"
                        FontSize="15"
                        FontFamily="Segoe UI Emoji"
                        Content="📌"
                        ToolTip="Pin on top"/>

                <Button x:Name="CloseButton"
                        Grid.Column="9"
                        Width="34"
                        Height="34"
                        Background="#18FFFFFF"
                        BorderBrush="#2EFFFFFF"
                        Foreground="#FFF5F7FB"
                        FontSize="13"
                        FontFamily="Bahnschrift SemiBold"
                        Content="X"
                        ToolTip="Hide to tray"/>
            </Grid>

            <Border x:Name="InternetAlertPanel"
                    Margin="0,52,0,0"
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
                        <RowDefinition Height="0.95*"/>
                        <RowDefinition Height="12"/>
                        <RowDefinition Height="1.12*"/>
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
                                       Margin="0,8,0,0"
                                       Foreground="#FFF8FBFF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="11.5"
                                       TextWrapping="Wrap"/>

                            <TextBlock x:Name="EtaText"
                                       Grid.Row="2"
                                       Margin="0,6,0,0"
                                       Foreground="#FFF8D479"
                                       FontFamily="Bahnschrift SemiBold"
                                       FontSize="11.5"/>

                            <TextBlock x:Name="BatteryMetaText"
                                       Grid.Row="3"
                                       Margin="0,7,0,0"
                                       Foreground="#C8EAF4FF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="9.5"
                                       TextWrapping="Wrap"/>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>

            <Grid x:Name="CompactContentGrid"
                  Grid.Row="2"
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
                                       TextWrapping="Wrap"/>
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
                                       TextWrapping="Wrap"/>
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
                                       TextWrapping="Wrap"/>
                            <TextBlock x:Name="CompactBatteryText"
                                       Margin="0,5,0,0"
                                       Foreground="#C8EAF4FF"
                                       FontFamily="Segoe UI Variable Text"
                                       FontSize="9.5"
                                       TextWrapping="Wrap"/>
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
                                       TextWrapping="Wrap"/>
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
        'CloseButton',
        'InternetBadge',
        'InternetDot',
        'InternetText',
        'NetworkSpeedBadge',
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

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $notifyIcon.Icon = Get-AppNotifyIcon
    $notifyIcon.Text = 'System Monitor'
    $notifyIcon.Visible = $true

    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $showHideMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Hide widget'
    $compactMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Compact mode'
    $compactMenuItem.CheckOnClick = $true
    $notificationMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Desktop internet alerts'
    $notificationMenuItem.CheckOnClick = $true
    $startupMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Start with Windows'
    $startupMenuItem.CheckOnClick = $true
    $exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Exit'

    [void]$trayMenu.Items.Add($showHideMenuItem)
    [void]$trayMenu.Items.Add($compactMenuItem)
    [void]$trayMenu.Items.Add($notificationMenuItem)
    [void]$trayMenu.Items.Add($startupMenuItem)
    [void]$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$trayMenu.Items.Add($exitMenuItem)
    $notifyIcon.ContextMenuStrip = $trayMenu
    Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem

    $window.Add_MouseLeftButtonDown({
        try {
            $window.DragMove()
            Save-AppState -Window $window
        } catch {
        }
    })

    $namedElements.CloseButton.Add_Click({
        Hide-MainWindow -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem
    })
    $namedElements.PinButton.Add_Click({
        Set-PinVisual -Window $window -NamedElements $namedElements -IsPinned (-not $script:isPinned)
        Save-AppState -Window $window
    })
    $namedElements.CompactButton.Add_Click({
        $nextCompactState = -not [bool]$script:appConfig.IsCompact
        Set-CompactMode -Window $window -NamedElements $namedElements -IsCompact $nextCompactState
        $compactMenuItem.Checked = $nextCompactState
        Save-AppState -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem
    })

    $showHideMenuItem.Add_Click({
        if ($window.IsVisible) {
            Hide-MainWindow -Window $window
        } else {
            Show-MainWindow -Window $window
        }
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem
    })

    $compactMenuItem.Add_Click({
        Set-CompactMode -Window $window -NamedElements $namedElements -IsCompact $compactMenuItem.Checked
        Save-AppState -Window $window
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem
    })

    $notificationMenuItem.Add_Click({
        if ($script:appConfig) {
            $script:appConfig.EnableInternetNotifications = $notificationMenuItem.Checked
        }
        Save-AppConfig
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem
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
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem
    })

    $exitMenuItem.Add_Click({
        Exit-WidgetApplication -Window $window
    })

    $notifyIcon.Add_DoubleClick({
        if ($window.IsVisible) {
            Hide-MainWindow -Window $window
        } else {
            Show-MainWindow -Window $window
        }
        Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem
    })

    $window.Add_Closing({
        param($sender, $e)

        if (-not $script:isExiting) {
            $e.Cancel = $true
            Hide-MainWindow -Window $window
            Update-TrayMenu -Window $window -ShowHideMenuItem $showHideMenuItem -CompactMenuItem $compactMenuItem -NotificationMenuItem $notificationMenuItem -StartupMenuItem $startupMenuItem
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

    $renderFrame = {
        $snapshot = Get-PowerSnapshot -Computer $computer

        Add-HistoryPoint -History $tdpHistory -Value $snapshot.CpuRealtimeW
        Add-HistoryPoint -History $drainHistory -Value $snapshot.DrainDisplayW

        $namedElements.TdpValueText.Text = if ($null -ne $snapshot.CpuRealtimeW) { ('{0:N1} W' -f $snapshot.CpuRealtimeW) } else { '--' }
        $namedElements.TdpBadge.Text = 'CPU POWER'
        $namedElements.TdpMetaText.Text = if ($null -ne $snapshot.CpuRealtimeW) {
            'Realtime CPU package power.'
        } else {
            'Current backend does not expose CPU package/APU STAPM like HWMonitor.'
        }
        $namedElements.CompactCpuValueText.Text = $namedElements.TdpValueText.Text
        $namedElements.CompactCpuMetaText.Text = if ($null -ne $snapshot.CpuRealtimeW) {
            'Realtime package power'
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
            'Discharging' { '{0}: {1}' -f $snapshot.BatteryEtaLabel, (Format-Duration -TotalSeconds $snapshot.BatteryEtaSeconds) }
            'Charging' { '{0}: {1}' -f $snapshot.BatteryEtaLabel, (Format-Duration -TotalSeconds $snapshot.BatteryEtaSeconds) }
            'Plugged in' { 'On charger' }
            'Estimating' { 'Estimating battery life' }
            default { 'ETA unavailable' }
        }
        $namedElements.CompactEtaText.Text = $namedElements.EtaText.Text
        $namedElements.CompactBatteryText.Text = $namedElements.BatteryText.Text

        $voltText = if ($null -ne $snapshot.BatteryVoltageV) { Format-Number -Value $snapshot.BatteryVoltageV -Unit 'V' } else { 'N/A' }
        $currentText = if ($null -ne $snapshot.BatteryCurrentA) { Format-Number -Value $snapshot.BatteryCurrentA -Unit 'A' } else { 'N/A' }
        $fullText = if ($null -ne $snapshot.FullCapacityWh) { Format-Number -Value $snapshot.FullCapacityWh -Unit 'Wh full' } else { 'full cap N/A' }
        $namedElements.BatteryMetaText.Text = 'Pack {0} / {1}  |  {2}' -f $voltText, $currentText, $fullText
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




