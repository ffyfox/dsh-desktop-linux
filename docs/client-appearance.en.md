# Client appearance

[中文](client-appearance.md) | **English**

Independent window and sidebar settings are provided by patch `0020`. Use a build containing this patch; older release downloads do not imply support. See [README](../README.en.md#building-from-source) for the build entry point.

![Independent client appearance settings window](client-settings.png)

## Adjust and save

Choose “Client settings…” from the tray to choose macOS (left-side traffic lights), Windows (the upstream separate 40 px caption, sidebar toggle, and Application/Edit menus), or Blended (right-side window controls, with the logo and sidebar toggle on one row), and adjust corners, system shadows, sidebar glass, and transparency. “Advanced” includes the frameless main window and Wayland background blur. The settings window always retains its native frame and opaque background and requests the default system shadow, independently of main-window preferences; closing it closes only that window.

The defaults require no legacy environment variables: macOS title-bar controls, frameless enabled, 12 px corners, system shadow enabled, sidebar glass enabled, 20% transparency (80% fill opacity), and Wayland blur enabled. Frameless and glass modes can run together; they are not exclusive.

![macOS, Windows, and Blended title-bar styles](titlebar-styles.png)

Windows reuses the upstream caption, menus, and content layout instead of only moving window buttons to the right. A caption-colour backing under the inner content corner prevents the desktop showing through as a bright notch, while retaining sidebar glass and transparent exterior corners. A real dark-theme capture:

![Upstream-style Windows caption in dark theme](windows-upstream-style.png)

Real before/after captures use the same backing to show the transparent notch:

![Windows inner corner before and after the fix](windows-corner-comparison.png)

“Restore defaults” fills the form without writing until you save. “Save” affects the next launch only and leaves the current window and Host tasks running. The page distinguishes current-run and next-launch values. A failed save keeps the form for correction or retry and is not reported as saved.

“Save and restart…” saves first, then opens a native confirmation. Cancel is the default. The dialog warns that running Host tasks will be interrupted and scheduled tasks cannot run during restart; only a second confirmation requests restart. Cancelling does not undo the saved preferences, which still apply at the next launch.

## Configuration file and compatible initial values

Configuration is stored separately at `app.getPath('userData')/desktop/appearance.json`, not in `$DSH_HOME`, and does not change Host configuration. Reading settings does not create a file. Saving atomically replaces the file with mode 0600 and preserves the previous file on write failure. Unknown fields, invalid JSON, invalid field types or ranges, and unsupported versions produce explicit errors without silent fallback or replacement.

A complete version-3 file:

```json
{
  "schemaVersion": 3,
  "frameless": true,
  "titlebarStyle": "macos",
  "cornerRadius": 12,
  "systemShadow": true,
  "sidebarGlass": true,
  "sidebarOpacity": 80,
  "waylandBlur": true
}
```

`titlebarStyle` accepts only `macos`, `windows`, or `fusion` (Blended) and applies only to the frameless main window; native frames and the independent settings window remain compositor-controlled. `frameless`, `systemShadow`, `sidebarGlass`, and `waylandBlur` must be booleans. `cornerRadius` is an integer from 0 to 32; `sidebarOpacity` is an integer from 0 to 100. Strings and fractional numbers are rejected. UI transparency is `100 - sidebarOpacity`: 0% is fully opaque and 100% is fully transparent.

Only when the file is absent do `DSH_DESKTOP_FRAMELESS` and `DSH_DESKTOP_GLASS` supply compatible initial values: unset variables retain the defaults; an explicit value enables the option only when it is `1`. A valid integer `DSH_DESKTOP_GLASS_TINT` from 0 to 100 supplies initial fill opacity; invalid values retain the default. **Once a saved file exists, it takes precedence over these variables.** Later saves or environment changes do not mutate the loaded current-run snapshot.

Version-1 six-field files load with macOS controls. Version-2 `windows` explicitly migrates to `fusion`, preserving the previous menuless Blended appearance; `macos` remains unchanged. Every other saved value, including transparency, is retained. Reading does not rewrite the file; the next save writes version 3. To return to version 2, back up the file, map `fusion` back to `windows`, and set `schemaVersion` to `2`; the new separate Windows caption is unavailable there. For a version-1-only client, also remove `titlebarStyle`, retaining the other six values.

If the file is invalid, back it up before repairing fields or opening it with an app version that supports its schema. Direct file edits are not applied live and also require restarting. The file rejects API keys, tokens, and other credential fields.

## Compositor support and security

Background blur, shadow v2, and transparent rounded corners have been verified on KDE Plasma 6.8.2 / Wayland, including the settings save-and-restart path. The Wayland relay requests blur and shadows through compositor protocols, while root-view clipping supplies real alpha at rounded corners. It uses the primary-runtime Python bundled under resources, not system Python.

The glass sidebar no longer paints the opaque list-bottom fade, removing the white band above the footer without changing normal opaque sidebars or content. The comparison uses real captures of the same window over the same neutral backing to show the alpha difference.

![Sidebar fade before and after the fix](sidebar-fade-comparison.png)

A switch requests an effect; it does not guarantee that every desktop implements it. With native window decorations enabled, the compositor controls native corners. Compositors without the required protocols may provide transparency without blur or shadows. New effects on other compositors and X11 still need testing; successful startup of an older package does not establish appearance capabilities.

The settings window enables Electron sandbox and context isolation, disables Node integration, and exposes only `get/save/restart`. It checks the unique window, main frame, and exact local file URL. The page uses strict CSP with external scripts/styles, rejects arbitrary navigation, popups, and permissions, and does not read or transfer API credentials. These effects do not require disabling Chromium’s sandbox or changing global compositor settings.

## Maintainer checks

After applying the full series and installing dependencies, run `./scripts/check-appearance.sh` for desktop, Host, and Python relay regressions. `python3 scripts/check-patches.py` checks Git / GNU patch application from the commit pinned by `PKGBUILD`, plus local source checksums, without changing the existing source tree. `--source` can select an existing upstream Git checkout.

Native checks require an unpacked Linux runtime and an available Wayland socket: `python3 scripts/smoke-client-settings.py --source /path/to/unpacked --display wayland-1` checks settings, controls, and restart. Add `--scenario windows-corner` to check content-corner and sidebar alpha. Each run uses a temporary runtime and empty profile rather than real user settings. Unit and pixel checks do not replace testing other compositors, distributions, or arm64.

See [the 0020 notes](../patches/README.md#独立客户端外观与-kde-wayland-效果0020) for patch dependencies and implementation scope.
