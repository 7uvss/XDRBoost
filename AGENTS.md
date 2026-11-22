# Repository maintenance

- Use English for documentation, issues, pull requests, commit messages, and code comments.
- Keep existing application UI localization unless a task explicitly requests a UI language change.
- Preserve GPLv3 licensing and third-party attribution.
- Build with `./build.sh`; validate `Info.plist` and the application signature for code changes.
- Do not run `--self-test` while the normal app is running. Hardware diagnostics briefly change display brightness.
- Do not run hardware gamma diagnostics on CI. CI validates compilation, configuration, and signing only.
- Distinguish simulated notifications from real sleep, thermal, and gesture validation.
- Do not commit compiled applications, archives, local device reports, credentials, or personal paths.
