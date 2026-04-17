#!/bin/bash
# =============================================================================
#
#   ██╗  ██╗ ██╗██╗  ██╗ ██████╗ ██╗  ██╗
#   ██║ ██╔╝███║██║ ██╔╝██╔═══██╗██║  ██║
#   █████╔╝ ╚██║█████╔╝ ██║   ██║███████║
#   ██╔═██╗  ██║██╔═██╗ ██║   ██║╚════██║
#   ██║  ██╗ ██║██║  ██╗╚██████╔╝     ██║
#   ╚═╝  ╚═╝ ╚═╝╚═╝  ╚═╝ ╚═════╝      ╚═╝
#
#   install_gns3_debian13.sh
#   GNS3 latest (v3.x) — Debian
#   Dynamips + uBridge + VPCS compilados desde fuente
#   Fix PyQt6 incluido (sip workaround)
#
#   by k1k04
# =============================================================================

set -euo pipefail

# ─── Colores ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[✔]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✘] ERROR: $*${NC}" >&2; exit 1; }
header() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; \
           echo -e "${BOLD}${CYAN}  $*${NC}"; \
           echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}"; }

# ─── Comprobaciones previas ───────────────────────────────────────────────────
header "Comprobaciones previas"

[[ $EUID -eq 0 ]] && die "No ejecutes este script como root. Usa un usuario con sudo."

DEBIAN_VERSION=$(grep -oP '(?<=VERSION_ID=").*(?=")' /etc/os-release 2>/dev/null || cat /etc/debian_version 2>/dev/null || echo "unknown")
info "Sistema detectado: Debian $DEBIAN_VERSION"

if ! grep -qiE 'trixie|13' /etc/os-release 2>/dev/null; then
    warn "No se detectó Debian 13 Trixie. El script puede funcionar igual, pero no se garantiza."
    read -rp "¿Continuar de todas formas? [s/N]: " RESP
    [[ "${RESP,,}" == "s" ]] || exit 0
fi

# Comprobar virtualización
VT_COUNT=$(egrep -c '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo 0)
if [[ "$VT_COUNT" -eq 0 ]]; then
    warn "No se detectó soporte de virtualización (VT-x/AMD-V). KVM no funcionará."
    warn "Activa la virtualización en la BIOS/UEFI y reinicia antes de continuar."
    read -rp "¿Continuar sin KVM? [s/N]: " RESP
    [[ "${RESP,,}" == "s" ]] || exit 0
else
    ok "Virtualización hardware detectada ($VT_COUNT vCPU(s) compatibles)"
fi

# ─── Variables configurables ──────────────────────────────────────────────────
VENV_DIR="$HOME/gns3-venv"
BUILD_DIR="/tmp/gns3-build"
CURRENT_USER=$(whoami)

# ─── PASO 1: Actualizar sistema ───────────────────────────────────────────────
header "PASO 1 — Actualizar sistema"
sudo apt update && sudo apt upgrade -y
ok "Sistema actualizado"

# ─── PASO 2: Dependencias del sistema ────────────────────────────────────────
header "PASO 2 — Instalando dependencias del sistema"

PKGS=(
    python3 python3-pip python3-venv python3-setuptools python3-dev
    python3-pyqt6 python3-pyqt6.qtsvg python3-pyqt6.qtwebsockets
    qemu-system-x86 qemu-kvm qemu-utils
    libvirt-daemon-system libvirt-clients virtinst
    bridge-utils libpcap-dev libelf-dev
    cmake git gcc g++ make
    telnet xterm wireshark
    cpu-checker curl ca-certificates
)

sudo apt install -y "${PKGS[@]}" || warn "Algún paquete no se pudo instalar — se continúa de todas formas"
ok "Dependencias instaladas"

# ─── PASO 3: Entorno virtual Python + GNS3 ───────────────────────────────────
header "PASO 3 — Instalando GNS3 (latest v3.x) en virtualenv"

if [[ -d "$VENV_DIR" ]]; then
    warn "El venv $VENV_DIR ya existe. Se usará el existente."
else
    python3 -m venv "$VENV_DIR"
    ok "Virtualenv creado en $VENV_DIR"
fi

# Activar venv e instalar
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel

# Instalar GNS3
pip install gns3-server gns3-gui

# ── Fix PyQt: en Debian 13 PyQt5/sip falla — usar PyQt6 ──────────────────────
info "Aplicando fix PyQt6 (workaround 'No module named sip')..."
pip uninstall PyQt5 PyQt5-sip sip -y 2>/dev/null || true
pip install PyQt6 PyQt6-Qt6 PyQt6-sip
ok "PyQt6 instalado correctamente"

ok "GNS3 instalado: $(gns3server --version 2>/dev/null || echo 'versión no detectada')"
deactivate

# ─── PASO 4: Compilar Dynamips ───────────────────────────────────────────────
header "PASO 4 — Compilando Dynamips desde fuente"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ -d dynamips ]]; then
    info "Repositorio dynamips ya clonado, actualizando..."
    cd dynamips && git pull && cd ..
