#!/usr/bin/env bash
# EPSILON — Script d'installation
# Usage one-line : curl -sSL https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.sh | bash
# Usage local    : bash install.sh
#
# Repo public EPSILON-install : héberge ce script + docker-compose.prod.yml (sans secret).
# L'image ghcr.io/ioup3409/epsilon reste PRIVÉE → le script demande un token read:packages.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/ioup3409/EPSILON-install/main"
IMAGE="ghcr.io/ioup3409/epsilon"
GH_USER="ioup3409"
INSTALL_DIR="${EPSILON_INSTALL_DIR:-/opt/epsilon}"

# ── Couleurs ──────────────────────────────────────────────────────────────────
B='\033[1;34m' G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' N='\033[0m'
info()    { echo -e "${B}[EPSILON]${N} $*"; }
success() { echo -e "${G}[EPSILON]${N} $*"; }
warn()    { echo -e "${Y}[EPSILON]${N} $*"; }
error()   { echo -e "${R}[EPSILON]${N} $*"; exit 1; }

echo ""
echo "  ███████╗██████╗ ███████╗██╗██╗      ██████╗ ███╗   ██╗"
echo "  ██╔════╝██╔══██╗██╔════╝██║██║     ██╔═══██╗████╗  ██║"
echo "  █████╗  ██████╔╝███████╗██║██║     ██║   ██║██╔██╗ ██║"
echo "  ██╔══╝  ██╔═══╝ ╚════██║██║██║     ██║   ██║██║╚██╗██║"
echo "  ███████╗██║     ███████║██║███████╗╚██████╔╝██║ ╚████║"
echo "  ╚══════╝╚═╝     ╚══════╝╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝"
echo ""

# ── Vérification OS ───────────────────────────────────────────────────────────
[[ "$OSTYPE" == "linux-gnu"* ]] || error "Ce script est pour Linux. Sur Windows, utilisez install.bat."

# ── Sudo ──────────────────────────────────────────────────────────────────────
SUDO=""
if [[ $EUID -ne 0 ]]; then
  command -v sudo &>/dev/null || error "Lancez le script en root ou installez sudo."
  SUDO="sudo"
fi

# ── Docker ────────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  info "Docker non détecté — installation..."
  curl -fsSL https://get.docker.com | $SUDO sh
  if [[ $EUID -ne 0 ]]; then
    $SUDO usermod -aG docker "$USER"
    warn "Utilisateur ajouté au groupe docker. Une reconnexion peut être nécessaire."
  fi
  $SUDO systemctl enable --now docker
else
  info "Docker $(docker --version | cut -d' ' -f3 | tr -d ',') détecté."
  if ! docker info &>/dev/null 2>&1; then
    info "Démarrage du daemon Docker..."
    $SUDO systemctl start docker
  fi
fi

# ── Docker Compose plugin ─────────────────────────────────────────────────────
if ! docker compose version &>/dev/null 2>&1; then
  info "Installation du plugin Docker Compose..."
  ARCH=$(uname -m); [[ "$ARCH" == "aarch64" ]] && ARCH="aarch64" || ARCH="x86_64"
  DC_DIR="${DOCKER_CONFIG:-$HOME/.docker}/cli-plugins"
  mkdir -p "$DC_DIR"
  curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${ARCH}" \
    -o "$DC_DIR/docker-compose"
  chmod +x "$DC_DIR/docker-compose"
fi

# ── Répertoire d'installation ─────────────────────────────────────────────────
info "Répertoire : $INSTALL_DIR"
$SUDO mkdir -p "$INSTALL_DIR"
$SUDO chown "$(id -u):$(id -g)" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ── Téléchargement docker-compose.prod.yml ────────────────────────────────────
info "Téléchargement de la configuration..."
curl -sSL "$REPO_RAW/docker-compose.prod.yml" -o docker-compose.yml

# ── Configuration .env ────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  info "Configuration initiale..."

  # Lecture depuis /dev/tty → fonctionne même via `curl | bash` (où stdin = le script).
  # GH_TOKEN peut aussi être fourni en variable d'environnement (mode automatisé).
  if [ -e /dev/tty ]; then
    read -rp "  Port d'écoute [3000] : " PORT </dev/tty
    [ -z "${GH_TOKEN:-}" ] && { read -rsp "  GitHub token (read:packages, image privée) : " GH_TOKEN </dev/tty; echo ""; }
  fi

  PORT="${PORT:-3000}"
  GH_TOKEN="${GH_TOKEN:-}"

  if [[ -z "$GH_TOKEN" ]]; then
    error "Token GitHub requis (read:packages) pour tirer l'image privée. Relancez avec un terminal ou GH_TOKEN=... en variable d'env."
  fi
  WATCHTOWER_TOKEN=$(openssl rand -hex 32 2>/dev/null || cat /proc/sys/kernel/random/uuid | tr -d '-')

  cat > .env << EOF
EPSILON_PORT=${PORT}
EPSILON_VERSION=latest
WATCHTOWER_TOKEN=${WATCHTOWER_TOKEN}
GH_TOKEN=${GH_TOKEN}
EOF
  success ".env créé."
else
  warn ".env existant conservé (supprimez-le pour reconfigurer)."
fi

# Charger les variables
set -a; source .env; set +a

# ── Authentification ghcr.io ──────────────────────────────────────────────────
if [[ -n "${GH_TOKEN:-}" ]]; then
  info "Connexion à ghcr.io..."
  echo "$GH_TOKEN" | docker login ghcr.io -u "$GH_USER" --password-stdin
else
  error "GH_TOKEN manquant — impossible de tirer l'image privée."
fi

# ── Pull & start ──────────────────────────────────────────────────────────────
info "Téléchargement de l'image EPSILON..."
docker compose pull

info "Démarrage d'EPSILON (premier démarrage : build frontend ~2-3 min)..."
docker compose up -d

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
success "EPSILON installé et démarré !"
echo ""
echo "  → Interface  : http://$(hostname -I | awk '{print $1}'):${EPSILON_PORT:-3000}"
echo "  → Logs       : docker compose -f $INSTALL_DIR/docker-compose.yml logs -f epsilon"
echo "  → Arrêt      : docker compose -f $INSTALL_DIR/docker-compose.yml down"
echo "  → Mise à jour : depuis l'interface admin EPSILON"
echo ""
