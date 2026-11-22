# Changelog

## 1.1.1

- Fix a discontinuous gamma increase when EDR headroom is close to 1.
- Separate the user's requested target from currently available gain, retaining the selection when headroom drops.
- Coalesce wake notifications and reuse the trigger window when lifecycle state is unchanged.
- Stop boosting when an external gamma change is detected and preserve the new settings.
- Add a readiness handshake, nonblocking communication, and health checks for the recovery process.
- Retire the recovery process directly during normal shutdown, avoiding unbounded main-thread waits and suspended child processes.
- Count only successful GPU frames; attempt one rebuild after a stall, then disable the boost if rendering fails again.
- Add a 15-check local regression suite.

## 1.1.0

- Replace the full-screen white multiply overlay with a tiny EDR trigger and gamma-table adjustment.
- Add baseline capture, crash recovery, color-conflict checks, and local diagnostics.

## 1.0.x

- Introduce a native menu bar app with a dynamic EDR slider.
- Move slider controls into a popover and simplify the interface.
