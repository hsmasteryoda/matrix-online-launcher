#!/bin/bash
# The Matrix Online for Linux, pointed at our own server (mxoemu "Reality"): unpacks the community MxO client
# (MxO_7.6005.7z, from the folder this script is in or files.mxoemu.info), makes a copy of launcher.exe carrying our
# server's signing key, writes useropts.cfg, adds the two server names to /etc/hosts, sets up a Wine prefix and shortcuts.
# No game files are in this repo.
#
# usage: install-mxo-linux.sh [--dest DIR] [--server IP] [--archive FILE] [--no-desktop-icon] [--yes]
#   --dest     where to install (default: ask; ~/Games/mxo is suggested)
#   --server   server IP (default: SERVER= in mxo-installer.conf next to this script; WORLD= sets the world name)
#   --archive  the client archive (default: MxO_7.6005.7z next to this script, else download it)
#   --yes      don't ask anything (uses the defaults)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd); DEST=""; SERVER=""; ARCHIVE=""; DESKTOP_ICON=1; ASK=1
CLIENT_URL=https://files.mxoemu.info/MxO_7.6005.7z
WORLD=Reality AUTH=mxo-auth.home.arpa SUFFIX=.mxo.home.arpa   # WORLD must match GameServer.WorldName in the server's Reality.conf (set WORLD= in mxo-installer.conf)
DNS=""   # a public DNS name with wildcard sub-names (DNS= in mxo-installer.conf): then no hosts-file edit is needed
[ -f "$HERE/mxo-installer.conf" ] && . "$HERE/mxo-installer.conf"
while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST=$2; shift 2;;
    --server) SERVER=$2; shift 2;;
    --archive) ARCHIVE=$2; shift 2;;
    --no-desktop-icon) DESKTOP_ICON=0; shift;;
    --yes|-y) ASK=0; shift;;
    -h|--help) sed -n '2,13p' "$0"; exit 0;;
    *) echo "unknown option $1"; exit 1;;
  esac
done

# 0. the game-themed setup window (needs python3 + Tk); it runs this script again with --yes
if [ "$ASK" = 1 ] && [ -z "${RETRO_WIZARD:-}" ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ -f "$HERE/launcher/mxo_launcher.py" ] \
   && python3 -c 'import tkinter' 2>/dev/null; then
  exec python3 "$HERE/launcher/mxo_launcher.py" --install
fi

T="Matrix Online installer"
gui() { [ "$ASK" = 1 ] && command -v zenity >/dev/null && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; }
say() { echo "$*"; gui && zenity --info --title "$T" --text "$*" --width 460 2>/dev/null || true; }
die() { echo "ERROR: $*" >&2; gui && zenity --error --title "$T" --text "$*" --width 460 2>/dev/null; exit 1; }
SEVENZ=$(command -v 7z || command -v 7zz || command -v 7za || true)
[ -n "$SEVENZ" ] || die "Please install 7-Zip first (package 7zip or p7zip)."
[ -f "$HERE/server/signPub.dat" ] || die "server/signPub.dat is missing next to this script."

# 1. server address
if [ "$ASK" = 1 ]; then
  if gui; then
    SERVER=$(zenity --entry --title "$T" --width 460 --text "Server IP address\n(at home use the LAN address, elsewhere the public one):" \
      --entry-text "$SERVER" 2>/dev/null) || exit 1
  elif [ -t 0 ]; then
    read -r -p "Server IP [$SERVER]: " a; [ -n "$a" ] && SERVER="$a"
  fi
fi
if [ -n "$DNS" ] && [ -z "$SERVER" -o "$SERVER" = "$DNS" ]; then
  AUTH=$DNS; SUFFIX=".$DNS"; SERVER=$DNS
