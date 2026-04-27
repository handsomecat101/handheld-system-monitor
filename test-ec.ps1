$dllPath = 'c:\Users\PC\Documents\Playground\Workspaces\SystemMonitor-Widget-next\amd\inpoutx64.dll'
try {
    $kernelCode = @"
using System;
using System.Runtime.InteropServices;
namespace SystemMonitorTest {
    public static class Kernel32Bridge {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool SetDllDirectory(string lpPathName);
    }
}
"@
    Add-Type -TypeDefinition $kernelCode -Language CSharp
    [SystemMonitorTest.Kernel32Bridge]::SetDllDirectory("c:\Users\PC\Documents\Playground\Workspaces\SystemMonitor-Widget-next\amd")
    
    $code = @"
using System;
using System.Runtime.InteropServices;
namespace SystemMonitorTest {
    public static class InpOutBridge {
        [DllImport("inpoutx64.dll", EntryPoint = "Inp32")]
        public static extern short Inp32(short portAddress);
    }
}
"@
    Add-Type -TypeDefinition $code -Language CSharp
    
    $res = [SystemMonitorTest.InpOutBridge]::Inp32(0x4F)
    Write-Host ("Success, Inp32 returned: " + $res)
} catch {
    Write-Host "Error:" $_.Exception.Message
}