else
    git clone https://github.com/GNS3/dynamips.git
fi

cd dynamips
mkdir -p build && cd build
cmake .. -DDYNAMIPS_CODE=stable
make -j"$(nproc)"
sudo make install
cd "$BUILD_DIR"

DYNVER=$(dynamips --version 2>&1 | head -1 || echo "no detectado")
ok "Dynamips instalado: $DYNVER"

# ─── PASO 5: Compilar uBridge ────────────────────────────────────────────────
header "PASO 5 — Compilando uBridge desde fuente"

cd "$BUILD_DIR"

if [[ -d ubridge ]]; then
    info "Repositorio ubridge ya clonado, actualizando..."
    cd ubridge && git pull && cd ..
else
    git clone https://github.com/GNS3/ubridge.git
fi

cd ubridge
make -j"$(nproc)"
sudo make install
cd "$BUILD_DIR"

ok "uBridge instalado: $(ubridge --version 2>/dev/null || echo 'no detectado')"

# Dar capacidades de red a ubridge (sin necesidad de root en runtime)
UBRIDGE_BIN=$(which ubridge 2>/dev/null || echo "")
if [[ -n "$UBRIDGE_BIN" ]]; then
    sudo setcap cap_net_admin,cap_net_raw+ep "$UBRIDGE_BIN"
    ok "Capabilities asignadas a ubridge"
else
    warn "No se encontró ubridge en PATH — asigna capabilities manualmente luego"
fi

# ─── PASO 6: Compilar VPCS ───────────────────────────────────────────────────
header "PASO 6 — Compilando VPCS desde fuente"

cd "$BUILD_DIR"

if [[ -d vpcs ]]; then
    info "Repositorio vpcs ya clonado, actualizando..."
    cd vpcs && git pull && cd ..
else
    git clone https://github.com/GNS3/vpcs.git
fi

cd vpcs/src
./mk.sh
sudo cp vpcs /usr/local/bin/vpcs
sudo chmod +x /usr/local/bin/vpcs
cd "$BUILD_DIR"

ok "VPCS instalado: $(vpcs --version 2>/dev/null | head -1 || echo 'no detectado')"

# ─── PASO 7: Permisos de usuario ─────────────────────────────────────────────
header "PASO 7 — Configurando grupos y permisos"

GROUPS_TO_ADD=(kvm libvirt wireshark)

for GRP in "${GROUPS_TO_ADD[@]}"; do
    if getent group "$GRP" &>/dev/null; then
        sudo usermod -aG "$GRP" "$CURRENT_USER"
        ok "Usuario '$CURRENT_USER' añadido al grupo '$GRP'"
    else
        warn "Grupo '$GRP' no existe — omitido"
    fi
done

# ─── PASO 8: Launcher script ──────────────────────────────────────────────────
header "PASO 8 — Creando launcher y acceso directo"

sudo tee /usr/local/bin/gns3-launcher > /dev/null << LAUNCHER
#!/bin/bash
source "$VENV_DIR/bin/activate"
exec gns3 "\$@"
LAUNCHER
sudo chmod +x /usr/local/bin/gns3-launcher
ok "Launcher creado en /usr/local/bin/gns3-launcher"

# Icono por defecto si existe
ICON_PATH="gns3"
GNS3_ICON="$VENV_DIR/share/icons/hicolor/48x48/apps/gns3.png"
[[ -f "$GNS3_ICON" ]] && ICON_PATH="$GNS3_ICON"

