# MacPulse — Ultra-Lightweight macOS Power & Wi-Fi Usage Tracker

**MacPulse** is a native, offline-first macOS menu bar utility built for Apple Silicon Macs (specifically optimized for MacBook Air M4, 16 GB RAM). It provides high-accuracy system power monitoring, 64-bit Wi-Fi traffic tracking, persistent session management, and historical analytics with zero third-party dependencies, zero cloud telemetry, and an ultra-lean memory footprint (< 12 MB).

---

## Quick Install (Terminal)

Install or update **MacPulse** directly from your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/akshay1117/tracker/main/install.sh | bash
```

> **Note for Private Repositories**: If the repository is set to private, pass your GitHub token:
> ```bash
> curl -fsSL -H "Authorization: token YOUR_GITHUB_TOKEN" https://raw.githubusercontent.com/akshay1117/tracker/main/install.sh | GITHUB_TOKEN=YOUR_GITHUB_TOKEN bash
> ```
> *Once the repository is set to Public on GitHub, the standard one-liner works anywhere without any token.*

### What the installer does:
1. Automatically detects your macOS architecture (Apple Silicon `arm64` / Intel `x86_64`).
2. Fetches the latest pre-compiled `MacPulse.zip` from GitHub Releases.
3. Falls back to compiling locally via Swift Command Line Tools if release assets are unavailable.
4. Installs cleanly to `/Applications/MacPulse.app` (or `~/Applications/` if non-admin).
5. Clears macOS Gatekeeper quarantine (`xattr -dr com.apple.quarantine`) so the app opens immediately without security prompts.
6. Launches MacPulse in the menu bar.

---

## 1. Core Capabilities

1. **Per-Application Tracking**: Real-time per-application accounting for:
   - **Screen-On Time**: Precision foreground active duration tracking via `NSWorkspace.shared.frontmostApplication` while awake.
   - **Energy Consumption (Wh & Energy Impact)**: Darwin `proc_pidinfo` microsecond CPU sampling + child helper process aggregation (renderers, audio, network workers) combined with Apple Silicon hardware PMU wattage allocation.
   - **Network Data Usage (In / Out)**: Asynchronous 64-bit per-process bandwidth & byte accounting via kernel `/usr/bin/nettop`.
2. **Dedicated App Usage Dashboard**: Filter by "Current Session" vs "All Sessions", sort by Screen Time, Energy, Total Data, Download, Upload, or Name, with search and native high-resolution app icons.
3. **System Power Draw**: Real-time wattage measured directly from the Apple Silicon hardware PMU (`AppleSmartBattery.PowerTelemetryData.SystemLoad`), with graceful fallback to battery gas gauge telemetry when operating on battery.
4. **Energy Consumption**: Trapezoidally integrated energy in Watt-hours (Wh) and kilowatt-hours (kWh) for both the active session and cumulative lifetime.
5. **Session Energy Tracking**: Distinct energy accounting for each session, cleanly separated from lifetime totals.
6. **Instantaneous Wi-Fi Throughput**: Live download and upload speeds computed from kernel counter deltas over monotonic time intervals.
7. **Wi-Fi Data Accounting**: True 64-bit hardware counters for received, transmitted, and combined data without 32-bit (4 GB) rollover truncation.
8. **Session Wi-Fi Accounting**: Granular tracking of Wi-Fi usage for each active session.
9. **Boot Uptime**: Monotonic uptime since system boot (`kern.boottime` / `ProcessInfo.systemUptime`), clearly designated as including sleep.
10. **Cumulative Tracked Awake Uptime**: Total awake time spent in tracked active sessions across reboots, strictly excluding sleep intervals.
11. **Precise Session Lifecycle**: Sessions trigger on lid-open and finalize on lid-close (or sleep, depending on configured policy).
12. **Historical Analytics & Swift Charts**: Daily and weekly summaries with interactive Swift Charts, detailed session inspector with per-app breakdowns, and full CSV/JSON export.

---

## 2. Measured Resource Usage (MacBook Air M4)

Measured on macOS 26 / arm64 using `vmmap` and `ps`:

| Metric | Target Budget | **Actual Measured Result** |
| :--- | :--- | :--- |
| **Idle Memory (Footprint)** | < 30 MB | **11.7 MB** (Peak: 12.3 MB) |
| **Idle CPU Usage** | Negligible | **0.0%** (Popover closed) |
| **Awake Sampling Interval** | ~5.0 s | **5.0 s** (1.5 s when popover open) |
| **Sleep CPU Usage** | Zero | **0.0%** (Timers paused via `NSWorkspace`) |
| **Disk Activity** | Minimal | **30s WAL checkpoints**, immediate on session transitions |
| **Privileges Required** | None | **Zero root, Zero helper, Zero SIP bypass** |

---

## 3. Architecture & Technical Implementation

```
Sources/MacPulse/
├── App/
│   ├── MacPulse.swift            # NSApplication entry point, accessory policy (LSUIElement)
│   ├── AppState.swift            # Observable model coordinating timers, menu bar, and views
│   └── StatusBarController.swift # NSStatusItem & NSPopover presentation controller
├── Core/
│   ├── AppUsageModel.swift       # AppUsageRecord model and sorting options
│   ├── EnergyIntegrator.swift    # Trapezoidal rule integrator with bounds & sanity checks
│   ├── MeasurementQuality.swift  # Telemetry sources, quality, and confidence classifications
│   ├── MonotonicClock.swift      # Monotonic time provider protocol and mock clocks
│   ├── NetworkAccumulator.swift  # 64-bit network counter accumulator and rollover protection
│   ├── NetworkSnapshot.swift     # Immutable network model and formatting utilities
│   ├── PowerSnapshot.swift       # Immutable power model with confidence flags
│   └── SessionModel.swift        # UsageSession, BootRecord, and AggregateStats models
├── Hardware/
│   ├── AppUsageMonitor.swift     # Native Darwin proc_pidinfo, child PID traversal, and nettop sampler
│   ├── ClamshellMonitor.swift    # IOPMrootDomain AppleClamshellState reader
│   ├── NetworkMonitor.swift      # Dynamic IEEE80211 interface detection & sysctl NET_RT_IFLIST2
│   ├── PowerMonitor.swift        # Apple Silicon PMU & AppleSmartBattery reader
│   └── UptimeProvider.swift      # Kernel sysctl kern.boottime & kern.bootsessionuuid
├── Persistence/
│   ├── DatabaseManager.swift     # Thread-safe SQLite database with WAL mode, migrations (v2), & app tables
│   └── DataExporter.swift        # CSV and JSON export generators including per-app usage
├── Lifecycle/
│   ├── SessionManager.swift      # Persisted state machine coordinating app tracking
│   └── SessionPolicy.swift       # Configurable session boundary policies
└── UI/
    ├── AppUsageView.swift        # Dedicated dashboard with scope, sort, search, and app cards
    ├── DesignSystem.swift        # Restrained dark macOS tokens and MetricCard container
    ├── OverviewView.swift        # Live dashboard with Top Apps summary
    ├── HistoryView.swift         # Swift Charts 7-day activity & session inspector with app breakdown
    ├── SettingsView.swift        # Display modes, launch at login, policy, export, reset
    └── PopoverView.swift         # Segmented container for Overview, Apps, History, and Settings
