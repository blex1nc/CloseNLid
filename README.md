# CloseNLid

**Coded by Blex** · [Türkçe](README.tr.md)

A macOS menu bar app that keeps your MacBook awake with the lid closed.
No external display, dock or charger required — downloads, renders, builds and
servers keep running in your bag or on a shelf with the lid shut.

---

## Install

Requirements: macOS 14 (Sonoma) or later, Command Line Tools
(`xcode-select --install`). Xcode is not needed.

```bash
git clone https://github.com/blex1nc/CloseNLid.git
cd CloseNLid
./Scripts/bundle.sh && open dist/CloseNLid.app
```

The app lives in the menu bar as a bolt icon and does not appear in the Dock.
It is ad-hoc signed, so Gatekeeper may warn on first launch — if so,
**right-click the app → Open**, or allow it under
**System Settings → Privacy & Security → Open Anyway**.

For permanent use, move `dist/CloseNLid.app` to `/Applications`. Launch at
login only works from the bundled `.app`.

---

## First launch: the permission rule

Sleep on lid close is kernel-level behavior; blocking it needs root. To avoid
asking for your password on every toggle, a one-time sudoers rule is installed
on first launch. The settings window opens directly on the **Access** pane;
**Install Rule…** asks for your admin password once and writes:

```
/etc/sudoers.d/closenlid
<your-username> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
```

The scope is deliberately this narrow: no wildcards, only these two exact
commands run without a password. The file is validated with `visudo -c` before
being copied into `/etc/sudoers.d` — a broken rule would lock up all sudo use on
the machine.

To remove it, use **Access → Remove Rule…**, or by hand:

```bash
sudo rm /etc/sudoers.d/closenlid
```

---

## Features

**Sleep** — master switch and duration: indefinite, 30 minutes, 1 hour,
2 hours. In timed mode the remaining time counts down next to the menu bar icon.

**Status** — lid open or closed, sleep blocked or not, power source and
temperature. All read without root. Anything that needs attention (running on
battery, hot with the lid closed, sleep blocked by something else) shows up here.

**Battery** — when unplugged and the battery drops below the threshold, the
sleep block turns itself off and a notification explains why. Default 20%.
With the lid closed the screen is dark, so macOS's own low-battery warning is
invisible; this guard closes that gap. Below the threshold the switch won't
turn on.

**Thermal** — airflow is restricted with the lid closed, so there is a separate
warning threshold. When exceeded, the menu bar icon turns into a warning sign
and a line appears in the menu; no modal window (nobody would see it with the
lid closed anyway). Optionally it can turn the block off automatically at a
critical temperature — off by default.

**General** — version, launch at login, quit behavior.

---

## How it works

Two layers:

1. **`pmset -a disablesleep 1`** — the setting that actually prevents sleep on
   lid close. Needs root, is system-wide and persistent.
2. **IOPM assertion** (`PreventUserIdleSystemSleep`) — prevents idle sleep,
   needs no permission, and is released automatically if the process dies.

The assertion alone is not enough: lid close ignores assertions. The second
layer ensures that if the process crashes, idle sleep behavior is at least
restored.

Even when `pmset` returns zero, the setting is verified by reading it back from
IOPMrootDomain; otherwise the UI could show "on" while the Mac sleeps on lid
close.

Display sleep is left alone — the panel turns off with the lid closed anyway.

### The setting persists, the app doesn't

`disablesleep` is a system setting that survives reboots. The app restores
normal sleep on quit. If the app is killed somehow, the setting stays on; that's
why CloseNLid reads the real system state on every launch and adopts it — the
switch shows as on and you can turn it off.

---

## Menu bar

- `bolt.fill` — sleep blocked
- `bolt.slash` — normal sleep
- `exclamationmark.triangle.fill` — sleep blocked and temperature threshold exceeded

The menu has a quick toggle, duration picker, live status rows, settings and quit.

---

## Development

```bash
swift build            # build
swift run CloseNLid    # run unbundled (launch at login won't work)
./Scripts/bundle.sh    # bundle .app, render icon, ad-hoc sign
```

Probes:

```bash
CloseNLid --probe                 # was the status item actually drawn?
CloseNLid --settings battery      # open settings on that pane
CloseNLid --make-icon icon.png    # render the app icon
```

A universal build (arm64 + x86_64) needs full Xcode; without it the script
builds for this machine's architecture.

---

## Icon not showing in the menu bar?

When the menu bar is full, macOS doesn't remove the item — it hides it behind
the notch, leaving nothing to click. The app detects this on launch and warns
once. Fix: remove another menu bar icon, or ⌘-drag to rearrange. To check
directly:

```bash
dist/CloseNLid.app/Contents/MacOS/CloseNLid --probe
```

---

## Good to know

- A Mac running with the lid closed, keyboard deck on a surface and airflow
  restricted, gets warm. For heavy work, leaving the lid slightly open or
  placing it on a hard surface makes a difference.
- Keep battery protection on when unplugged; with the lid closed there's no
  other way to notice the battery running out.
- The app sends no data anywhere. It only talks to macOS power management.

---

## License

[MIT](LICENSE) © 2026 Blex
