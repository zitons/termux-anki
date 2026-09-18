#!/usr/bin/env bash
set -Eeuo pipefail

# Install Anki in a Debian proot on Termux and run it through a local VNC server.
#
# Install or continue:
#   bash install-termux-anki-vnc.sh
#
# Check current progress only:
#   bash install-termux-anki-vnc.sh --check
#
# Start Anki after install:
#   ~/start-anki-vnc.sh
#
# Connect from Android VNC client:
#   Host: 127.0.0.1
#   Port: 5901
#   Password: ankianki, unless VNC_PASSWORD was set during install
#
# Optional environment variables:
#   ANKI_USER=anki          Debian user to create/use
#   ANKI_PRE=0             Set to 1 to install beta/pre-release aqt
#   DISTRO=debian          proot-distro name
#   VNC_DISPLAY=:1         VNC display, :1 means TCP port 5901
#   VNC_GEOMETRY=anki      anki fits VNC to Anki's window; auto uses Android wm size; or set WxH
#   VNC_START_GEOMETRY=1280x960 temporary geometry used before Anki appears
#   VNC_DEPTH=24           VNC color depth
#   VNC_LOCALHOST=no       no listens on 0.0.0.0; yes listens only on loopback
#   VNC_PASSWORD=ankianki  VNC password, minimum 6 chars
#   ANKI_SCALE=1.5         Qt UI scale factor
#   ANKI_FONT_DPI=144      Qt font DPI
#   ANKI_WINDOW_SIZE=phone phone uses Android wm size; none disables resizing; or set WxH

DISTRO="${DISTRO:-debian}"
ANKI_USER="${ANKI_USER:-anki}"
ANKI_PRE="${ANKI_PRE:-0}"
VNC_DISPLAY="${VNC_DISPLAY:-:1}"
VNC_GEOMETRY="${VNC_GEOMETRY:-anki}"
VNC_START_GEOMETRY="${VNC_START_GEOMETRY:-1280x960}"
VNC_DEPTH="${VNC_DEPTH:-24}"
VNC_LOCALHOST="${VNC_LOCALHOST:-no}"
VNC_PASSWORD="${VNC_PASSWORD:-ankianki}"
ANKI_SCALE="${ANKI_SCALE:-1.5}"
ANKI_FONT_DPI="${ANKI_FONT_DPI:-144}"
ANKI_WINDOW_SIZE="${ANKI_WINDOW_SIZE:-phone}"
MODE="install"

for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    -h|--help)
      sed -n '1,28p' "$0"
      exit 0
      ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

log() {
  printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

warn() {
  printf '\n[WARN] %s\n' "$*" >&2
}

die() {
  printf '\n[ERROR] %s\n' "$*" >&2
  exit 1
}

status() {
  case "$1" in
    ok) printf '[DONE]    %s\n' "$2" ;;
    missing) printf '[MISSING] %s\n' "$2" ;;
    warn) printf '[WARN]    %s\n' "$2" ;;
  esac
}

step() {
  printf '\n== Step %s/%s: %s ==\n' "$1" "$2" "$3"
}

require_termux() {
  if [[ -z "${PREFIX:-}" || ! -d "/data/data/com.termux/files/usr" ]]; then
    die "This script must be run inside Termux on Android."
  fi
}

termux_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

rootfs_dir() {
  printf '%s/var/lib/proot-distro/installed-rootfs/%s' "$PREFIX" "$DISTRO"
}

check_termux_host() {
  step 1 6 "Termux host packages"
  local missing=0
  for pkg in proot-distro pulseaudio; do
    if termux_pkg_installed "$pkg"; then
      status ok "Termux package installed: $pkg"
    else
      status missing "Termux package missing: $pkg"
      missing=1
    fi
  done
  return "$missing"
}

check_debian_rootfs() {
  step 2 6 "Debian proot rootfs"
  if [[ -d "$(rootfs_dir)" ]]; then
    status ok "proot-distro rootfs exists: $DISTRO"
  else
    status missing "proot-distro rootfs missing: $DISTRO"
    return 1
  fi
}

