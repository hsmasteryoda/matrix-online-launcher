# The Matrix Online installer for Windows, pointed at our own server (mxoemu "Reality").
# Unpacks the community MxO client (MxO_7.6005.7z from this folder / the folder above, else files.mxoemu.info) with
# 7-Zip's 7zr.exe, makes MatrixPrivate.exe = launcher.exe carrying our server's signing key, writes useropts.cfg, adds the
# two server names to the hosts file and makes Desktop/Start menu shortcuts. Nothing is bundled in the repo.
# Start it with "Install The Matrix Online.bat" (asks for admin rights once - needed for the hosts file).
param([string]$Dest = "", [string]$Server = "", [switch]$Quiet)

$ErrorActionPreference = "Stop"
$ClientUrl = "https://files.mxoemu.info/MxO_7.6005.7z"
$SevenZipUrl = "https://www.7-zip.org/a/7zr.exe"
$World = "Reality"; $AuthName = "mxo-auth.home.arpa"; $Suffix = ".mxo.home.arpa"; $Dns = ""   # $World must match GameServer.WorldName (WORLD= in mxo-installer.conf)
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Up = Split-Path -Parent $Here
foreach ($conf in @("$Here\mxo-installer.conf", "$Up\mxo-installer.conf")) {
    if ((Test-Path $conf) -and -not $Server) {
        foreach ($line in Get-Content $conf) {
            if ($line -match '^\s*SERVER=(.*)$') { $Server = $Matches[1].Trim('"', ' ') }
            if ($line -match '^\s*WORLD=(.*)$') { $World = $Matches[1].Trim('"', ' ') }
            if ($line -match '^\s*DNS=(.*)$') { $Dns = $Matches[1].Trim('"', ' ') }   # public name with wildcard sub-names: no hosts file needed
        }
    }
}
if (-not $Dest) { $Dest = "C:\Games\MatrixOnline" }
function Find-Local($name) { foreach ($d in @($Here, $Up)) { if (Test-Path "$d\$name") { return "$d\$name" } }; return $null }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Net.Http
[System.Windows.Forms.Application]::EnableVisualStyles()
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromHours(2)

# ---------- the period look (banner + colours) and the game launcher, compiled on this PC from launcher\*.cs ----------
# (C# that ships with Windows; the launcher reads its pictures and icon out of the game's own files - none are shipped)
$LauncherDir = @("$Here\launcher", "$Here\..\windows\launcher") | Where-Object { Test-Path "$_\RetroArt.cs" } | Select-Object -First 1
$LauncherSrc = @(); $Retro = $false
if ($LauncherDir) {
    $LauncherSrc = @(Get-ChildItem $LauncherDir -Filter *.cs | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) })
    try {
        Add-Type -TypeDefinition ([System.IO.File]::ReadAllText("$LauncherDir\RetroArt.cs")) -ReferencedAssemblies System.Windows.Forms, System.Drawing
        $Retro = $true
    } catch { }
}
function Set-Look($banner, $bannerH, $bg, $fg, $accent, $box) {
    foreach ($c in @($form.Controls)) {
        $c.Top += $bannerH
        if ($c -is [System.Windows.Forms.TextBox]) { $c.BackColor = $box; $c.ForeColor = $fg; $c.BorderStyle = "FixedSingle" }
        elseif ($c -is [System.Windows.Forms.Button]) {
            $c.FlatStyle = "Flat"; $c.BackColor = $box; $c.ForeColor = $accent; $c.FlatAppearance.BorderColor = $accent
        }
        elseif ($c -is [System.Windows.Forms.ProgressBar]) { }
        else { $c.ForeColor = $fg; $c.BackColor = $bg }
    }
    $form.BackColor = $bg; $form.Height += $bannerH
    $banner.SetBounds(0, 0, $form.ClientSize.Width, $bannerH); $form.Controls.Add($banner)
}
# Builds "<dest>\<exeName>" and lets it read its art; returns the exe, or $null (shortcuts then start the game directly)
function Build-Launcher($dest, $exeName, $conf) {
    $log = Join-Path $dest "launcher-build.log"     # anything that goes wrong is written here
    if (-not $LauncherSrc.Count) { "launcher source (windows\launcher\*.cs) not found next to the installer" | Set-Content $log; return $null }
    $exe = Join-Path $dest $exeName
    try {
        $cp = New-Object System.CodeDom.Compiler.CompilerParameters
        $cp.GenerateExecutable = $true; $cp.OutputAssembly = $exe; $cp.CompilerOptions = "/target:winexe /optimize"
        [void]$cp.ReferencedAssemblies.AddRange([string[]]@("System.dll", "System.Drawing.dll", "System.Windows.Forms.dll"))
        $r = (New-Object Microsoft.CSharp.CSharpCodeProvider).CompileAssemblyFromSource($cp, [string[]]$LauncherSrc)
        if ($r.Errors.HasErrors) { $r.Errors | ForEach-Object { $_.ToString() } | Set-Content $log; return $null }
        [System.IO.File]::WriteAllText((Join-Path $dest "launcher.conf"), $conf)
        $p = Start-Process -FilePath $exe -ArgumentList "--extract" -WorkingDirectory $dest -PassThru
        while (-not $p.HasExited) { Start-Sleep -Milliseconds 200; [System.Windows.Forms.Application]::DoEvents() }
    } catch { "$($_.Exception.Message)" | Set-Content $log; if (-not (Test-Path $exe)) { return $null } }
    # built: use it even if the art didn't come out (it tries again, and says why, when it starts)
    if (-not (Test-Path (Join-Path $dest "launcher-art\strings.txt"))) { "launcher built, but reading the art from launcher.exe failed" | Set-Content $log }
    if (Test-Path $exe) { return $exe }
    return $null
}

