# Omarchy Control Panel

System Settings panel for **Omarchy / Hyprland**, built as an Omarchy shell plugin (Quickshell/QML). Familiar for users coming from macOS, useful for everyone.

## Qué hace

Panel de configuración rápida que se sumona desde la barra de Omarchy. Controla, sin tocar `/usr/share/omarchy` ni pedir sudo:

- **Trackpad / Mouse** (optimizado para Apple MTP multi-touch, clasificado como mouse por Hyprland):
  - Tap to click (sin presionar)
  - Scroll natural/invertido (por dispositivo, vía `natural_scroll` + `scroll_factor`)
  - Scroll con inercia
  - Swipe de 3 dedos para cambiar de escritorio
- **Animaciones**: animaciones del sistema, transición de escritorios, flat pointer acceleration, velocidad/sensibilidad
- **Ventanas**: espaciado interno/externo (gaps)
- **Dispositivos**: retroiluminación de teclado, APFS (discos macOS)
- **Teclado e Idioma**: distribución física, idioma del sistema
- **Luz nocturna**, captura de pantalla, y más

## Características técnicas

- **i18n externo**: todos los strings viven en `i18n.json` (en/es/pt/fr), editables como datos planos sin tocar el QML.
- **Persistencia**: el estado se guarda en `~/.config/hypr/control-panel.lua` (re-aplicado al cargar Hyprland) y en prefs JSON del plugin.
- **Sin root**: el plugin nunca escribe en `/usr/share/omarchy` ni pide sudo; solo cambios esenciales vía `hyprctl`.
- **Sin flicker de estado**: la UI se sincroniza desde el Lua (fuente de verdad) al abrir, evitando el flip-flop de lectura de `hyprctl` en dispositivos mouse-class.

## Instalación

```bash
omarchy plugin add https://github.com/avillagran/omarchy-control-panel
```

O clónalo manualmente en `~/.config/omarchy/plugins/io.github.avillagran.omarchy-control-panel/` y habilítalo.

## Estructura

```
manifest.json        # declaración del plugin (id, kinds, entry points)
BarWidget.qml        # widget en la barra que sumona el panel
Panel.qml            # el panel de configuración
i18n.json            # strings de UI en 4 idiomas
```

## Verificación

Antes de publicar/subir, corre el smoke test:

```bash
~/.local/bin/verify-omarchy-control-panel.sh
```

Valida el manifest con `omarchy-plugin-validate`, revisa symlinks, JSON y que el panel cargue sin errores.

## Licencia

MIT — ver [LICENSE](LICENSE).
