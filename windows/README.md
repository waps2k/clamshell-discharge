# Clamshell Discharge for Windows (preview)

**English** | [한국어](README.ko.md)

A Windows 10/11 tray app with the same layout as the macOS version. It's a **single executable**; at launch it detects the laptop manufacturer and picks the matching charge-control method.

> **This is a preview.** Charge control currently supports **Lenovo only** and is still being verified on real hardware. On other brands you get battery monitoring (dashboard, SOH, history) and the lid-close behavior only.

## Support status

| Manufacturer | Method | Maintain level | Status |
|---|---|---|---|
| **Lenovo ThinkPad** | Charge start/stop thresholds (Lenovo PM driver `IBMPmDrv` + `PWRMGRV` registry) | Any level from 60 to 99% | Implemented, needs verification |
| **Lenovo IdeaPad / Yoga / Legion** | Conservation mode (Energy Management driver `EnergyDrv`) | Fixed by firmware (roughly 60% or 80%) | Implemented, needs verification |
| ASUS · Dell · HP · Samsung · LG | — | — | Planned |

Required drivers:
- ThinkPad: **Lenovo Power Management Driver** (installed with Lenovo Vantage or System Update)
- IdeaPad/Yoga/Legion: **Lenovo Energy Management** driver

## Features (same as macOS)

- Maintain charge (limit-based), and **commute**, **leave** and **weekend outing** charge schedules
- **Charge now (trip)** to 80% / 100%, starting late to finish by your departure (Now / In 1·2·3 h)
- Dashboard (charge chart, daily SOH), usage history, capacity bar, multiple languages

## Differences from macOS

- **"Hold 60%" works as a charge limit.** Most Windows laptops can't run on battery while plugged in (active discharge). Instead, while plugged in, charging stops at the chosen level and the laptop runs on AC. If the battery is already above it, wait until you use it down, or unplug for a while.
- **Lid-close behavior uses the Windows power plan** (`powercfg` LIDACTION). Turning on **Stay awake with lid closed (on power)** sets "on power: do nothing / on battery: sleep", and turning it off restores the original values. Waking with a USB or Bluetooth keyboard is built into Windows, so nothing extra is needed.
- Capacity is shown in **mWh**, as Windows reports it.
- Administrator rights are required, so a UAC prompt appears on launch. The app changes charge limits (HKLM registry, Lenovo drivers) and power settings.
- **Open at login** creates a Task Scheduler task that runs "with highest privileges", so you don't get a UAC prompt every time.
- **Quitting the app removes the charge limit** (normal charging) and restores the lid settings.

## Install and run

1. Download `ClamshellDischarge-Windows.zip` from a `win-v…` preview in [Releases](../../../releases) and unzip it.
2. Run `ClamshellDischarge.exe`. It's unsigned, so if **SmartScreen** blocks it, click **More info → Run anyway**. Then click **Yes** in the UAC prompt.
3. A battery-number icon appears in the tray at the bottom right of the taskbar. **Left-click** opens the main screen, **right-click** opens the menu. If you don't see it, check **^** (hidden icons).

## Testing on Lenovo

1. In the main screen, check what **Battery → Charge control** shows: "ThinkPad charge thresholds" / "Conservation mode (~80%, fixed)" / "Not supported (monitoring only)".
2. Turn on **Maintain charge**. On a ThinkPad, set the level below the current charge (e.g. 80% if you're at 85%).
3. After about a minute, check that the status badge changes to **Charging paused · Limit 80%** and that the Windows battery icon also shows it isn't charging.
4. Open Lenovo Vantage and check that the charge threshold or conservation mode changed to the same value.
5. If something is wrong, click **Copy diagnostics** at the bottom of the main screen and paste it into an [issue](../../../issues). The diagnostics include the model, the detected method, driver status, and battery values.

## Build

Requires the .NET 10 SDK. Thanks to `EnableWindowsTargeting`, it also compiles on macOS or Linux (it only runs on Windows).

```bash
cd windows
dotnet publish -c Release -o publish     # publish/ClamshellDischarge.exe (single file)
```

- The translation table is generated from the macOS `Sources/L10n.swift`: `python3 tools/gen_l10n_cs.py`. Windows-only strings are in the `Extra` table in `windows/L10n.cs`.
- GitHub Actions (`.github/workflows/windows.yml`) builds on Windows and runs a basic `--selftest`. Pushing a `win-v*` tag creates a preview release.

## Support

You can support the project on [Ko-fi](https://ko-fi.com/waps99). The **☕ Support on Ko-fi** button at the bottom of the app opens it too.

## Credits

- ThinkPad threshold protocol: [wesmar/lbm](https://github.com/wesmar/lbm) (MIT), "Implementation" section of its README
- Conservation mode protocol: [dara-oladapo/power-helper](https://github.com/dara-oladapo/power-helper) (MIT)

## Cautions

- This uses private interfaces of the manufacturer's drivers. **Use it at your own risk.** It may not work on some models or driver versions.
- Lenovo Vantage may overwrite the same settings. Change them in only one place.
