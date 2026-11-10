# Clamshell Discharge

**English** | [한국어](README.ko.md)

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/waps99)

A battery-care menu bar app for people who use an Apple Silicon MacBook **with the lid closed (clamshell) on an external monitor**.

- Keeps the battery **around 60%** while plugged in, to slow down aging. On macOS 26.4+ it does this **with the macOS charge limit itself**, so the Mac runs on power at 60% **without charging or using the battery**.
- **Charges ahead of your commute and leave times**, and for a trip, one tap charges to **80% / 100% right now**.
- Shows **battery temperature** and protects the battery when it gets hot.
- Can **actively discharge** while plugged in, and stays awake in clamshell mode.
- Shows battery health (SOH), capacity and usage history, and keeps a **daily log for years** (optionally in iCloud Drive).

<p>
  <img src="docs/screenshots/popover-en.png" width="640" alt="Menu bar popover: battery status on the left; maintain charge, commute/leave/weekend charge and charge now on the right">
</p>

*The menu bar popover. Battery status and capacity on the left, modes on the right: maintain charge at 60%, the commute charge editor (08:00 · 80%), leave and weekend outing charge, and charge now with a departure choice.*

<details>
<summary>Dashboard · Korean UI</summary>

<p>
  <img src="docs/screenshots/dashboard-en.png" width="420" alt="Dashboard (English)">
  <img src="docs/screenshots/dashboard-ko.png" width="420" alt="Dashboard (Korean)">
</p>
<p>
  <img src="docs/screenshots/popover-ko.png" width="640" alt="Popover (Korean)">
</p>

*The dashboard has status cards, the capacity bar, a charge chart (with maintain/commute/leave target lines), a daily SOH chart, and detailed settings for maintain charge and the three schedules (commute, leave, weekend). Chart axes and times follow the selected language.*
</details>

> **Windows preview:** a Windows 10/11 version with the same UI is in progress. Charge control currently supports Lenovo only. See [windows/README.md](windows/README.md).

