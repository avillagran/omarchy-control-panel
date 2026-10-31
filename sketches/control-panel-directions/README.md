# Control Panel visual directions

Disposable HTML comparison only. No QML, settings, or installed plugin files were changed. Open `index.html` in a browser; the Windows and Trackpad navigation, tooltip shape/border controls, and switches simulate state without writing settings.

Round 2 retains directions 02 and 03 selected by the user. Both use the browser's `system-ui`; no named font, font download, or direction-specific font family is imposed. The native implementation must inherit Omarchy's configured `Style.font.family`, not assume the browser and Quickshell resolve identical font families. Keep typography settings independent of the chosen visual direction.

Both retain the existing sidebar order: Trackpad, Windows, Displays, Keyboard & Language, Devices, Network Devices, Backup, Profiles. Windows displays the complete tooltip controls and a sample tooltip.

| Direction | Stance | Strong at | Trade-off |
| --- | --- | --- | --- |
| 02 · Omarchy preciso | Near-black, rule-based utility with system typography | Density and precise states without ornament | Less playful |
| 03 · Studio | Dark-blue depth, specimen preview and more personality | Character without a dashboard | More stylized; color should be derived from the active theme in production |

## Round 3: hybrid

Switch refinement: use rectangular tracks and square sliding knobs, not phone-style pills. The mock opens Trackpad to compare on/off states; Windows and its tooltip controls remain available. Native implementation should reuse Omarchy's `ToggleSwitch` rather than introducing a separate mobile-style switch.

`hybrid-theme.html` combines 02's rule-based spacing and precise active states with 03's limited depth around contextual content (the tooltip specimen and profile). It retains the sidebar order and the tooltip controls. The three palette buttons demonstrate the **same layout** under semantic roles taken from the current Omarchy `colors.toml` snapshot and stock Gruvbox/Flexoki Light themes. They do not change the installed theme.

The mock uses the system `monospace` fontconfig alias, not a named font. Omarchy's `Style.font.family` currently defaults to this alias and `omarchy font set` controls its concrete family. Production QML must bind to `Style.font.family` and existing font tokens; colors must bind to live theme roles, not the example palette values embedded here. Structural radius and spacing are design choices, not fixed theme colors. Browser HTML cannot automatically watch the Omarchy theme file, so the **current** palette in this mock is a snapshot, not live theme integration.

These are directions, not production specs. The live tooltip feature in the installed panel is intentionally untouched.

## Round 4: review pass

`hybrid-theme.html` is now round 4; round 3 is kept as `hybrid-theme.r3.html`. Changes from the review:

- One `--radius` for everything (panel, nav, switch track and knob, slider knob, fields, cards). It stands in for `Style.cornerRadius`; the simulator exposes 0 / 6 / 12 to check both sharp and rounded themes.
- No drop shadows anywhere. Depth comes only from surface tone and borders.
- Eyebrow and redundant group title removed; a page shows group titles only when it has more than one group.
- Profile appears once (header). "Save to profile" moved to the Profiles page as an explicit, separate action; page subtitles state that changes apply instantly.
- Trackpad preview replaced by a test pad that reacts to real wheel/drag input and honours the natural-scroll and inertia switches.
- Slider values are editable number fields with −/+ steppers (NumberField).
- Keyboard cursor: every row is focusable; ↑↓ or j/k move, Space/Enter toggles, ←→ steps sliders. The ring is drawn outside the row like `ToggleSwitch.cursorRing`.
- Hover/selected fills are foreground-alpha mixes mirroring the shell's state tokens; DEV badge uses muted, not urgent; sidebar footer removed.
