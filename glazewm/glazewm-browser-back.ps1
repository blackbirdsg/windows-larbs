param(
  [ValidateSet('back', 'forward')]
  [string]$Direction = 'back'
)
$ErrorActionPreference = 'Stop'
$logPath = Join-Path $env:LOCALAPPDATA 'larbs-windows\logs\browser-back.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null

function Write-BackLog {
  param([string]$Message)
  Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
}

Add-Type @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class BrowserNavigation {
  private const uint WM_APPCOMMAND = 0x0319;
  private const int APPCOMMAND_BROWSER_BACKWARD = 1;

  [DllImport("user32.dll")]
  private static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

  [DllImport("user32.dll")]
  private static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, UIntPtr extraInfo);

  [DllImport("user32.dll")]
  private static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

  public static bool Navigate(string direction) {
    var window = GetForegroundWindow();
    if (window == IntPtr.Zero) return false;

    uint processId;
    GetWindowThreadProcessId(window, out processId);
    try {
      var name = Process.GetProcessById((int)processId).ProcessName.ToLowerInvariant();
      if (name != "brave" && name != "chrome" && name != "msedge" && name != "firefox") return false;
    } catch {
      return false;
    }

    var appCommandId = direction == "forward" ? 2 : 1;
    var appCommand = new IntPtr(appCommandId << 16);
    SendMessage(window, WM_APPCOMMAND, window, appCommand);

    var browserKey = direction == "forward" ? (byte)0xA7 : (byte)0xA6;
    const uint keyUp = 0x0002;
    keybd_event(browserKey, 0, 0, UIntPtr.Zero);
    keybd_event(browserKey, 0, keyUp, UIntPtr.Zero);
    return true;
  }
}
'@

if ([BrowserNavigation]::Navigate($Direction)) {
  Write-BackLog "Browser $Direction command sent."
} else {
  Write-BackLog 'Ignored: the foreground window was not a supported browser.'
}