run_debian_check() {
  local check_script="${TMPDIR:-/tmp}/anki-debian-vnc-check.sh"

  cat > "$check_script" <<'DEBIAN_CHECK'
#!/usr/bin/env bash
set -Eeuo pipefail

ANKI_USER="${ANKI_USER:?}"

status() {
  case "$1" in
    ok) printf '[DONE]    %s\n' "$2" ;;
    missing) printf '[MISSING] %s\n' "$2" ;;
  esac
}

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

missing=0

printf '\n== Step 3/6: Debian runtime and VNC packages ==\n'
for pkg in ca-certificates dbus-x11 fonts-noto-cjk libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-shape0 libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 libnss3 locales mpv openbox python3 python3-pip python3-pyqt6.qtmultimedia python3-pyqt6.qtquick python3-pyqt6.qtwebengine python3-venv sudo tigervnc-standalone-server x11-xserver-utils xauth xdotool xterm; do
  if pkg_installed "$pkg"; then
    status ok "Debian package installed: $pkg"
  else
    status missing "Debian package missing: $pkg"
    missing=1
  fi
done

printf '\n== Step 4/6: libpci3 segfault workaround ==\n'
if pkg_installed libpci3; then
  status missing "libpci3 is installed and should be purged"
  missing=1
else
  status ok "libpci3 is not installed"
fi
if apt-mark showhold 2>/dev/null | grep -qx 'libpci3'; then
  status ok "libpci3 is held"
else
  status missing "libpci3 is not held"
  missing=1
fi

printf '\n== Step 5/6: Debian user, Anki and VNC config ==\n'
if id "$ANKI_USER" >/dev/null 2>&1; then
  status ok "Debian user exists: $ANKI_USER"
else
  status missing "Debian user missing: $ANKI_USER"
  missing=1
fi

user_home="$(getent passwd "$ANKI_USER" | cut -d: -f6 || true)"
if [[ -n "$user_home" && -x "$user_home/pyenv/bin/anki" ]]; then
  status ok "Anki launcher exists: $user_home/pyenv/bin/anki"
else
  status missing "Anki venv launcher missing"
  missing=1
fi

if [[ -n "$user_home" && "$(cat "$user_home/.local/share/Anki2/gldriver6" 2>/dev/null || true)" == "software" ]]; then
  status ok "Anki gldriver6 is set to software"
else
  status missing "Anki gldriver6 software setting missing"
  missing=1
fi

if [[ -n "$user_home" && -x "$user_home/.config/tigervnc/xstartup" && -s "$user_home/.config/tigervnc/passwd" ]]; then
  status ok "VNC xstartup and password are configured"
else
  status missing "VNC xstartup or password missing"
  missing=1
fi

exit "$missing"
DEBIAN_CHECK

  chmod +x "$check_script"
  proot-distro login "$DISTRO" --shared-tmp -- env ANKI_USER="$ANKI_USER" bash "/tmp/$(basename "$check_script")"
}

check_termux_launcher() {
  step 6 6 "Termux VNC launcher"
  if [[ -x "${HOME}/start-anki-vnc.sh" ]]; then
    status ok "Launcher exists: ~/start-anki-vnc.sh"
  else
    status missing "Launcher missing: ~/start-anki-vnc.sh"
    return 1
  fi
}

check_all() {
  require_termux
  local rc=0
  check_termux_host || rc=1
  if check_debian_rootfs; then
    run_debian_check || rc=1
  else
    rc=1
  fi
  check_termux_launcher || rc=1

  if [[ "$rc" == "0" ]]; then
    log "All steps appear complete."
  else
    log "Some steps are missing. Run without --check to continue installation."
  fi
  return "$rc"
}

install_termux_host() {
  step 1 6 "Install Termux host packages"
  if check_termux_host >/dev/null 2>&1; then
    status ok "Termux host packages already installed"
    return
  fi

  pkg update -y
  pkg upgrade -y
  pkg install -y proot-distro pulseaudio
}

