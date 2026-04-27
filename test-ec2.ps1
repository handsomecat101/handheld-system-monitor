try {
    $kernelCode = @"
using System;
using System.Runtime.InteropServices;
namespace SystemMonitorTest2 {
    public static class Kernel32Bridge {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool SetDllDirectory(string lpPathName);
    }
    public static class InpOutBridge {
        [DllImport("inpoutx64.dll", EntryPoint = "Out32")]
        public static extern void Out32(short portAddress, short data);
        [DllImport("inpoutx64.dll", EntryPoint = "Inp32")]
        public static extern short Inp32(short portAddress);
    }
}
"@
    Add-Type -TypeDefinition $kernelCode -Language CSharp
    [SystemMonitorTest2.Kernel32Bridge]::SetDllDirectory("c:\Users\PC\Documents\Playground\Workspaces\SystemMonitor-Widget-next\amd")

    function Invoke-EcReadByte {
        param([int]$Offset)
        [SystemMonitorTest2.InpOutBridge]::Out32(0x4E, 0x2E)
        [SystemMonitorTest2.InpOutBridge]::Out32(0x4F, 0x11)
        [SystemMonitorTest2.InpOutBridge]::Out32(0x4E, 0x2F)
        [SystemMonitorTest2.InpOutBridge]::Out32(0x4F, [int16](($Offset -shr 8) -band 0xFF))

        [SystemMonitorTest2.InpOutBridge]::Out32(0x4E, 0x2E)
        [SystemMonitorTest2.InpOutBridge]::Out32(0x4F, 0x10)
        [SystemMonitorTest2.InpOutBridge]::Out32(0x4E, 0x2F)
        [SystemMonitorTest2.InpOutBridge]::Out32(0x4F, [int16]($Offset -band 0xFF))

        [SystemMonitorTest2.InpOutBridge]::Out32(0x4E, 0x2E)
        [SystemMonitorTest2.InpOutBridge]::Out32(0x4F, 0x12)
        [SystemMonitorTest2.InpOutBridge]::Out32(0x4E, 0x2F)
        return ([SystemMonitorTest2.InpOutBridge]::Inp32(0x4F) -band 0xFF)
    }

    $pwm = Invoke-EcReadByte -Offset 0x047A
    $rpmMsb = Invoke-EcReadByte -Offset 0x0478
    $rpmLsb = Invoke-EcReadByte -Offset 0x0479
    $rpm = (($rpmMsb -shl 8) -bor $rpmLsb)
    
    Write-Host ("PWM: " + $pwm)
    Write-Host ("RPM MSB: " + $rpmMsb)
    Write-Host ("RPM LSB: " + $rpmLsb)
    Write-Host ("RPM: " + $rpm)
} catch {
    Write-Host "Error:" $_.Exception.Message
}
