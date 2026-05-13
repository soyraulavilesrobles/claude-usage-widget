# Claude Usage Widget

Muestra el porcentaje de uso de Claude Code en la **ventana de 5 horas** — igual que `/usage` — en la barra de menú del Mac (xbar), en el iPhone (Scriptable) y en el terminal de Claude Code. Funciona sin WiFi compartida.

**Shows your Claude Code usage** for the **5-hour window** — matching `/usage` exactly — in your Mac menu bar (xbar), iPhone (Scriptable), and Claude Code's status line. No shared WiFi required.

---

## Cómo funciona / How it works

```
Claude Code (oficial stdin)
        │
        ▼
  statusline.py  ──→  terminal status bar  🤖 23% $0.82 ↺14:30
        │
        ▼
    sync.py (cada 2 min / every 2 min)
        │
        ▼
  GitHub Gist (cloud)
        │
   ┌────┴────┐
   ▼         ▼
xbar       Scriptable
(Mac)      (iPhone)
```

`statusline.py` recibe los datos **oficiales de Anthropic** vía stdin desde Claude Code y los cachea localmente. `sync.py` los sube a un Gist privado de GitHub. Los widgets leen ese Gist desde cualquier red.

`statusline.py` receives **official Anthropic data** via stdin from Claude Code and caches it locally. `sync.py` pushes it to a private GitHub Gist. Both widgets read from that Gist on any network.

---

## Requisitos / Requirements

- macOS con Python 3 / macOS with Python 3
- [Claude Code](https://claude.ai/code) instalado / installed
- Cuenta de GitHub / GitHub account
- [xbar](https://xbarapp.com/) (widget barra de menú Mac / Mac menu bar widget)
- [Scriptable](https://apps.apple.com/app/scriptable/id1405459188) en iPhone (opcional / optional)

---

## Instalación / Installation

### 1. Clona el repositorio / Clone the repo

```bash
git clone https://github.com/soyraulavilesrobles/claude-usage-widget.git ~/claude-usage
cd ~/claude-usage
```

### 2. Crea un token de GitHub / Create a GitHub token

Ve a / Go to: **https://github.com/settings/tokens/new**

- Nota / Note: `claude-usage-widget`
- Scopes: solo `gist` / only `gist`
- Expiración / Expiration: sin límite (o la que prefieras / or whatever you prefer)

### 3. Ejecuta el setup / Run setup

```bash
bash ~/claude-usage/setup.sh
```

El script pedirá tu usuario y token de GitHub, creará el Gist, guardará la configuración e instalará el LaunchAgent que sincroniza cada 2 minutos.

The script will ask for your GitHub username and token, create the Gist, save the config, and install the LaunchAgent that syncs every 2 minutes.

### 4. Configura el status line de Claude Code / Configure Claude Code status line

Agrega esto a `~/.claude/settings.json` / Add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/usr/local/bin/python3 /Users/TU_USUARIO/claude-usage/statusline.py",
    "refreshInterval": 5
  }
}
```

Reemplaza `TU_USUARIO` con tu nombre de usuario de macOS / Replace `TU_USUARIO` with your macOS username.

Reinicia Claude Code para que tome efecto / Restart Claude Code for it to take effect.

### 5. xbar (barra de menú Mac / Mac menu bar)

```bash
# Instala xbar desde https://xbarapp.com/
# Abre xbar → Open Plugin Folder / Open xbar → Open Plugin Folder
cp ~/claude-usage/xbar-plugin.sh <carpeta-xbar>/claude-usage.2m.sh
chmod +x <carpeta-xbar>/claude-usage.2m.sh
# Haz clic en "Refresh All" en xbar / Click "Refresh All" in xbar
```

### 6. Scriptable (iPhone)

1. Instala [Scriptable](https://apps.apple.com/app/scriptable/id1405459188) desde la App Store
2. Abre Scriptable → toca `+` → pega el contenido de `scriptable.js`
3. Edita las dos primeras líneas de configuración:
   ```javascript
   const GITHUB_USER = "tu-usuario-github";
   const GIST_ID     = "el-id-de-tu-gist";  // lo muestra el setup al final
   ```
4. Mantén presionado el home screen → `+` → Scriptable → elige tamaño → selecciona el script

---

## Archivos / Files

| Archivo / File | Descripción |
|---|---|
| `setup.sh` | Instalador interactivo / Interactive installer |
| `statusline.py` | Recibe datos oficiales de Claude Code vía stdin / Receives official Claude Code data via stdin |
| `sync.py` | Sube datos al Gist de GitHub / Pushes data to GitHub Gist |
| `xbar-plugin.sh` | Plugin para la barra de menú del Mac / Mac menu bar plugin |
| `scriptable.js` | Widget para iPhone via Scriptable / iPhone widget via Scriptable |
| `config.example.json` | Plantilla de configuración / Config template |

---

## Qué muestra / What it shows

- **%** de uso en la ventana activa de 5 horas (dato oficial de Anthropic)
- **↺ en Xh** — tiempo hasta el reset de la ventana / time until window resets
- **Costo estimado** en USD / Estimated cost in USD
- Barra de progreso verde/amarillo/rojo según el nivel / Green/amber/red progress bar by level
- Fuente: `✓` = datos oficiales, `~` = estimación desde JSONL local (fallback) / Source: `✓` = official data, `~` = local JSONL estimate (fallback)

---

## Suscripciones / Subscription types

Edita `config.json` y agrega `subscription_type` / Edit `config.json` and add `subscription_type`:

```json
{
  "subscription_type": "pro"
}
```

| Valor / Value | Límite / Limit |
|---|---|
| `pro` | $13.00 / ventana 5h |
| `max_5x` | $65.00 / ventana 5h |
| `max_20x` | $260.00 / ventana 5h |

---

## Licencia / License

MIT