install_debian_rootfs() {
  step 2 6 "Install Debian proot rootfs"
  if [[ -d "$(rootfs_dir)" ]]; then
    status ok "proot-distro rootfs already exists: $DISTRO"
    return
  fi
  proot-distro install "$DISTRO"
}

configure_debian() {
  step 3 6 "Configure Debian, VNC and Anki"
  local setup_script="${TMPDIR:-/tmp}/anki-debian-vnc-setup.sh"

  cat > "$setup_script" <<'DEBIAN_SETUP'
#!/usr/bin/env bash
set -Eeuo pipefail

ANKI_USER="${ANKI_USER:?}"
ANKI_PRE="${ANKI_PRE:?}"
VNC_PASSWORD="${VNC_PASSWORD:?}"

log() {
  printf '\n[debian %s] %s\n' "$(date +%H:%M:%S)" "$*"
}

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

wait_for_apt_locks() {
  local waited=0
  local timeout=900
  while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
    if [[ "$waited" -ge "$timeout" ]]; then
      printf '[ERROR] Timed out waiting for apt/dpkg locks. Check running apt processes with: ps -ef | grep -E "apt|dpkg"\n' >&2
      exit 1
    fi
    printf '[debian] Waiting for another apt/dpkg process to finish... %ss/%ss\n' "$waited" "$timeout"
    sleep 10
    waited=$((waited + 10))
  done
}

install_missing_packages() {
  local missing=()
  for pkg in "$@"; do
    if ! pkg_installed "$pkg"; then
      missing+=("$pkg")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    wait_for_apt_locks
    apt-get install -y "${missing[@]}"
  else
    log "Requested Debian packages already installed"
  fi
}

export DEBIAN_FRONTEND=noninteractive

log "Updating Debian package indexes"
wait_for_apt_locks
apt-get update
wait_for_apt_locks
apt-get upgrade -y

log "Holding libpci3 before package installation"
wait_for_apt_locks
apt-mark hold libpci3 >/dev/null 2>&1 || true

log "Installing VNC, window manager, Qt, Python and Anki runtime packages"
install_missing_packages \
  ca-certificates \
  dbus-x11 \
  fonts-noto-cjk \
  libxcb-cursor0 \
  libxcb-icccm4 \
  libxcb-image0 \
  libxcb-keysyms1 \
  libxcb-randr0 \
  libxcb-render-util0 \
  libxcb-shape0 \
  libxcb-xinerama0 \
  libxcb-xkb1 \
  libxkbcommon-x11-0 \
  libnss3 \
  locales \
  mpv \
  openbox \
  python3 \
  python3-pip \
  python3-pyqt6.qtmultimedia \
  python3-pyqt6.qtquick \
  python3-pyqt6.qtwebengine \
  python3-venv \
  sudo \
  tigervnc-standalone-server \
  x11-xserver-utils \
  xauth \
  xdotool \
  xterm

if pkg_installed libpci3; then
  log "Removing libpci3 to avoid known Qt/Anki segfaults in Termux proot"
  wait_for_apt_locks
  apt-get purge -y libpci3
fi
wait_for_apt_locks
apt-mark hold libpci3 >/dev/null 2>&1 || true

log "Configuring locale"
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen en_US.UTF-8

if ! id "$ANKI_USER" >/dev/null 2>&1; then
  log "Creating non-root user: $ANKI_USER"
  adduser --disabled-password --gecos "" "$ANKI_USER"
  usermod -aG sudo "$ANKI_USER"
else
  log "Debian user already exists: $ANKI_USER"
fi

log "Installing/updating Anki and VNC config for user: $ANKI_USER"
su - "$ANKI_USER" -c '
  set -Eeuo pipefail
  cd "$HOME"
  if [[ ! -x pyenv/bin/python ]]; then
    python3 -m venv --system-site-packages pyenv
  fi
  pyenv/bin/pip install --upgrade pip
  if [[ "'"$ANKI_PRE"'" == "1" ]]; then
    pyenv/bin/pip install --upgrade --pre aqt
  else
    pyenv/bin/pip install --upgrade aqt
  fi

  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/Anki2" "$HOME/.config/tigervnc"
  echo software > "$HOME/.local/share/Anki2/gldriver6"

  if [[ -d "$HOME/.vnc" && ! -L "$HOME/.vnc" ]]; then
    legacy_backup="$HOME/.vnc.legacy.$(date +%Y%m%d%H%M%S)"
    mv "$HOME/.vnc" "$legacy_backup"
  fi

  printf "%s\n" "'"$VNC_PASSWORD"'" | vncpasswd -f > "$HOME/.config/tigervnc/passwd"
  chmod 600 "$HOME/.config/tigervnc/passwd"

  cat > "$HOME/.local/bin/anki-vnc" <<'"'"'ANKI_LAUNCHER'"'"'
#!/usr/bin/env bash
set -Eeuo pipefail
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export QT_OPENGL="${QT_OPENGL:-software}"
export QT_SCALE_FACTOR="${QT_SCALE_FACTOR:-1.5}"
export QT_FONT_DPI="${QT_FONT_DPI:-144}"
export QTWEBENGINE_DISABLE_SANDBOX="${QTWEBENGINE_DISABLE_SANDBOX:-1}"
export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:---disable-seccomp-filter-sandbox --disable-gpu}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$USER}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
exec "$HOME/pyenv/bin/anki"
ANKI_LAUNCHER
  chmod +x "$HOME/.local/bin/anki-vnc"

  cat > "$HOME/.config/tigervnc/xstartup" <<'"'"'VNC_XSTARTUP'"'"'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export QT_QPA_PLATFORM=xcb