Holding the level uses the **macOS charge limit** through a small helper (see [Permissions](#2-permissions-the-app-asks-for)). Adapter blocking (SMC), used for manual discharge and as a fallback, uses the tool and permissions installed by the [actuallymentor/battery](https://github.com/actuallymentor/battery) CLI. This app adds charge maintenance, scheduled charging, clamshell sleep control, and the UI on top.

## Why

- A laptop that is always plugged in sits near 100% for long periods, which ages the battery quickly.
- macOS 26.4+ has a charge limit, but System Settings only goes down to **80%**.
- On macOS 27 battery firmware, the SMC keys that "only stop charging" (`CH0B`, `CH0C`, `CHTE`) are rejected, so classic charge-limit apps can only **cut the adapter** (the Mac then runs on battery, cycling it and heating it under load).

This app sets the **macOS charge limit below 80%** (e.g. 60%) so macOS itself holds the level on power, and falls back to adapter blocking (`CHIE`) where that isn't available. It also handles the clamshell problems that adapter blocking causes.

## Features

| Feature | Description |
|---|---|
| **Maintain charge** | While plugged in, keeps the battery at a level you choose between 60% and 100% (60% recommended). **macOS charge limit mode (default, macOS 26.4+):** the level is written as the macOS charge limit; if the battery is above it, macOS eases it down while plugged in, then holds it with **0 mA — not charging, not discharging, running on power**. It keeps holding even while the app is closed. **Sailing mode (fallback):** at the target it blocks the adapter and runs on battery; after it drops 3%, charging resumes. Can be limited to "lid closed only". |
| **Commute charge** | If the Mac stays plugged in at home overnight, charges to the target (default 80%) before your commute time (default 08:00). Until then it holds the maintain level (60%). |
| **Weekend outing charge** | A weekend schedule for when the time differs from your commute (default Sat/Sun 10:00 · 80%, off). |
| **Charge now (trip)** | Charges to 80% or 100% regardless of schedules. Choose **Leave: Now / In 1·2·3 h**, and it **starts late so it finishes just before you leave**, using this Mac's real charge rate learned from history, so the battery doesn't sit at a high level for long. It turns off when you unplug after reaching the target, or after 24 hours. Priority: charge now → commute/leave/weekend → maintain. |
| **Leave charge** | Set a leave time (default 18:00), days, how early to start (default 90 min), and a target (default 100%). In that window it pauses maintain mode and charges to the target, then returns to maintain mode 30 minutes after the leave time. |
| **Schedule editor** | Commute, leave and weekend outing charge share one editor: time (−/+ 15 min, menu of common times), start lead (30–180 min before), target (80/90/100% or a 60–100% slider), and days. |
| **Auto work mode** | While plugged in with an external monitor, the Mac stays awake with the lid closed (even while the adapter is blocked). On battery, or with the lid closed and no monitor, it sleeps right away. |
| **Leave detection** | If you unplug the external monitor or the adapter with the lid closed, it stops discharging/blocking, restores the sleep setting, and sleeps immediately. |
| **Heat protection** | In sailing mode, if the battery reaches a set temperature (default 35°C, 32–42°C), it stops running on battery and uses adapter power until it cools by 2°C. Shown as 🌡. |
| **Battery temperature** | Shown in the menu bar (e.g. `60% 32°`, 🔥 at 40°C+), the popover and the dashboard: normal below 35°C, warm 35–40°C, hot 40°C+. |
| **Wake the display** | (Sailing mode only.) In clamshell mode a USB or Bluetooth keyboard/mouse can wake the displays. **With Input Monitoring allowed**, the adapter stays blocked while the displays sleep, so the battery holds near 60%; on input the app switches to AC and turns the display on. Without the permission it switches to AC as soon as the displays sleep to guarantee waking (the battery may then charge to 80%). |
| **Manual discharge** | Discharges to a target (50–90%) while plugged in. You can change the target while it runs, and it stays awake in clamshell mode. |
| **Popover (main screen)** | Battery % and state, 4-hour usage history, power source and time remaining, a capacity bar (current / max / design) with SOH, power, current, voltage, cycles and temperature, plus controls for every mode. Everything fits on one screen without scrolling. |
| **Dashboard** | Charge chart (6 h to 30 days), daily SOH chart, and detailed settings for maintain charge and the commute/leave/weekend schedules (time entry to the minute). History is saved locally every minute (with temperature) and kept for 90 days. |
| **Daily log (permanent)** | One line per day (SOH, cycles, max/design capacity, max temperature) is kept indefinitely (10 years ≈ a few hundred KB), so the SOH chart covers the battery's whole life. If iCloud Drive is on, it's copied to **iCloud Drive › ClamshellDischarge › `<model>-<device id>.csv`**, one file per Mac — no server. |
| **Languages** | 한국어 · English · 日本語 · 简体中文. Follows the system language by default; change it in ⚙︎ → Language. |

## Requirements

- Apple Silicon MacBook, macOS 13 or later. **macOS 26.4 or later** for macOS charge limit mode (holding without using the battery).
- [battery CLI](https://github.com/actuallymentor/battery) installed (needs an administrator password)
  ```bash
  curl -s https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash
  ```
- **Remove other charge-management apps** such as AlDente. They touch the same SMC keys and conflict.

## Install

### 1. Download and first launch (allow it in Gatekeeper)

The app is not signed or notarized with a paid Apple Developer ID, so the first time you open it macOS blocks it as an "unidentified developer". Allow it **once** like this:

1. Download `ClamshellDischarge-<version>.zip` from [Releases](../../releases), unzip it, and move `ClamshellDischarge.app` to `/Applications`.
2. Open the app. When a "cannot be opened" or "unidentified developer" dialog appears, click **Done** (or Cancel).
3. Go to **System Settings → Privacy & Security**. In the Security section near the bottom, where it says *"ClamshellDischarge" was blocked*, click **Open Anyway**.
4. Confirm with your administrator password (or Touch ID), then click **Open** in the next dialog.

> Since macOS 15 (Sequoia), **right-click → Open** no longer bypasses Gatekeeper. Use **Open Anyway** as above.
>
> If you're comfortable with Terminal, you can instead remove the download flag: `xattr -dr com.apple.quarantine /Applications/ClamshellDischarge.app`

### 2. Permissions the app asks for

Depending on the features you use, the app needs the permissions below. Each is a **one-time** setup.

| Permission | When it's needed | How to allow it |
|---|---|---|
| **battery CLI install** (administrator password) | Everything that blocks the adapter: maintain charge, scheduled charging, discharge | Run the install command from [Requirements](#requirements) in Terminal. It creates `/etc/sudoers.d/battery` so the SMC write commands run without a password. |
| **macOS charge limit** (administrator password) | Maintain charge and schedules in macOS charge limit mode | Click **Set up** next to maintain charge in the popover (or in the dashboard). It installs a root-owned helper `/usr/local/libexec/clamshell-charge-limit` that accepts only a number from 50 to 100, and `/etc/sudoers.d/clamshell-charge-limit`, which allows only that helper. |
| **Sleep control** (administrator password) | Manual discharge and auto work mode (staying awake with the lid closed) | Click **Set up permission (once)…** in the popover and enter your password. It creates `/etc/sudoers.d/clamshell-discharge`, which allows only the two commands below. This is needed because no password dialog can be shown while the lid is closed. |
| **Input Monitoring** | Turning the display on with a Bluetooth keyboard or mouse | macOS asks on first launch. If you missed it, click **Open Settings** in the popover, or turn on ClamshellDischarge in **System Settings → Privacy & Security → Input Monitoring**, then restart the app. It only detects **whether** input happened, never which keys were pressed, and only while the displays are off. |
| **Login item** (optional) | Opening at login | Popover ⚙︎ → **Open at login**. macOS shows a "Login item added" notification. |

Rules added by these permissions:

```
<user> ALL = (root) NOPASSWD: /usr/local/libexec/clamshell-charge-limit
<user> ALL = (root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

### 3. Updating

- After replacing the app with a new zip, you may need to do **Open Anyway** from step 1 again.
- Release zips are ad-hoc signed, so macOS may treat a new version as a different app and **Input Monitoring may stop applying**. If the app shows "Permission needed" even though it's on in the Input Monitoring list, remove ClamshellDischarge from the list with **−**, then restart the app and allow it again.
- The sleep control permission and the battery CLI don't depend on the app signature, so they stay.
- When building from source, if you have an Apple Development certificate (free with an Apple ID in Xcode), `./build.sh --install` signs with it and permissions survive rebuilds. See [Build](#build).

## Usage

### First-time setup (5 minutes)

1. Install the battery CLI, then install and open the app ([Install](#install)).
2. Click the menu bar icon to open the popover, then click **Set up permission (once)…**.
3. Under **Modes**, turn on:
   - **Maintain charge 60%**: auto work mode turns on with it. If it shows "Permission needed to hold without using the battery", click **Set up** and enter your password (once). For **Apply** just below, **Always** is recommended, so it also holds 60% while you work at home with the lid open. **Lid closed only** holds it only in clamshell mode (e.g. at the office).
   - **Commute charge / Leave charge**: set your commute and leave times and targets ([see below](#set-commute-and-leave-times)).
   - **Bluetooth wake** (only matters in sailing mode): turn it on and allow Input Monitoring. It detects USB input as well as Bluetooth.
4. Turn on ⚙︎ → **Open at login**.

### Day to day (office, lid closed, external monitor)

- Just use your Mac. The popover shows "macOS charge limit 60% · running on power, battery idle" and the battery current stays at 0 mA (🔌).
- The first time (or after a trip), if the battery is above 60%, it shows "easing down to the limit" and goes down slowly while plugged in. At light load this takes a while (about 0.15%/min); it only happens once.
- It stays awake with the lid closed (auto work mode), and the monitor can turn off and wake normally because the adapter is never cut.
- In sailing mode (fallback) it instead blocks the adapter above 60% and runs on battery (⛵), charging again at 57%.

### Set commute and leave times

Commute charge, leave charge and weekend outing charge are all set the same way.

**In the popover (quick)**

1. Click the menu bar icon to open the popover.
2. Under **Modes** on the right, turn on **Commute charge** (or leave / weekend outing charge). The editor opens right away; if it's collapsed, click ▾ next to the name.
3. Set the time on the first row, **`Commute  − 08:00 +`**:
   - **− / +** moves it by 15 minutes.
   - Click **the time in the middle** to pick a common time: 06:30–09:30 for commute, 16:30–20:00 for leave, 08:00–14:00 for weekend.
4. On the right of the same row, **"60 min before ▾"** sets how early charging starts (30–180 minutes). On this MacBook, 60%→80% takes about 20–30 minutes and 60%→100% about an hour.
5. **Target**: pick 80 / 90 / 100%, or use the slider in 5% steps.
6. **Days**: turn on only the days you need (commute and leave default to Mon–Fri, weekend to Sat–Sun).
7. Check the summary line at the bottom for the next run, e.g. "🕓 Charge from 7:00 AM → 80% by Tue 8:00 AM".

**In the dashboard (to the minute)**

- Click **Dashboard** in the popover and type the hour and minute into the time field of **Commute charge / Leave charge / Weekend outing charge** at the bottom.
- "Start charging: N min before" changes in 15-minute steps with the arrows.

**Good to know**

- Set the time to **when you walk out the door**. It reaches the target by then and holds it for 30 more minutes, so unplug and go any time in that window.
- If the Mac stays plugged in at home overnight, set maintain charge **Apply** to **Always**. It then holds 60% overnight and tops up to 80% before your commute.
- In macOS charge limit mode the schedule simply raises the macOS limit to the target, then returns it to the maintain level. Because macOS enforces the limit, this works **even while the Mac sleeps or the app is closed** (the limit that was set last stays).
- If schedules overlap, the higher target wins. **Charge now** comes first whenever it's on.

### Before a trip (charge now)

- In the popover under **Charge now (trip)**, first choose **Leave** (Now / In 1 h / In 2 h / In 3 h), then click **80%** or **100%**.
  - **Now**: starts charging immediately and shows the time remaining.
  - **In N h**: starts late so it finishes right before you leave (e.g. "Leaving 1:00 PM · charging from 12:05 PM"). Until then it holds the maintain level. The estimate uses this Mac's real charge rate plus a 15-minute buffer.
- You can change the departure while it's active.
- It turns off on its own when you unplug after reaching the target. Click the same button again or **Cancel** to stop it right away.
- In macOS charge limit mode the app raises the limit to 80% or 100% for you. In sailing mode, also raise the macOS charge limit to 100% in System Settings; otherwise it stops at the limit.

### Weekends

- If the Mac stays plugged in at home all weekend, the commute/leave schedules (Mon–Fri) don't run and it **holds 60%**.
- If you go out at a set time on weekends, turn on **Weekend outing charge** and set its time and target. If it's the same time as your commute, you can simply add Sat/Sun to the commute schedule.
- For spontaneous outings, use **Charge now** and pick a departure (e.g. In 1 h).

### Leaving the office

1. **Unplug the external monitor cable first**, then the power adapter.
2. With the lid closed, the app detects this, stops discharging/blocking, and **sleeps within about 10 seconds**.
3. The first few times, check that it went to sleep (keyboard backlight off, etc.) before putting it in your bag.

### Manual discharge

- Pick a target (50–90%) from **Manual discharge ▾** in the popover to start.
- While it runs, **− / +** and the target buttons change the target **without restarting**; it takes effect within 10 seconds.
- **Stop**, or reaching the target, restores adapter blocking and the sleep setting.
- With maintain mode on you'll rarely need this; it's for occasionally running the battery down, e.g. to recalibrate.

### Menu bar icon

| Icon | Meaning |
|---|---|
| ⚡ `80%` | Charging |
| ⛵ `80%` | Maintain mode (sailing): adapter blocked, running on battery |
| ↓ `80%→60` | Manual discharge (target 60%) |
| 🔌 `60%` | Plugged in, not charging (e.g. held at the macOS charge limit) |
| 🔋 `80%` | On battery (no adapter) |
| `80%⏰` | Scheduled charging window (commute / leave / weekend) |
| `80%🧳` | Charge now |
| `60% 32°` / `🔥` / `🌡` | Battery temperature / 40°C or more / heat protection active |

Right-click for a short menu (discharge, modes, dashboard, quit).

### Capacity bar and SOH

```
[■■■■■■■■■■■■■■░░░░│▨▨▨▨▨]
 current charge  room │ capacity lost to wear
 └──── current max capacity ────┘
 └────────── design capacity (new battery) ──────────┘
```

- **SOH (State of Health)** = current max capacity ÷ design capacity, the same basis as macOS "Maximum Capacity".
- Below 80%, macOS may show "Service Recommended". This app slows aging; it can't bring lost capacity back.

## Cautions

**Safety**
- This tool writes to the SMC (System Management Controller). **Use it at your own risk.**
- During manual discharge, or while plugged in with auto work mode, the Mac **does not sleep when you close the lid**. Always unplug and check that it went to sleep before putting it in a bag; otherwise it can get hot.
- High temperature (35°C+, especially 40°C+) is bad for the battery whether charging or discharging. Running on battery under heavy load heats the battery itself; macOS charge limit mode avoids that because the battery current is 0 while holding.
- macOS charge limit mode writes PowerUIAgent's own preferences (`com.apple.smartcharging.topoffprotection`) with values below the 80% that System Settings allows. This is **undocumented**; a future macOS update may change or block it, in which case the app falls back to sailing.

**Other apps**
- **Don't run** AlDente, other charge-limit apps, or `battery maintain` at the same time. They change the same SMC keys and get in each other's way.
- **In macOS charge limit mode, the app manages the macOS charge limit.** Don't change it in System Settings at the same time (System Settings may show an odd value such as 60%; that's expected). When the app has no target (maintain off, no schedule) it restores the limit it found first (usually 80%).
- **In sailing mode, setting the macOS charge limit to 80% is recommended** (System Settings → Battery → ⓘ next to Charging), so the battery stays at or below 80% even while the Mac sleeps or the app isn't running. A schedule target above the limit stops at the limit.
- On older macOS without a charge limit, turning off "Optimized Battery Charging" is recommended, since it can overlap (e.g. pausing at 80%).

**Behaviors to know**
- The items below apply to **sailing mode** (adapter blocking).
- Sailing doesn't "only stop charging"; it **cuts adapter input**. While blocked, the whole Mac runs on battery, so heavy work drains it faster. Shallow cycling between 57% and 60% puts very little stress on the battery.
- **Adapter blocking is always released right before sleep and when the app quits.** While asleep or with the app off, macOS charges normally and may go above the maintain level; once the app runs again it comes back down.
- When the displays turn off in clamshell mode: **with Input Monitoring allowed**, the adapter stays blocked and the battery holds near 60%; keyboard or mouse input switches to AC and turns the display on. **Without it**, the app switches to AC right away to guarantee waking, so while you're away it charges up to the macOS limit (e.g. 80%) and then drains back to 60%. Allow the permission to avoid that round trip.
- With auto work mode on and power connected, **system sleep is blocked even with the lid open**. The display still turns off as usual.
- Bluetooth wake only works while the system is awake (auto work mode). If the Mac is fully asleep, wake it with USB input or by opening the lid.
- **Update or restart the app with the lid open** to be safe. On quit the app releases adapter blocking and waits for AC power before restoring sleep, but if the Mac ends up on battery with the lid closed, macOS sleeps immediately and an external keyboard or mouse can't wake it.
- Whether an adapter is connected is decided from the USB-C power contract (PD). The contract stays while the adapter is blocked and disappears as soon as you unplug.
- macOS updates battery info a few seconds late, so right after blocking or unblocking the adapter, the badge (charging / discharging) may be briefly out of sync.
- Other apps (e.g. Stats) use different bases for battery health, so their value may differ slightly from this app's SOH.

**If something goes wrong**
- If the app quit unexpectedly and the adapter stays blocked, or the Mac won't sleep with the lid closed, restore with:
  ```bash
  /Applications/ClamshellDischarge.app/Contents/Resources/clamshell-discharge --restore
  sudo pmset -a disablesleep 0
  ```
- To put the macOS charge limit back to 80% (or 100% = off) by hand:
  ```bash
  sudo /usr/local/libexec/clamshell-charge-limit 80
  pmset -g battlimit   # check
  ```
- On models without MagSafe, the log may show `SMCWriteKey ... e00002bc`. It's about the LED and can be ignored.
- SMC keys can differ between models. If it doesn't work, open an [issue](../../issues) with your model and macOS version.

**Privacy**
- Data stays on this Mac: usage history in `~/Library/Application Support/ClamshellDischarge/history.csv`, the daily log in `daily.csv` next to it, and the discharge log in `~/.battery/clamshell-discharge.log`. The only copy that leaves the Mac is the optional daily log in **your own** iCloud Drive (no serial number; the device ID is a hash). No server is involved.
- Input Monitoring only checks **whether** input happened while the displays are off; it never reads key contents.

## CLI

You can also run the script bundled in the app from Terminal.

```bash
/Applications/ClamshellDischarge.app/Contents/Resources/clamshell-discharge 80         # discharge to 80%
echo 70 > ~/.battery/clamshell-discharge.target                                         # change the target while running
/Applications/ClamshellDischarge.app/Contents/Resources/clamshell-discharge --restore  # emergency restore
```

## Build

Requires `swiftc` from Xcode (or the Command Line Tools).

```bash
./build.sh            # build/ClamshellDischarge.app + zip
./build.sh --install  # + install to /Applications
```

If your keychain has an **Apple Development** or **Developer ID Application** certificate, `--install` re-signs the installed copy with it. To use a different one: `SIGN_ID="certificate name" ./build.sh --install`. Without a certificate it stays ad-hoc signed, and you'll need to allow Input Monitoring again after every rebuild. Release zips are always ad-hoc signed so no personal information (certificate name) is included.

- Translations: the table in `Sources/L10n.swift` (the Korean source text is the key). `python3 tools/wrap_strings.py --apply Sources/<file>.swift` wraps new Korean strings as translation keys; `--list` lists keys.
- App icon: `icon/MakeIcon.swift`

## Uninstall

```bash
sudo /usr/local/libexec/clamshell-charge-limit 80   # put the macOS charge limit back first (or 100 = off)
sudo rm /etc/sudoers.d/clamshell-discharge /etc/sudoers.d/clamshell-charge-limit /usr/local/libexec/clamshell-charge-limit
rm -rf /Applications/ClamshellDischarge.app ~/.battery/clamshell-discharge.*
sudo pmset -a disablesleep 0
```

Also remove ClamshellDischarge from **System Settings → Privacy & Security → Input Monitoring** and **General → Login Items**. To remove the battery CLI too, follow the instructions in the [battery repository](https://github.com/actuallymentor/battery).

## Support

If this app helps keep your battery healthy, you can buy me a coffee. ☕

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/waps99)

In Korea you can also send via Toss: scan this QR with your phone camera or the Toss app.

<img src="docs/donate/toss-qr.png" width="180" alt="Toss transfer QR">

You can also open Ko-fi from ⚙︎ → **Support on Ko-fi** in the app. Support is optional; every feature is free.

## License

MIT