else
  [[ "$SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "The server must be an IP address (got '$SERVER')."
fi

# 2. where to install
if [ -z "$DEST" ]; then
  DEST="$HOME/Games/mxo"
  if gui; then
    zenity --question --title "$T" --width 460 --text "Install The Matrix Online into\n\n$DEST\n\n(about 6 GB)?" \
      --ok-label "Install here" --cancel-label "Choose another folder" 2>/dev/null || {
      pick=$(zenity --file-selection --directory --title "Choose a folder - MxO goes into an 'mxo' folder inside it" 2>/dev/null) || exit 1
      DEST="$pick/mxo"; }
  elif [ "$ASK" = 1 ] && [ -t 0 ]; then
    read -r -p "Install folder [$DEST]: " a; [ -n "$a" ] && DEST="$a"
  fi
fi
DEST=$(realpath -m "$DEST"); P="$DEST/pfx"; G="$P/drive_c/MxO"
mkdir -p "$G"
free=$(df -Pk "$DEST" | awk 'NR==2 {print $4}')
[ "$free" -gt 8388608 ] || die "Not enough space in $DEST: need 8 GB free, have $((free/1048576)) GB."

# 3. Wine: newest GE-Proton from Steam/Lutris if present (has DXVK), else the system wine
GE=$(ls -d "$HOME"/.local/share/Steam/compatibilitytools.d/GE-Proton*/files "$HOME"/.steam/root/compatibilitytools.d/GE-Proton*/files \
          "$HOME"/.local/share/lutris/runners/wine/*GE*/ 2>/dev/null | sort -V | tail -1 || true)
if [ -n "$GE" ] && [ -x "$GE/bin/wine" ]; then WINEBIN="$GE/bin"; DXVK="$GE/lib/wine/dxvk"
elif command -v wine >/dev/null; then WINEBIN=$(dirname "$(command -v wine)"); DXVK=""
else die "No Wine found. Install GE-Proton (e.g. with ProtonUp-Qt) or your distro's wine package, then run this again."; fi

# 4. client files
if [ ! -f "$G/client.dll" ]; then
  [ -n "$ARCHIVE" ] || ARCHIVE="$HERE/MxO_7.6005.7z"
  if [ ! -f "$ARCHIVE" ]; then
    ARCHIVE="$DEST/MxO_7.6005.7z"
    echo "Downloading the MxO client (1.3 GB) ..."
    curl -fL --retry 3 -o "$ARCHIVE.part" "$CLIENT_URL" && mv -f "$ARCHIVE.part" "$ARCHIVE" || die "Download failed."
  fi
  echo "Unpacking the client (6 GB) ..."
  if gui; then
    ( "$SEVENZ" x -y -o"$G" "$ARCHIVE" >/dev/null; echo $? > "$DEST/.unpack-rc" ) | zenity --progress --pulsate --auto-close \
      --no-cancel --title "$T" --text "Unpacking 6 GB of game files..." 2>/dev/null
    [ "$(cat "$DEST/.unpack-rc")" = 0 ] || die "Unpacking failed."; rm -f "$DEST/.unpack-rc"
  else "$SEVENZ" x -y -o"$G" "$ARCHIVE" >/dev/null || die "Unpacking failed."; fi
fi
[ -f "$G/launcher.exe" ] || die "launcher.exe not found after unpacking."

# 5. our launcher: a copy of launcher.exe with our server's signing key at both places the client checks it
python3 - "$G/launcher.exe" "$HERE/server/signPub.dat" "$G/MatrixPrivate.exe" <<'EOF'
import sys
exe, key, out = sys.argv[1:]
b = bytearray(open(exe, "rb").read()); k = open(key, "rb").read()
assert len(k) == 256, "signPub.dat must be 256 bytes"
assert b[0xB6080:0xB6180] == b[0xB6B38:0xB6C38] and b[0xB6180:0xB6188] == b"AuthServ", "unexpected launcher.exe version"
b[0xB6080:0xB6180] = k; b[0xB6B38:0xB6C38] = k
open(out, "wb").write(b)
EOF
keep=$(grep -iE '^\s*(ScreenWidth|ScreenHeight|Windowed)\s*=' "$G/useropts.cfg" 2>/dev/null || true)   # the launcher's Display choice
printf 'UseLaunchPad = 0\r\nAuthServerDNSName = "%s"\r\nMarginServerDNSSuffix = "%s"\r\n' "$AUTH" "$SUFFIX" > "$G/useropts.cfg"
[ -n "$keep" ] && printf '%s\n' "$keep" >> "$G/useropts.cfg"

# 6. server names -> /etc/hosts (the client looks the server up by name)
want="$SERVER $AUTH $WORLD$SUFFIX # matrix-online-installer"
HOSTS_NOTE=""
if [ "$SERVER" = "$DNS" ]; then :   # public name: DNS finds the server, nothing to add
elif ! grep -qxF "$want" /etc/hosts; then
  echo "Adding the server names to /etc/hosts (asks for your password) ..."
  cmd="sed -i '/# matrix-online-installer\$/d' /etc/hosts && echo '$want' >> /etc/hosts"
  if [ "$(id -u)" = 0 ]; then sh -c "$cmd"
  elif { gui || [ -n "${RETRO_WIZARD:-}" ]; } && command -v pkexec >/dev/null; then pkexec sh -c "$cmd" || HOSTS_NOTE=1
  elif [ -t 0 ]; then sudo sh -c "$cmd" || HOSTS_NOTE=1
  else HOSTS_NOTE=1; fi
fi
[ -z "$HOSTS_NOTE" ] || HOSTS_NOTE="

IMPORTANT: /etc/hosts couldn't be changed. Add this line to it (as root) before playing:
$want"

# 7. launcher script
cat > "$DEST/mxo.sh" <<EOF
#!/bin/bash
# The Matrix Online (our server). usage: mxo.sh [settings]   ("settings" runs the graphics auto-detect tool)
export WINEPREFIX="$P" WINEARCH=win64 WINEDEBUG=-all PATH="$WINEBIN:\$PATH" DXVK_LOG_LEVEL=none
${DXVK:+export WINEDLLOVERRIDES="d3d9=n,b"}
cd "$G"
if [ "\${1:-}" = settings ]; then exec wine autodetect_settings.exe; fi
exec wine MatrixPrivate.exe -nopatch -clone
EOF
chmod +x "$DEST/mxo.sh"

# 8. prefix + DXVK
echo "Setting up the Wine prefix (first run takes a minute)..."
export WINEPREFIX="$P" WINEARCH=win64 WINEDEBUG=-all PATH="$WINEBIN:$PATH"
wineboot -u >/dev/null 2>&1 || true
for d in "$DXVK/i386-windows/d3d9.dll" "$DXVK/x32/d3d9.dll"; do
  [ -n "$DXVK" ] && [ -f "$d" ] && { cp -f "$d" "$P/drive_c/windows/syswow64/d3d9.dll"; break; }
done
wineserver -w 2>/dev/null || true

# 9. shortcuts
# launcher: the period-style one (art read from the game files) when python3 + Tk are there, else the plain script
LAUNCH="\"$DEST/mxo.sh\""; ICON=applications-games
if [ -f "$HERE/launcher/mxo_launcher.py" ] && python3 -c 'import tkinter' 2>/dev/null; then
  mkdir -p "$DEST/launcher" && cp -f "$HERE"/launcher/*.py "$DEST/launcher/"
  printf 'SERVER=%s\nWORLD=%s\n' "$SERVER" "$WORLD" > "$DEST/mxo-installer.conf"
  echo "Reading the launcher art from the game files..."
  if python3 "$DEST/launcher/mxo_launcher.py" --extract >/dev/null 2>&1; then
    LAUNCH="python3 \"$DEST/launcher/mxo_launcher.py\""; ICON="$DEST/launcher/art/icon.png"
  fi
fi
APPS="$HOME/.local/share/applications"; mkdir -p "$APPS"
for kind in play settings; do
  if [ $kind = play ]; then name="The Matrix Online"; exec=$LAUNCH; file=mxo.desktop
  else name="The Matrix Online Settings"; exec="\"$DEST/mxo.sh\" settings"; file=mxo-settings.desktop; fi
  cat > "$APPS/$file" <<EOF
[Desktop Entry]
Type=Application
Name=$name
Exec=$exec
Path=$G
Icon=$ICON
Categories=Game;
EOF
done
DESK=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
if [ "$DESKTOP_ICON" = 1 ] && [ -d "$DESK" ]; then
  cp -f "$APPS/mxo.desktop" "$DESK/" && chmod +x "$DESK/mxo.desktop"
  gio set "$DESK/mxo.desktop" metadata::trusted true 2>/dev/null || true
fi

say "The Matrix Online is installed in $DEST.

Start it from the menu or desktop (\"The Matrix Online\"). New player? Type a new username and password at the login
screen and your account is made on the spot (use a password you don't use anywhere else).
Server: $SERVER (world $WORLD).$HOSTS_NOTE"
