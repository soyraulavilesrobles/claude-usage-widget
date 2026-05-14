# Handover — Claude Usage Widget

## Qué hace

Muestra el % de uso de Claude Code en la ventana activa de 5 horas (igual que `/usage`) en:
- **Barra de menú del Mac** (xbar) — refresca cada 2 min
- **Status line de Claude Code** (terminal) — refresca con cada mensaje
- **Widget del iPhone** (Scriptable) — refresca por iOS (~5-15 min, o al tocar)

**Arquitectura:**
```
Claude Code stdin → statusline.py → caché local (~/.cache/claude-usage/)
                                          ↓
                              sync.py (launchd, cada 2 min)
                                          ↓
                               GitHub Gist (privado)
                                    ↙        ↘
                            xbar plugin    Scriptable (iPhone)
```

---

## Archivos clave

| Archivo | Rol |
|---|---|
| `statusline.py` | Recibe JSON oficial de Anthropic vía stdin desde Claude Code. Guarda el caché y muestra `🤖 62% $8.45 ↺21:30` en el terminal. **Usa el máximo de `used_percentage` dentro de la ventana activa** para evitar que el % baje por valores inconsistentes de la API. |
| `sync.py` | Lee el caché oficial (TTL 10 min). Si está vencido, estima desde JSONL con cutoff inteligente basado en `resets_at`. Sube a GitHub Gist. |
| `xbar-plugin.sh` | Lee el Gist. Muestra `🤖 62%` en la barra de menú con dropdown: barra de progreso, costo, countdown al reset (`↺ en 2h30m (21:30)`), semana 7d. |
| `scriptable.js` | Widget iOS: muestra %, barra, costo, countdown. Al tocar abre Scriptable y re-ejecuta el script para refrescar. `refreshAfterDate` en el pasado fuerza redibujado al volver al home screen. |
| `config.json` | `github_user`, `github_token` (scope: gist), `gist_id`, `subscription_type`. Permisos 600. **No está en git.** |
| `config.example.json` | Plantilla para nuevos usuarios. |
| `setup.sh` | Instalador interactivo: crea Gist, guarda config, instala LaunchAgent. |

---

## Comportamiento de la API de Anthropic (cosas raras que aprendimos)

1. **`resets_at` no se actualiza en cada ventana nueva.** La API puede seguir reportando el `resets_at` de la ventana anterior aunque ya haya reseteado. No usarlo como señal de invalidación de caché.

2. **`used_percentage` es inconsistente entre requests.** En la misma ventana, distintos requests pueden reportar 6%, 22%, 6%, 24%. Solución: `statusline.py` guarda el máximo visto dentro de la ventana (mismo `resets_at`).

3. **Cuando hay actividad, el caché oficial siempre es más preciso que la estimación JSONL.** El JSONL sobreestima porque duplica requestIds y cuenta subagentes (`isSidechain`).

4. **El caché se invalida por edad (10 min), no por `resets_at`.** Si el usuario no usa Claude Code por más de 10 min, `sync.py` cae al fallback JSONL.

---

## Fallback JSONL (cuando no hay caché oficial fresco)

`sync.py` lee `~/.claude/projects/**/*.jsonl`, deduplica por `requestId`, ignora `isSidechain`. El cutoff de tiempo es `max(now - 5h, window_start_from_stale_cache())`.

`window_start_from_stale_cache()` lee el `resets_at` del caché aunque esté vencido:
- Si `resets_at` está en el futuro → window empezó en `resets_at - 5h`
- Si `resets_at` está en el pasado Y es menor a 5h atrás → window empezó en `resets_at` (reset reciente)
- Si `resets_at` es más de 5h atrás → retorna None (el rolling 5h cubre todo)

---

## Limitaciones conocidas

| Limitación | Por qué | Workaround |
|---|---|---|
| Widget iPhone puede tardar 5-15 min en refrescar | iOS controla WidgetKit refresh | Tocar el widget → Scriptable abre y refresca manualmente |
| Después de un reset, el % puede tardar hasta 10 min en reflejar 0% | El caché oficial dura 10 min | Nada; es el TTL del caché |
| Token breakdown siempre muestra 0 con fuente oficial | Anthropic no incluye desglose de tokens en la API de rate limits | Se muestra "datos oficiales sin desglose" |
| Error de red si el Mac duerme durante el sync | launchd no reintenta si falla por red | El siguiente ciclo de 2 min lo resuelve solo |

---

## Configuración requerida en `~/.claude/settings.json`

```json
{
  "statusLine": {
    "type": "command",
    "command": "/usr/local/bin/python3 /Users/TU_USUARIO/claude-usage/statusline.py",
    "refreshInterval": 5
  }
}
```

Reiniciar Claude Code tras cambiar esto.

---

## LaunchAgent

```
~/Library/LaunchAgents/com.claude.usage-sync.plist
```
Corre `sync.py` cada 120 segundos. Logs en:
- `~/claude-usage/sync.log` — output del último sync
- `~/claude-usage/sync-error.log` — errores (ej. red no disponible)

Recargar tras cambios:
```bash
launchctl unload ~/Library/LaunchAgents/com.claude.usage-sync.plist
launchctl load ~/Library/LaunchAgents/com.claude.usage-sync.plist
```

---

## Repositorio

https://github.com/soyraulavilesrobles/claude-usage-widget