export QT_OPENGL=software
export QT_SCALE_FACTOR="${QT_SCALE_FACTOR:-1.5}"
export QT_FONT_DPI="${QT_FONT_DPI:-144}"
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-seccomp-filter-sandbox --disable-gpu"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$USER}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
if [[ -r "$HOME/.config/tigervnc/anki-session-env" ]]; then
  . "$HOME/.config/tigervnc/anki-session-env"
fi
openbox-session >/tmp/openbox-session.log 2>&1 &
sleep 1
"$HOME/.local/bin/anki-vnc" >/tmp/anki-vnc.log 2>&1 &
if [[ "${VNC_FIT_TO_ANKI:-0}" == "1" || -n "${ANKI_TARGET_GEOMETRY:-}" ]]; then
  : > /tmp/anki-window-resize.log
  echo "target=${ANKI_TARGET_GEOMETRY:-}, fit=${VNC_FIT_TO_ANKI:-0}" >> /tmp/anki-window-resize.log
  for _ in $(seq 1 80); do
    anki_window="$(xdotool search --onlyvisible --class anki 2>/dev/null | tail -n 1 || true)"
    if [[ -z "$anki_window" ]]; then
      anki_window="$(xdotool search --onlyvisible --class Anki 2>/dev/null | tail -n 1 || true)"
    fi
    if [[ -z "$anki_window" ]]; then
      anki_window="$(xdotool search --onlyvisible --name Anki 2>/dev/null | tail -n 1 || true)"
    fi
    if [[ -n "$anki_window" ]]; then
      echo "window=$anki_window" >> /tmp/anki-window-resize.log
      if [[ "${ANKI_TARGET_GEOMETRY:-}" =~ ^([0-9]+)x([0-9]+)$ ]]; then
        target_w="${BASH_REMATCH[1]}"
        target_h="${BASH_REMATCH[2]}"
        xrandr --fb "${target_w}x${target_h}" >/tmp/vnc-xrandr.log 2>&1 || true
        xdotool windowactivate "$anki_window" >/tmp/anki-window-activate.log 2>&1 || true
        xdotool windowsize "$anki_window" "$target_w" "$target_h" >/tmp/anki-window-size.log 2>&1 || true
        xdotool windowmove "$anki_window" 0 0 >/tmp/anki-window-move.log 2>&1 || true
        eval "$(xdotool getwindowgeometry --shell "$anki_window" 2>/dev/null || true)"
        echo "requested=${target_w}x${target_h} actual=${WIDTH:-?}x${HEIGHT:-?}" >> /tmp/anki-window-resize.log
        break
      fi
      eval "$(xdotool getwindowgeometry --shell "$anki_window" 2>/dev/null || true)"
      if [[ "${WIDTH:-0}" -gt 0 && "${HEIGHT:-0}" -gt 0 ]]; then
        xrandr --fb "${WIDTH}x${HEIGHT}" >/tmp/vnc-xrandr.log 2>&1 || true
        echo "fit=${WIDTH}x${HEIGHT}" >> /tmp/anki-window-resize.log
        break
      fi
    fi
    sleep 0.25
  done