sudo tee /usr/share/applications/gns3.desktop > /dev/null << DESKTOP
[Desktop Entry]
Name=GNS3
GenericName=Network Simulator
Comment=Graphical Network Simulator 3
Exec=/usr/local/bin/gns3-launcher %u
Icon=$ICON_PATH
Type=Application
Categories=Education;Network;Science;
Terminal=false
StartupNotify=true
DESKTOP
ok "Acceso directo creado en /usr/share/applications/gns3.desktop"

# ─── PASO 9 (Opcional): Servicio systemd para GNS3 server ────────────────────
header "PASO 9 — Servicio systemd (opcional)"

read -rp "¿Instalar GNS3 server como servicio systemd para arranque automático? [s/N]: " SYSTEMD_RESP

if [[ "${SYSTEMD_RESP,,}" == "s" ]]; then
    sudo tee /etc/systemd/system/gns3-server.service > /dev/null << SERVICE
[Unit]
Description=GNS3 Server
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
ExecStart=$VENV_DIR/bin/gns3server --local
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

    sudo systemctl daemon-reload
    sudo systemctl enable gns3-server.service
    ok "Servicio gns3-server habilitado (arrancará en el próximo boot)"
    info "Para iniciarlo ahora: sudo systemctl start gns3-server"
else
    info "Servicio systemd omitido"
fi

# ─── PASO 10 (Opcional): Reglas de firewall ───────────────────────────────────
header "PASO 10 — Firewall (opcional)"

read -rp "¿Añadir reglas de firewall para GNS3 (puerto 3080 + UDP 10000-30000)? [s/N]: " FW_RESP

if [[ "${FW_RESP,,}" == "s" ]]; then
    if command -v nft &>/dev/null; then
        sudo nft add rule inet filter input tcp dport 3080 accept 2>/dev/null || warn "Regla nftables ya existe o tabla no configurada"
        sudo nft add rule inet filter input udp dport 10000-30000 accept 2>/dev/null || true
        ok "Reglas nftables añadidas"
    elif command -v ufw &>/dev/null; then
        sudo ufw allow 3080/tcp comment "GNS3 server"
        sudo ufw allow 10000:30000/udp comment "GNS3 console ports"
        sudo ufw reload
        ok "Reglas ufw añadidas"
    else
        warn "No se encontró nft ni ufw — añade las reglas manualmente"
    fi
else
    info "Configuración de firewall omitida"
fi

# ─── Limpieza ─────────────────────────────────────────────────────────────────
header "Limpieza"
rm -rf "$BUILD_DIR"
ok "Directorio de compilación eliminado"

# ─── Resumen final ────────────────────────────────────────────────────────────
header "Instalación completada"

echo -e ""
echo -e "${BOLD}Versiones instaladas:${NC}"
echo -e "  GNS3 server : $(source "$VENV_DIR/bin/activate" && gns3server --version 2>/dev/null; deactivate)"
echo -e "  GNS3 GUI    : $(source "$VENV_DIR/bin/activate" && gns3 --version 2>/dev/null; deactivate)"
echo -e "  Dynamips    : $(dynamips --version 2>&1 | head -1)"
echo -e "  uBridge     : $(ubridge --version 2>/dev/null || echo 'ver con: ubridge --version')"
echo -e "  VPCS        : $(vpcs --version 2>/dev/null | head -1 || echo 'ver con: vpcs --version')"
echo -e ""
echo -e "${YELLOW}⚠ IMPORTANTE: Cierra sesión y vuelve a entrar para aplicar los cambios de grupo (kvm, libvirt, wireshark).${NC}"
echo -e ""
echo -e "${BOLD}Para lanzar GNS3:${NC}"
echo -e "  → Desde terminal : ${CYAN}gns3-launcher${NC}"
echo -e "  → Desde menú     : busca 'GNS3' en tus aplicaciones"
echo -e ""
echo -e "${BOLD}Imágenes de dispositivos:${NC}"
echo -e "  IOS (Dynamips) → ${CYAN}~/GNS3/images/IOS/${NC}"
echo -e "  QEMU           → ${CYAN}~/GNS3/images/QEMU/${NC}"
echo -e ""
ok "¡Listo! Disfruta de GNS3 en Debian"
echo -e "\n${BOLD}                          — k1k04${NC}\n"
