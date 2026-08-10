# Troubleshooting

Most of the confusion around a `.saver` bundle on modern macOS comes from
caching, not from the saver. These are the cases worth knowing.

Installing for the first time? [INSTALL.md](INSTALL.md) walks through the
dialogs macOS shows on the way, with screenshots.

## macOS says it could not verify Gibson

Releases are notarised and will not do this. A saver you built yourself is
signed ad hoc, and so was the 1.0.0 release, so Gatekeeper asks you to confirm
it once. In the warning press **Done**, never **Move to Trash**, then open
**Privacy & Security** and press **Open Anyway** next to the line about Gibson.
The last section of [INSTALL.md](INSTALL.md) shows both dialogs. Clearing the
quarantine flag before installing skips them:

```bash
xattr -dr com.apple.quarantine ~/Downloads/Gibson.saver
```

## Gibson does not appear in the picker

Third party screen savers live at the bottom of the list, in the **Other**
section, after all of Apple's own. If it is not there:

1. Quit System Settings with Cmd+Q rather than closing the window. The list of
   legacy savers is read once at launch.
2. Confirm the bundle is where macOS looks:

   ```bash
   ls ~/Library/Screen\ Savers/
   ```

## The tile or the saver is an old build

macOS caches the picker tile in a location keyed by the bundle path, and it does
not notice that the file behind that path changed. Reinstalling on its own will
not clear it. This clears everything:

```bash
osascript -e 'tell application "System Settings" to quit'
killall WallpaperLegacyExtension legacyScreenSaver 2>/dev/null
pkill -f 'com.apple.wallpaper.agent' 2>/dev/null
rm -rf "$(getconf DARWIN_USER_CACHE_DIR)com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails"
rm -rf "$(getconf DARWIN_USER_CACHE_DIR)com.apple.wallpaper.agent/com.apple.wallpaper.view-model-cache"
rm -rf ~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/screenSaver-/Users
```

`WallpaperLegacyExtension` and `legacyScreenSaver` are separate processes that
survive quitting System Settings and keep the previously loaded bundle in
memory, which is why killing them is part of the sequence.

To check what the system will actually draw, without opening the UI, ask the
private `ScreenSaverModule` API for the thumbnail it serves and compare it with
the file in the bundle.

## Clicking Options does nothing

Usually a stale connection: something killed `WallpaperLegacyExtension` while
System Settings was open, and Settings is still talking to a process that is
gone. Quit System Settings with Cmd+Q and reopen it.

## `make preview` exits immediately

`ScreenSaverEngine` runs hardened without a library validation exemption, so it
is killed with `Code Signature Invalid` the moment it loads an ad hoc signed
bundle. You will find the crash report under
`~/Library/Logs/DiagnosticReports/ScreenSaverEngine-*.ips`.

This affects that one launch path only. At idle, and in the System Settings
preview, macOS loads the saver through `legacyScreenSaver.appex`, which carries
`com.apple.security.cs.disable-library-validation`, so an ad hoc build runs there
without trouble. Use `make demo` to iterate, or set `SIGN_ID` to a Developer ID
certificate if you need the engine path.

## The clock and the menu bar sit over the saver

That is the lock screen, drawn above the saver by the system. A screen saver
plug-in has no API to suppress it, and the `com.apple.screensaver showClock`
default that used to hide it was retired in Sonoma.

What does help: System Settings, Lock Screen, **Require password after screen
saver begins or display is turned off**. Until that delay elapses the saver runs
on its own.

## Preferences look empty from a terminal

```
$ defaults read com.perfecto-web.Gibson
Domain com.perfecto-web.Gibson does not exist
```

Expected. The saver is sandboxed, so its preferences land in the host container:

```bash
plutil -p ~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost/com.perfecto-web.Gibson.*.plist
```

## A panel is blank or shows placeholder values

Live sampling may have been denied by the sandbox, or **Read live system
metrics** is off in Options. Both paths fall back to synthesised values on
purpose rather than showing an empty panel. `make demo` runs unsandboxed and is
the quickest way to tell the two apart.
