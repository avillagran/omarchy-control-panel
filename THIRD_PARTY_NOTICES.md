# Third-party notices

## qs-hyprview

QuickView's overview renderer is provided by [qs-hyprview](https://github.com/dom0/qs-hyprview), authored by Domenico Martella ([dom0](https://github.com/dom0)).

- Source: https://github.com/dom0/qs-hyprview at `1fdea0ac9faea585771d4da3680397e449285706`
- Pinned revision: `fe44661a95b8ab4b7f9f4c290334cf4c3c129d31` in https://github.com/avillagran/qs-hyprview (upstream plus one Qt 6.12 import fix; the same commit as the `external/qs-hyprview` submodule). On first use `bin/quickview-toggle.sh` clones it, checks out that exact commit and refuses to run anything else.
- License: GNU General Public License v3.0 (SPDX: `GPL-3.0`; `external/qs-hyprview/LICENSE`)
- Integration: Omarchy Control Panel owns only the launcher, Hyprland gesture/key binding integration, and future Omarchy-specific extensions. The upstream renderer remains a Git submodule and is not presented as an original work of this project.
