# Contributing

Use English for repository documentation, issue reports, pull requests, commit messages, and code comments. The application's existing Simplified Chinese interface is maintained separately from repository language.

## Local development

1. Install Apple Command Line Tools.
2. Edit the Swift files in `Source/`.
3. Run `./build.sh`.
4. Quit the previous application instance and run the new build.

The app uses native AppKit with no Swift packages or third-party runtime dependencies. Build outputs are excluded from Git.

## Checks

```sh
./build.sh
plutil -lint Info.plist
codesign --verify --strict XDRBoost.app
```

For changes involving gamma, recovery, or window behavior, run `--self-test` on supported display hardware. Quit the normal application first: the suite briefly changes display brightness. A successful build does not establish hardware-boost or gesture compatibility.

Describe the triggering problem, the resulting behavior, and the validation actually performed in each fix. Distinguish simulated notifications from real sleep or temperature testing.

## Manual regression coverage

- Enable and disable the boost, drag the slider, and verify restoration after quitting.
- Open Mission Control, switch applications, enter full screen, and switch Spaces.
- Test real sleep/wake, lid closure, and external-display configuration changes.
- Change display presets or use another gamma-adjustment app while the boost is active.

## Reporting issues

Include the application version, macOS version, Mac model, and reproducible steps. Remove device serial numbers, credentials, and other private information from logs or screenshots.

## Versions and licensing

When publishing a release, update the version and build number in `Info.plist` together with `CHANGELOG.md`. Update `THIRD_PARTY_NOTICES.md` when adding adapted code, and preserve GPLv3 licensing obligations.
