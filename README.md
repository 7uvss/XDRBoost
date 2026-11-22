# XDRBoost

A compact macOS menu bar app that enables additional brightness on supported built-in XDR displays.

Current version: **1.1.1**. Built with native Swift, AppKit, Metal, and Core Graphics, with no third-party runtime dependencies.

## Features

- A menu bar sun icon with a boost toggle, target slider, current EDR limit, and quit button.
- A tiny corner EDR trigger and gamma-table adjustment, without a full-screen white multiply overlay.
- A target range that follows available EDR headroom while retaining the user's selection during temporary limits.
- Pause handling for sleep, session changes, and high temperatures, with duplicate wake notifications coalesced.
- External gamma-change detection that stops the boost and preserves the new settings.
- A separate recovery process that restores gamma settings still owned by the app after an unexpected exit.
- Recovery-process and GPU health checks, with one rendering-recovery attempt before disabling the boost.

## Requirements

- An Apple Silicon Mac running macOS 13 or later.
- A supported built-in EDR display using an XDR-capable display preset.
- Apple Command Line Tools to build; a full Xcode installation is not required.

Verified on a **16-inch MacBook Pro (2021, M1 Pro, Liquid Retina XDR), running macOS 27.2.1**. Other models and system versions have not been verified. External displays are outside the current scope.

## Build and run

```sh
git clone https://github.com/7uvss/XDRBoost.git
cd XDRBoost
xcode-select --install # Skip this if Command Line Tools are already installed.
./build.sh
open XDRBoost.app
```

The build script creates `XDRBoost.app` and applies an ad hoc local signature. The app is not notarized by Apple. This repository does not include prebuilt applications.

Click the menu bar sun icon and enable extra brightness. Allow the system a few seconds to establish EDR headroom, then adjust the target slider. Start at 1.25×. Disabling the boost or quitting restores settings still owned by the app. Boost is off on every launch. The application interface currently uses Simplified Chinese.

## Brightness scale and limitations

The slider is a **target boost scale**, not a measurement of nits or physical brightness multiplication. Reported EDR headroom, gamma scaling, and actual display brightness are different quantities. At the reference EDR headroom of 3.2×, the maximum setting uses approximately a 1.59 gamma scale.

Results depend on system brightness, the display preset, temperature, and color management. Higher brightness increases power use, and gamma adjustment changes color reproduction. Disable the boost for calibration or other color-critical work. The corner trigger is tiny but may remain visible in some screenshots or display configurations.

Extended gamma behavior depends on macOS and the display implementation and should be reverified after system upgrades. The app requires no screen-recording, Accessibility, or administrator permissions and contains no networking code.

## Validation

Read the model and EDR capabilities without enabling the boost:

```sh
./XDRBoost.app/Contents/MacOS/XDRBoost --probe
```

Quit the normally running application before running the hardware regression suite:

```sh
./XDRBoost.app/Contents/MacOS/XDRBoost --self-test
```

The suite takes about 12 seconds, briefly changes display brightness, and reverses its simulated gamma changes when finished. Its 15 checks cover curve continuity, slider actions and gamma readback, duplicate notifications, rendering recovery, color conflicts, and recovery-process failures. A successful run prints `REGRESSION_SUITE PASS checks=15` and exits with status 0.

GitHub Actions validates compilation, application configuration, and the local signature. It does not run brightness tests requiring a real XDR display. Automated checks do not replace visual testing of trackpad gestures, rapid app switching, sleep/wake transitions, or color reproduction.

## Project layout

```text
Source/main.swift         Menu bar interface and lifecycle management
Source/GammaBoost.swift   Gamma adjustment, EDR trigger, and recovery process
Source/Diagnostics.swift  Local hardware regression suite
Info.plist                Application configuration
build.sh                  Apple Silicon build script
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and issue-reporting guidance, and [CHANGELOG.md](CHANGELOG.md) for version history. Repository documentation, issues, pull requests, and commit messages are maintained in English.

## License and acknowledgments

Licensed under [GNU GPL v3](LICENSE). EDR and gamma techniques are informed by and adapted from [BrightXDR](https://github.com/starkdmi/BrightXDR) and [BrightIntosh](https://github.com/niklasr22/BrightIntosh). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the full notices.
