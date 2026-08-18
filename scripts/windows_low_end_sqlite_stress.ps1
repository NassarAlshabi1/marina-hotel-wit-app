$ErrorActionPreference = 'Stop'

# Windows Job Object CPU rate control: CpuRate is hundredths of a percent.
Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class LowEndCpuLimiter {
    private const int JobObjectCpuRateControlInformation = 15;
    private const uint Enable = 0x1;
    private const uint HardCap = 0x4;

    [StructLayout(LayoutKind.Sequential)]
    private struct CpuRateControlInformation {
        public uint ControlFlags;
        public uint CpuRate;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(
        IntPtr job,
        int informationClass,
        IntPtr information,
        uint informationLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    public static IntPtr Create(uint percent) {
        if (percent < 1 || percent > 100) {
            throw new ArgumentOutOfRangeException("percent");
        }

        var job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }

        var info = new CpuRateControlInformation {
            ControlFlags = Enable | HardCap,
            CpuRate = percent * 100
        };
        var size = Marshal.SizeOf<CpuRateControlInformation>();
        var buffer = Marshal.AllocHGlobal(size);
        try {
            Marshal.StructureToPtr(info, buffer, false);
            if (!SetInformationJobObject(job, JobObjectCpuRateControlInformation, buffer, (uint)size)) {
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            }
        } finally {
            Marshal.FreeHGlobal(buffer);
        }
        return job;
    }

    public static void Assign(IntPtr job, Process process) {
        if (!AssignProcessToJobObject(job, process.Handle)) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
"@

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot 'mobile'
$logPath = Join-Path $mobileDir 'sqlite-low-end-stress-windows.log'
$errorPath = Join-Path $mobileDir 'sqlite-low-end-stress-windows.err.log'
$cpuPercent = 25

Write-Host "WINDOWS_SQLITE_STRESS cpu_cap_percent=$cpuPercent"
$process = Start-Process `
    -FilePath $env:ComSpec `
    -WorkingDirectory $mobileDir `
    -ArgumentList @('/c', 'flutter.bat', 'test', 'test/performance/sqlite_low_end_stress_test.dart', '--reporter', 'expanded') `
    -RedirectStandardOutput $logPath `
    -RedirectStandardError $errorPath `
    -PassThru

$job = [LowEndCpuLimiter]::Create($cpuPercent)
try {
    [LowEndCpuLimiter]::Assign($job, $process)
    $process.WaitForExit()
} finally {
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
}

Get-Content $logPath
if (Test-Path $errorPath) {
    Get-Content $errorPath
}
if ($process.ExitCode -ne 0) {
    throw "SQLite stress test failed with exit code $($process.ExitCode)"
}

$line = Select-String -Path $logPath -Pattern 'SQLITE_LOW_END_STRESS' | Select-Object -Last 1
if ($null -eq $line) {
    throw 'SQLite stress metrics were not found in the test output'
}
Write-Host "WINDOWS_SQLITE_STRESS_RESULT $($line.Line)"
