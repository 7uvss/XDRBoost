XDRBoost is provided under GNU GPL version 3; see LICENSE.

The original versions used an EDR multiply-overlay technique adapted from
BrightXDR, Copyright (c) 2023 Dmitry Starkov, licensed under GNU GPL v3.
https://github.com/starkdmi/BrightXDR

Version 1.1.0 replaces the full-screen multiply overlay with a tiny EDR trigger
and per-display gamma-table adjustment. This technique, the 256-entry gamma
table implementation, and the XDR reference values (3.2 EDR / 0.59 bonus gamma)
are informed by/adapted from BrightIntosh, Copyright Niklas Rousset and
contributors, licensed under GNU GPL v3.
https://github.com/niklasr22/BrightIntosh

This application adds its own compact AppKit controls, dynamic target range,
baseline capture/restore, pipe-based crash recovery helper, conflict handling,
thermal/sleep/topology handling, diagnostic tests and application packaging.
Complete corresponding source and build script are included in this directory.
No warranty is provided.

Version 1.1.1 adds continuous gain mapping, retained user targets, idempotent
lifecycle handling, ownership-aware gamma restoration, a nonblocking recovery
protocol with readiness/health checks, bounded rendering recovery, and regression
diagnostics.
