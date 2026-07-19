$ErrorActionPreference = 'Stop'

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
  Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
    '-NoProfile',
    '-Sta',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    "`"$PSCommandPath`""
  )
  return
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class ActiveWindowCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

  [DllImport("dwmapi.dll")]
  public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
}
'@

$handle = [ActiveWindowCapture]::GetForegroundWindow()
if ($handle -eq [IntPtr]::Zero) {
  return
}

$rect = New-Object ActiveWindowCapture+RECT
$dwmResult = [ActiveWindowCapture]::DwmGetWindowAttribute(
  $handle,
  9,
  [ref] $rect,
  [Runtime.InteropServices.Marshal]::SizeOf([type] 'ActiveWindowCapture+RECT')
)

if ($dwmResult -ne 0) {
  [void] [ActiveWindowCapture]::GetWindowRect($handle, [ref] $rect)
}

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -le 0 -or $height -le 0) {
  return
}

$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
$graphics.Dispose()

[System.Windows.Forms.Clipboard]::SetImage($bitmap)
$bitmap.Dispose()