# ---------- window ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "The Matrix Online installer"; $form.Size = New-Object System.Drawing.Size(560, 330)
$form.StartPosition = "CenterScreen"; $form.FormBorderStyle = "FixedDialog"; $form.MaximizeBox = $false
function Add-Label($text, $y) {
    $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.Location = New-Object System.Drawing.Point(16, $y)
    $l.AutoSize = $true; $form.Controls.Add($l)
}
function Add-Box($text, $y, $w) {
    $b = New-Object System.Windows.Forms.TextBox; $b.Text = $text; $b.Location = New-Object System.Drawing.Point(16, $y)
    $b.Width = $w; $form.Controls.Add($b); $b
}
Add-Label "Install folder (about 6 GB):" 14
$destBox = Add-Box $Dest 34 420
$browse = New-Object System.Windows.Forms.Button; $browse.Text = "Browse..."; $browse.Location = New-Object System.Drawing.Point(444, 32)
$form.Controls.Add($browse)
$browse.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = "Choose a folder - MxO goes into a 'MatrixOnline' folder inside it"
    if ($d.ShowDialog() -eq "OK") { $destBox.Text = Join-Path $d.SelectedPath "MatrixOnline" }
})
Add-Label "Server (IP address, or the server's DNS name):" 66
$serverBox = Add-Box $(if ($Dns) { $Dns } else { $Server }) 86 510
$desk = New-Object System.Windows.Forms.CheckBox; $desk.Text = "Desktop shortcut"; $desk.Checked = $true
$desk.Location = New-Object System.Drawing.Point(16, 118); $desk.AutoSize = $true; $form.Controls.Add($desk)
$bar = New-Object System.Windows.Forms.ProgressBar; $bar.Location = New-Object System.Drawing.Point(16, 152); $bar.Width = 510
$bar.Style = "Marquee"; $bar.MarqueeAnimationSpeed = 0; $form.Controls.Add($bar)
$status = New-Object System.Windows.Forms.Label; $status.Location = New-Object System.Drawing.Point(16, 182)
$status.Size = New-Object System.Drawing.Size(510, 50); $form.Controls.Add($status)
$go = New-Object System.Windows.Forms.Button; $go.Text = "Install"; $go.Location = New-Object System.Drawing.Point(370, 252)
$go.Size = New-Object System.Drawing.Size(75, 28); $form.Controls.Add($go)
$quit = New-Object System.Windows.Forms.Button; $quit.Text = "Close"; $quit.Location = New-Object System.Drawing.Point(451, 252)
$quit.Size = New-Object System.Drawing.Size(75, 28); $form.Controls.Add($quit); $quit.Add_Click({ $form.Close() })
if ($Retro) {
    $banner = New-Object Retro.MatrixRain; $banner.Title = "THE MATRIX ONLINE"; $banner.Sub = "setup  //  world $World"
    Set-Look $banner 170 ([System.Drawing.Color]::FromArgb(5, 10, 5)) ([System.Drawing.Color]::FromArgb(159, 232, 159)) `
        ([System.Drawing.Color]::FromArgb(56, 232, 72)) ([System.Drawing.Color]::FromArgb(12, 26, 12))
}

function Set-Status($text) { $status.Text = $text; [System.Windows.Forms.Application]::DoEvents() }

function Get-Url($url, $file) {
    $resp = $http.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    if (-not $resp.IsSuccessStatusCode) { throw "Download failed: $url ($($resp.StatusCode))" }
    $total = $resp.Content.Headers.ContentLength
    $in = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $out = [System.IO.File]::Create("$file.part"); $done = 0
    try {
        $buf = New-Object byte[] 1048576
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n); $done += $n
            if ($total) { Set-Status ("Downloading {0}: {1:N0} of {2:N0} MB" -f (Split-Path -Leaf $file), ($done / 1MB), ($total / 1MB)) }
        }
    } finally { $out.Close(); $in.Close() }
    Move-Item -Force "$file.part" $file
}

# Run a program without freezing the window
function Invoke-Quiet($exe, $argList) {
    $p = Start-Process -FilePath $exe -ArgumentList $argList -WindowStyle Hidden -PassThru
    while (-not $p.HasExited) { Start-Sleep -Milliseconds 200; [System.Windows.Forms.Application]::DoEvents() }
    return $p.ExitCode
}

function Install-Mxo {
    $dest = $destBox.Text.Trim(); $server = $serverBox.Text.Trim()
    $byName = $Dns -and $server -eq $Dns
    if ($byName) { $script:AuthName = $Dns; $script:Suffix = ".$Dns" }
    elseif ($server -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "The server must be an IP address (or the DNS name from mxo-installer.conf)." }
    $sig = Find-Local "server\signPub.dat"
    if (-not $sig -or (Get-Item $sig).Length -ne 256) { throw "server\signPub.dat (256 bytes) is missing next to the installer." }
    New-Item -ItemType Directory -Force $dest | Out-Null
    $drive = (Get-Item $dest).PSDrive
    if ($drive.Free -lt 8GB) { throw "Not enough space on $($drive.Name): need 8 GB free." }
    $bar.MarqueeAnimationSpeed = 30

    if (-not (Test-Path "$dest\client.dll")) {
        $archive = Find-Local "MxO_7.6005.7z"
        if (-not $archive) { $archive = "$dest\MxO_7.6005.7z"; if (-not (Test-Path $archive)) { Get-Url $ClientUrl $archive } }
        $seven = Find-Local "7zr.exe"
        if (-not $seven) { $seven = "$dest\7zr.exe"; if (-not (Test-Path $seven)) { Get-Url $SevenZipUrl $seven } }
        Set-Status "Unpacking 6 GB of game files (a few minutes)..."
        $rc = Invoke-Quiet $seven @("x", "-y", "-o`"$dest`"", "`"$archive`"")
        if ($rc -ne 0) { throw "Unpacking failed (7-Zip exit code $rc)." }
    }
    if (-not (Test-Path "$dest\launcher.exe")) { throw "launcher.exe not found after unpacking." }

    Set-Status "Pointing the game at the server..."
    $b = [System.IO.File]::ReadAllBytes("$dest\launcher.exe"); $k = [System.IO.File]::ReadAllBytes($sig)
    $tag = [System.Text.Encoding]::ASCII.GetString($b, 0xB6180, 8)
    $same = $true; for ($i = 0; $i -lt 256; $i++) { if ($b[0xB6080 + $i] -ne $b[0xB6B38 + $i]) { $same = $false; break } }
    if ($tag -ne "AuthServ" -or -not $same) { throw "Unexpected launcher.exe version - can't add the server key." }
    [Array]::Copy($k, 0, $b, 0xB6080, 256); [Array]::Copy($k, 0, $b, 0xB6B38, 256)
    [System.IO.File]::WriteAllBytes("$dest\MatrixPrivate.exe", $b)
    [System.IO.File]::WriteAllText("$dest\useropts.cfg", "UseLaunchPad = 0`r`nAuthServerDNSName = `"$AuthName`"`r`nMarginServerDNSSuffix = `"$Suffix`"`r`n")

    if (-not $byName) {   # by IP: the client looks the server up by name, so the names go in the hosts file
        Set-Status "Adding the server names to the hosts file..."
        $hosts = "$env:WINDIR\System32\drivers\etc\hosts"
        $lines = @(Get-Content $hosts -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '# matrix-online-installer$' })
        $lines += "$server $AuthName $World$Suffix # matrix-online-installer"
        Set-Content -Path $hosts -Value $lines -Encoding ASCII
    }

    Set-Status "Building the launcher (reads the original launcher's skin from launcher.exe)..."
    $launcher = Build-Launcher $dest "MxO Launcher.exe" "SERVER=$server`r`nWORLD=$World`r`n"
    $play = if ($launcher) { @("MxO Launcher.exe", "") } else { @("MatrixPrivate.exe", "-nopatch -clone") }
    if (-not $launcher) {
        [System.Windows.Forms.MessageBox]::Show("The MxO launcher couldn't be built on this PC, so the shortcuts start the game directly.`n`nThe reason is in $dest\launcher-build.log", "The Matrix Online installer", "OK", "Warning") | Out-Null
    }

    Set-Status "Making shortcuts..."
    $sh = New-Object -ComObject WScript.Shell
    $menu = Join-Path ([Environment]::GetFolderPath("CommonPrograms")) "The Matrix Online"
    New-Item -ItemType Directory -Force $menu | Out-Null
    $links = @(@("$menu\The Matrix Online.lnk", $play[0], $play[1]), @("$menu\The Matrix Online Settings.lnk", "autodetect_settings.exe", ""))
    if ($desk.Checked) { $links += , @((Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "The Matrix Online.lnk"), $play[0], $play[1]) }
    foreach ($l in $links) {
        $s = $sh.CreateShortcut($l[0]); $s.TargetPath = Join-Path $dest $l[1]; $s.Arguments = $l[2]; $s.WorkingDirectory = $dest
        if ($launcher -and $l[1] -eq $play[0] -and (Test-Path (Join-Path $dest "launcher-art\icon.ico"))) { $s.IconLocation = Join-Path $dest "launcher-art\icon.ico" }
        $s.Save()
    }
    $bar.MarqueeAnimationSpeed = 0
    Set-Status "Done."
    [System.Windows.Forms.MessageBox]::Show("The Matrix Online is installed in $dest.`n`nStart it with the 'The Matrix Online' shortcut. New player? Type a new username and password at the login screen and your account is made on the spot (use a password you don't use anywhere else).`nServer: $server (world $World).", "The Matrix Online installer") | Out-Null
}

$go.Add_Click({
    $go.Enabled = $false
    try { Install-Mxo } catch { $bar.MarqueeAnimationSpeed = 0; Set-Status "Failed."; [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "The Matrix Online installer", "OK", "Error") | Out-Null }
    $go.Enabled = $true
})
if ($Quiet) { Install-Mxo } else { [void]$form.ShowDialog() }
