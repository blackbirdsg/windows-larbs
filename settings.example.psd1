@{
  Accent = @{
    Base = '#4b0706'
    Bright = '#8a1714'
    Text = '#ffd8d6'
  }

  Workspaces = @{
    One = 'PM'
    Two = 'Teams'
  }

  # Used when Codex does not expose an active project directory to the Yazi launcher.
  DefaultProjectDirectory = ''

  Browser = @{
    HomeUrl = 'https://start.duckduckgo.com/'
  }

  # Keep private company URLs in settings.local.psd1, which is ignored by Git.
  Urls = @{
    ProjectManagement = ''
    SourceControl = ''
    Onshape = 'https://cad.onshape.com/documents'
    Tasks = 'https://tasks.google.com/tasks/'
  }

  Vpn = @{
    ProfileId = ''
    DisplayName = 'VPN'
  }

  # Windows can hide the current SSID from non-elevated processes. Add only
  # trusted saved profile names here if a fallback is useful on your machine.
  Wifi = @{
    PreferredSsidFallbacks = @()
  }

  Codex = @{
    VimiumLauncher = ''
  }

  # Leave values empty for automatic discovery. Set an executable or .lnk path
  # only when an app is installed somewhere unusual.
  Apps = @{
    Brave = ''
    KiCad = ''
    BambuStudio = ''
    Wireshark = ''
    GoogleEarth = ''
    QGIS = ''
    OBS = ''
    TeXstudio = ''
    MarkText = ''
    Neovim = ''
    OpenVpnConnect = ''
    PowerToysRun = ''
    WindowsTerminal = ''
    Yazi = ''
  }
}

