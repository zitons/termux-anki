# Termux Anki

Run desktop Anki on Android with Termux, Debian proot, and a local VNC session.

This is aimed at phones where Termux:X11 is awkward for touch input. The default setup uses TigerVNC + Openbox, then connects from an Android VNC client such as AVNC.

Inspired by the Anki Discord discussion:

https://discord.com/channels/368267295601983490/1216428695481487460

Chinese version: [README.zh-CN.md](README.zh-CN.md)

## Screenshots

![Anki on Termux via VNC](58ed37870fa78a00e835d2f295345d2a.jpg)

![Anki VNC on Android](8562ca6acd67fc381e82969e7709c87d.jpg)

## Requirements

- Android device with ARM64 CPU
- Termux
- A few GB of free storage
- Wi-Fi recommended for the first install
- Android VNC client, recommended: AVNC

## Install

One-command install from GitHub:

```bash
pkg install -y curl && curl -L -o install-termux-anki-vnc.sh https://raw.githubusercontent.com/zitons/termux-anki/main/install-termux-anki-vnc.sh && bash install-termux-anki-vnc.sh
```

Copy the repository into Termux, then run:

```bash
bash install-termux-anki-vnc.sh
```

The installer is safe to run more than once. It checks completed steps and continues missing work.

To check progress only:

```bash
bash install-termux-anki-vnc.sh --check
```

## Start

Start the VNC-backed Anki session:

```bash
~/start-anki-vnc.sh
```

Keep this Termux session open while using Anki. The VNC server runs in the foreground so proot does not kill it when the launcher exits.

Then connect from AVNC/bVNC:

```text
Host: 127.0.0.1
Port: 5901
Username: leave blank
Password: ankianki
```

If your VNC app has a single address field, use:

```text
127.0.0.1:5901
```

## Display Tuning

The default profile is phone-oriented:

```text
VNC_GEOMETRY=anki
ANKI_SCALE=1.5
ANKI_FONT_DPI=144
ANKI_WINDOW_SIZE=phone
```

`ANKI_WINDOW_SIZE=phone` reads Android's `wm size`, then resizes the Anki window to that size after Anki starts. With the default `VNC_GEOMETRY=anki`, the VNC desktop uses the same phone size. If `wm size` cannot be read, it falls back to `600x1200`.

You can override it when starting:

```bash
VNC_GEOMETRY=auto ~/start-anki-vnc.sh
```

`auto` uses Android's `wm size` output directly. For example, if Android reports `1080x2400`, the VNC desktop uses `1080x2400`. If it cannot be read, it falls back to `600x1200`.

You can also set a fixed size:

```bash
VNC_GEOMETRY=720x1280 ANKI_SCALE=1.25 ~/start-anki-vnc.sh
```

For larger UI:

```bash
VNC_GEOMETRY=854x1080 ANKI_SCALE=1.5 ~/start-anki-vnc.sh
```

For more horizontal room:

```bash
VNC_GEOMETRY=1200x1080 ANKI_SCALE=1.25 ~/start-anki-vnc.sh
```

In AVNC, touchpad/trackpad mode usually works better than direct touch for desktop Anki.

## Options

Set these when installing or starting:

```bash
ANKI_USER=anki
ANKI_PRE=0
DISTRO=debian
VNC_DISPLAY=:1
VNC_GEOMETRY=anki
VNC_START_GEOMETRY=1280x960
VNC_DEPTH=24
VNC_LOCALHOST=no
VNC_PASSWORD=ankianki
ANKI_SCALE=1.5
ANKI_FONT_DPI=144
ANKI_WINDOW_SIZE=phone
```

Install Anki beta/pre-release:

```bash
ANKI_PRE=1 bash install-termux-anki-vnc.sh
```

Use a custom VNC password:

```bash
VNC_PASSWORD=yourpass bash install-termux-anki-vnc.sh
```

The VNC password must be at least 6 characters.

## Stop

Stop the VNC server:

```bash
proot-distro login debian --user anki -- vncserver -kill :1
```

## Troubleshooting

Check whether the VNC port is reachable from Termux:

```bash
timeout 3 bash -c 'head -c 12 < /dev/tcp/127.0.0.1/5901'
```

Expected output begins with:

```text
RFB
```

If you get `Connection refused`, the VNC server is not running.

View Anki logs:

```bash
proot-distro login debian --user anki --shared-tmp -- tail -n 80 /tmp/anki-vnc.log
```

If VNC reports a migration error from `~/.vnc` to `~/.config/tigervnc`, rerun the installer. It writes the new TigerVNC config path and backs up old `~/.vnc` directories.

## Notes

The installer includes the known Termux/proot Anki workarounds:

- holds/removes `libpci3` to avoid Debian ARM64 proot segmentation faults
- writes `~/.local/share/Anki2/gldriver6` with `software`
- starts Anki with `QTWEBENGINE_CHROMIUM_FLAGS="--disable-seccomp-filter-sandbox --disable-gpu"`
- uses software OpenGL by default

## Contributing

PRs are welcome, especially for better phone display profiles, VNC client recommendations, and device-specific fixes.