```

### Telemetry Sources & Meaning
- **Apple Silicon Hardware PMU (`AppleSiliconPMU`)**: Reads `AppleSmartBattery` -> `PowerTelemetryData.SystemLoad` in milliwatts. This is the direct instantaneous power consumption measured by Apple's on-chip power management unit.
- **Battery Gas Gauge (`BatteryGasGauge`)**: When unplugged and PMU load is unavailable, power is derived from instantaneous voltage and discharge amperage (`V * A`). Labeled clearly as battery discharge draw.
- **Charger Distinction**: Input charger rating (e.g. 35W) is never confused with Mac system consumption.

### Network Monitoring Correctness
- **Dynamic Interface Detection**: Detects the active physical Wi-Fi interface via `SCNetworkInterfaceCopyAll()` (`kSCNetworkInterfaceTypeIEEE80211`) and CoreWLAN without hardcoding `en0`.
- **64-bit Hardware Counters**: Queries `NET_RT_IFLIST2` (`if_msghdr2` -> `ifi_ibytes`, `ifi_obytes`) to prevent 32-bit counter rollover after 4 GB of traffic.
- **VPN Double-Counting Prevention**: Counts bytes strictly on the physical Wi-Fi link. Virtual tunnels (`utun*`), bridges, and loopback are excluded.
- **Counter Reset Protection**: If an interface resets or machine reboots, counter baselines are re-established without recording false negative or massive spikes.

### Session & Boot Lifecycle
- **Definition of a Session**: Begins when the lid opens; ends when the lid closes (`AppleClamshellState == true`), even if an external display keeps the Mac awake in clamshell mode.
- **Boot Isolation**: Every reboot creates a new boot record (`kern.bootsessionuuid`), preserving all lifetime aggregates and session histories.
- **Crash Recovery**: Checkpoints session progress every 20 seconds. An interrupted session is reconciled on next launch, marked as `CrashRecovered`, and incorporated into aggregate stats without duplicating counts.

---

## 4. Build and Installation

### Prerequisites
- macOS 14.0 or later (Tested on macOS 26.6 / Apple Silicon M4)
- Swift 6.0+ (Command Line Tools or Xcode)

### Building the Application Bundle
Run the reproducible build script from the repository root:
```bash
./build.sh
```

This compiles `MacPulse` in Release mode, creates `MacPulse.app`, embeds `Info.plist` (with `LSUIElement = true` for menu bar-only operation), embeds `AppIcon.icns`, and signs the bundle ad-hoc.

### Installing and Running
```bash
# Move to Applications folder
cp -R MacPulse.app /Applications/