fi
wait
VNC_XSTARTUP
  chmod +x "$HOME/.config/tigervnc/xstartup"
'

log "Debian VNC setup complete"
DEBIAN_SETUP

  chmod +x "$setup_script"
  proot-distro login "$DISTRO" --shared-tmp -- env ANKI_USER="$ANKI_USER" ANKI_PRE="$ANKI_PRE" VNC_PASSWORD="$VNC_PASSWORD" bash "/tmp/$(basename "$setup_script")"
}

write_termux_launcher() {
  step 6 6 "Write Termux VNC launcher"
  local launcher="${HOME}/start-anki-vnc.sh"

  cat > "$launcher" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

DISTRO="${DISTRO}"
ANKI_USER="${ANKI_USER}"
VNC_DISPLAY="\${VNC_DISPLAY:-${VNC_DISPLAY}}"
VNC_GEOMETRY="\${VNC_GEOMETRY:-${VNC_GEOMETRY}}"
VNC_START_GEOMETRY="\${VNC_START_GEOMETRY:-${VNC_START_GEOMETRY}}"
VNC_DEPTH="\${VNC_DEPTH:-${VNC_DEPTH}}"
VNC_LOCALHOST="\${VNC_LOCALHOST:-${VNC_LOCALHOST}}"
ANKI_SCALE="\${ANKI_SCALE:-${ANKI_SCALE}}"
ANKI_FONT_DPI="\${ANKI_FONT_DPI:-${ANKI_FONT_DPI}}"
ANKI_WINDOW_SIZE="\${ANKI_WINDOW_SIZE:-${ANKI_WINDOW_SIZE}}"

vnc_port=\$((5900 + \${VNC_DISPLAY#:}))
PHONE_GEOMETRY=""
if command -v wm >/dev/null 2>&1; then
  PHONE_GEOMETRY="\$(wm size 2>/dev/null | grep -Eo '[0-9]+x[0-9]+' | tail -n 1 || true)"
fi
ANKI_TARGET_GEOMETRY=""
if [[ "\$ANKI_WINDOW_SIZE" == "phone" ]]; then
  if [[ "\$PHONE_GEOMETRY" =~ ^[0-9]+x[0-9]+$ ]]; then
    ANKI_TARGET_GEOMETRY="\$PHONE_GEOMETRY"
  else
    ANKI_TARGET_GEOMETRY="600x1200"
  fi
elif [[ "\$ANKI_WINDOW_SIZE" != "none" && "\$ANKI_WINDOW_SIZE" =~ ^[0-9]+x[0-9]+$ ]]; then
  ANKI_TARGET_GEOMETRY="\$ANKI_WINDOW_SIZE"
fi

VNC_FIT_TO_ANKI=0
if [[ "\$VNC_GEOMETRY" == "anki" ]]; then
  if [[ -n "\$ANKI_TARGET_GEOMETRY" ]]; then
    VNC_GEOMETRY="\$ANKI_TARGET_GEOMETRY"
  else
    VNC_FIT_TO_ANKI=1
    VNC_GEOMETRY="\$VNC_START_GEOMETRY"
  fi
elif [[ "\$VNC_GEOMETRY" == "auto" ]]; then
  if [[ "\$PHONE_GEOMETRY" =~ ^[0-9]+x[0-9]+$ ]]; then
    VNC_GEOMETRY="\$PHONE_GEOMETRY"
  else
    VNC_GEOMETRY="600x1200"
  fi
fi

pulseaudio --start \\
  --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \\
  --exit-idle-time=-1 >/dev/null 2>&1 || true

exec proot-distro login "\$DISTRO" --user "\$ANKI_USER" --shared-tmp -- \\
  env PULSE_SERVER=127.0.0.1 \\
      VNC_DISPLAY="\$VNC_DISPLAY" \\
      VNC_GEOMETRY="\$VNC_GEOMETRY" \\
      VNC_DEPTH="\$VNC_DEPTH" \\
      VNC_LOCALHOST="\$VNC_LOCALHOST" \\
      VNC_FIT_TO_ANKI="\$VNC_FIT_TO_ANKI" \\
      ANKI_TARGET_GEOMETRY="\$ANKI_TARGET_GEOMETRY" \\
      QT_SCALE_FACTOR="\$ANKI_SCALE" \\
      QT_FONT_DPI="\$ANKI_FONT_DPI" \\
      bash -lc '
        set -Eeuo pipefail
        if [[ -d "\$HOME/.vnc" && ! -L "\$HOME/.vnc" ]]; then
          legacy_backup="\$HOME/.vnc.legacy.\$(date +%Y%m%d%H%M%S)"
          mv "\$HOME/.vnc" "\$legacy_backup"
          echo "Moved legacy VNC config to \$legacy_backup"
        fi
        port=\$((5900 + \${VNC_DISPLAY#:}))
        echo "Connect AVNC/bVNC to 127.0.0.1:\$port"
        echo "Geometry: \$VNC_GEOMETRY, Anki window: \${ANKI_TARGET_GEOMETRY:-default}, Qt scale: \${QT_SCALE_FACTOR:-unset}, Qt font DPI: \${QT_FONT_DPI:-unset}"
        if [[ "\${VNC_FIT_TO_ANKI:-0}" == "1" ]]; then
          echo "VNC will resize to Anki window after Anki appears."
        fi
        mkdir -p "\$HOME/.config/tigervnc"
        {
          printf "VNC_FIT_TO_ANKI=%q\n" "\${VNC_FIT_TO_ANKI:-0}"
          printf "ANKI_TARGET_GEOMETRY=%q\n" "\${ANKI_TARGET_GEOMETRY:-}"
          printf "QT_SCALE_FACTOR=%q\n" "\${QT_SCALE_FACTOR:-}"
          printf "QT_FONT_DPI=%q\n" "\${QT_FONT_DPI:-}"
        } > "\$HOME/.config/tigervnc/anki-session-env"
        echo "If 127.0.0.1 fails, try localhost:\$port"
        if vncserver -list 2>/dev/null | awk "{print \\\$1}" | grep -qx "\$VNC_DISPLAY"; then
          vncserver -kill "\$VNC_DISPLAY" >/dev/null 2>&1 || true
        fi
        echo "VNC is starting in the foreground. Keep this Termux session open while connected."
        exec vncserver "\$VNC_DISPLAY" -localhost "\$VNC_LOCALHOST" -geometry "\$VNC_GEOMETRY" -depth "\$VNC_DEPTH" -fg
      '
EOF

  chmod +x "$launcher"
  status ok "Launcher written: ~/start-anki-vnc.sh"
}

install_all() {
  require_termux
  if [[ "${#VNC_PASSWORD}" -lt 6 ]]; then
    die "VNC_PASSWORD must be at least 6 characters."
  fi

  install_termux_host
  install_debian_rootfs
  configure_debian
  write_termux_launcher

  log "Install run complete. Current status:"
  check_all || true

  printf '\nStart VNC Anki with:\n  ~/start-anki-vnc.sh\n\n'
  printf 'Then connect from AVNC/bVNC:\n  Host: 127.0.0.1\n  Port: 5901\n  Password: %s\n\n' "$VNC_PASSWORD"
}

if [[ "$MODE" == "check" ]]; then
  check_all
else
  install_all
fi
