#!/bin/bash
# setup.sh · Claude Usage Widget
# Configura el Gist de GitHub y el LaunchAgent de macOS.

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

echo -e "${BOLD}${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║   Claude Usage Widget · Setup        ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

PYTHON3=$(which python3 2>/dev/null || echo "/usr/bin/python3")
[ -x "$PYTHON3" ] || { echo -e "${RED}Error: python3 no encontrado.${NC}"; exit 1; }

mkdir -p ~/claude-usage

# ── GitHub credentials ───────────────────────────────────────────────────────
echo -e "${YELLOW}Paso 1/4 · GitHub Personal Access Token${NC}"
echo ""
echo "Necesitas un token con scope 'gist' (solo eso, sin más permisos)."
echo "Créalo en: https://github.com/settings/tokens/new"
echo "  → Nota: claude-usage-widget"
echo "  → Expiration: sin expiración (o la que prefieras)"
echo "  → Scopes: ✓ gist"
echo ""

read -p "  Tu GitHub username: " GITHUB_USER
echo -n "  Personal Access Token: "
read -s GITHUB_TOKEN
echo ""

if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}Error: username y token son obligatorios.${NC}"
    exit 1
fi

# ── Verify token ─────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Verificando token...${NC}"
TOKEN_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "User-Agent: claude-usage-widget/1.0" \
    https://api.github.com/user)

if [ "$TOKEN_CHECK" != "200" ]; then
    echo -e "${RED}Error: token inválido o sin permisos (HTTP $TOKEN_CHECK).${NC}"
    echo "  • Asegúrate de que el token tiene scope 'gist'"
    echo "  • Crea uno nuevo en https://github.com/settings/tokens/new"
    exit 1
fi
echo -e "${GREEN}  ✓ Token válido${NC}"

# ── Create Gist ──────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Paso 2/4 · Creando Gist privado...${NC}"

PAYLOAD=$("$PYTHON3" -c "
import json
init = json.dumps({'window_hours':5,'updated_at':'init','input_tokens':0,'output_tokens':0,'cache_creation_input_tokens':0,'cache_read_input_tokens':0,'total_tokens':0,'estimated_cost_usd':0})
print(json.dumps({'description':'Claude Code Usage Widget','public':False,'files':{'claude-usage.json':{'content':init}}}))
")

GIST_RESPONSE=$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: claude-usage-widget/1.0" \
    -d "$PAYLOAD" \
    https://api.github.com/gists)

GIST_ID=$("$PYTHON3" -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('id',''))" <<< "$GIST_RESPONSE" 2>/dev/null)

if [ -z "$GIST_ID" ]; then
    echo -e "${RED}Error al crear el Gist.${NC}"
    echo "Respuesta de GitHub:"
    echo "$GIST_RESPONSE" | "$PYTHON3" -m json.tool 2>/dev/null || echo "$GIST_RESPONSE"
    exit 1
fi

GIST_ID=$("$PYTHON3" -c "import json,sys; print(json.loads(sys.stdin.read())['id'])" <<< "$GIST_RESPONSE")

if [ -z "$GIST_ID" ]; then
    echo -e "${RED}Error: no se pudo obtener el ID del Gist.${NC}"
    echo "Respuesta: $GIST_RESPONSE"
    exit 1
fi

echo -e "${GREEN}  ✓ Gist creado: $GIST_ID${NC}"

# ── Save config ──────────────────────────────────────────────────────────────
cat > ~/claude-usage/config.json << CONFIGEOF
{
  "github_user": "$GITHUB_USER",
  "github_token": "$GITHUB_TOKEN",
  "gist_id": "$GIST_ID"
}
CONFIGEOF
chmod 600 ~/claude-usage/config.json
echo -e "${GREEN}  ✓ Config guardado (permisos 600)${NC}"

# ── First sync ───────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Paso 3/4 · Primera sincronización...${NC}"
"$PYTHON3" ~/claude-usage/sync.py
echo -e "${GREEN}  ✓ Datos subidos al Gist${NC}"

# ── LaunchAgent ──────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Paso 4/4 · Instalando LaunchAgent (cada 2 min)...${NC}"

PLIST="$HOME/Library/LaunchAgents/com.claude.usage-sync.plist"
cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.usage-sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON3</string>
        <string>$HOME/claude-usage/sync.py</string>
    </array>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/claude-usage/sync.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/claude-usage/sync-error.log</string>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo -e "${GREEN}  ✓ LaunchAgent activo${NC}"

# ── Summary ──────────────────────────────────────────────────────────────────
RAW_URL="https://gist.githubusercontent.com/${GITHUB_USER}/${GIST_ID}/raw/claude-usage.json"

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ✅ Setup completado${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}xbar (widget barra de menú Mac):${NC}"
echo "  1. Instala xbar: https://xbarapp.com/"
echo "  2. Abre xbar → Open Plugin Folder"
echo "  3. Copia y renombra el plugin:"
echo ""
echo -e "     ${BLUE}cp ~/claude-usage/xbar-plugin.sh <carpeta-xbar>/claude-usage.2m.sh${NC}"
echo -e "     ${BLUE}chmod +x <carpeta-xbar>/claude-usage.2m.sh${NC}"
echo ""
echo -e "${BOLD}Scriptable (widget iPhone):${NC}"
echo "  1. Instala Scriptable desde App Store"
echo "  2. Crea un script nuevo, pega el contenido de:"
echo "     ~/claude-usage/scriptable.js"
echo "  3. Cambia estas líneas al inicio del script:"
echo -e "     ${BLUE}const GITHUB_USER = \"$GITHUB_USER\";${NC}"
echo -e "     ${BLUE}const GIST_ID     = \"$GIST_ID\";${NC}"
echo "  4. Larga presión en la pantalla → agregar widget → Scriptable"
echo ""
echo -e "${BOLD}URL del Gist (sin auth, solo lectura):${NC}"
echo -e "  ${BLUE}$RAW_URL${NC}"
echo ""
