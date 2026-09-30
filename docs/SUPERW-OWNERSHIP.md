# SUPER+W ownership

Control Panel can keep all of its mouse, window, monitor and keyboard settings
without owning SUPER+W. Set `"manageSuperW": false` in the existing
`~/.local/state/omarchy/control-panel-prefs.json`, preserving its other fields.
Both settings interfaces retain this preference when saving. The startup helper
and forced settings calls then leave the compositor binding alone; the legacy
Lua writer also omits that binding. The browser-close option is disabled while
another component owns the shortcut. An installed Reprieve managed binding takes precedence even when older
preferences omit `manageSuperW`, including forced calls from a settings window.
Without that binding, missing `manageSuperW` retains existing behavior.

After changing ownership, reload Hyprland so the desired binding in the user's
configuration takes effect. Verify with `hyprctl binds -j` and, for Reprieve,
`reprieve-doctor`. Turning ownership off does not delete another component's
binding or send keypresses.

`node --test tests/superw-ownership.test.js` tests actual QML preference/save
methods and the helper with a fake compositor; it never operates real windows.