# Launch MacPulse
open /Applications/MacPulse.app
```

---

## 5. Running Automated Tests

MacPulse includes a comprehensive automated test suite with deterministic mocks and hardware integration checks:
```bash
export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
swift test
```

### Test Coverage Highlights (38 Tests, 8 Suites)
- **`MenuBarRecoveryTests`**: Status bar controller idempotent recreation, KVO-driven recovery, visibility toggling, database and aggregate state preservation during restoration.
- **`EnergyIntegratorTests`**: Trapezoidal rule integration, linear power ramps, sleep gap rejection (> 30s), negative interval rejection, implausible wattage rejection.
- **`NetworkAccumulatorTests`**: Monotonic speed calculation, counter reset protection, interface switching, disconnected state handling.
- **`DynamicUnitConversionTests`**: MB to GB (1,000 MB threshold), Wh to kWh (1,000 Wh threshold), KB/s to MB/s threshold, display unit decoupling.
- **`AppUsageTests`**: App usage record models, multi-session lifetime aggregation, sorting, query limits, reset tables.
- **`DatabaseTests`**: Schema creation, migrations, session lifecycle persistence, atomic aggregate updates, crash recovery, CSV/JSON export, history wipe.
- **`SessionLifecycleTests`**: Initial lid state, lid close finalization, lid reopen new session, duplicate sleep/wake notification idempotency, ClamshellOnly pause/resume, SleepOrClamshell policy.
- **`HardwareIntegrationChecks`**: Live sysctl uptime, live clamshell monitor, live power monitor, live 64-bit Wi-Fi sampler.

---

## 6. Launch at Login

To configure MacPulse to start automatically on login:
1. Open the MacPulse popover from the menu bar.
2. Select the **Settings** tab.
3. Toggle **Launch at Login** on.
   *(MacPulse utilizes macOS's modern `SMAppService.mainApp` API—no privileged helpers, daemon scripts, or root required).*

---

## 7. Uninstallation & Data Removal

To cleanly remove MacPulse and all its persisted local data:
```bash
# 1. Quit the application
killall MacPulse 2>/dev/null || true

# 2. Remove the application bundle
rm -rf /Applications/MacPulse.app

# 3. Remove local SQLite database and preferences
rm -rf ~/Library/Application\ Support/MacPulse
defaults delete com.macpulse.app 2>/dev/null || true
```

---

## 8. Known Limitations & Technical Disclosures

1. **Network Header Overhead**: Kernel interface counters (`NET_RT_IFLIST2`) measure physical link layer traffic, which includes packet headers, retransmissions, and protocol overhead. Recorded bytes may differ slightly from application-layer payload measurements or ISP billing meters.
2. **Desktop Macs (Mac mini / Mac Studio)**: Hardware clamshell state (`AppleClamshellState`) is specific to MacBook portables. On desktop hardware without a lid sensor, MacPulse falls back to system sleep/wake boundaries.
3. **Charger Efficiency**: When connected to AC power, the power draw measured by the Apple Silicon PMU represents total system motherboard load, not wall socket draw (which includes adapter conversion losses).
