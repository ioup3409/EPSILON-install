#!/usr/bin/env bash
# EPSILON — Script d'installation
# Usage one-line : curl -sSL https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.sh | bash
# Usage local    : bash install.sh
# Agent seul     : sudo bash install.sh --agent-only
#                  (ne touche NI à Docker, NI au compose, NI à l'image : pose ou met à niveau
#                  l'agent hôte natif d'une installation existante. C'est aussi ce qu'EPSILON
#                  exécute lui-même, depuis sa propre image, au premier démarrage d'une version.)
#
# ⚠️ SOURCE DE VÉRITÉ : dépôt EPSILON. Publié vers EPSILON-install à chaque tag par la CI.
#    Ne pas éditer la copie d'EPSILON-install : la prochaine release l'écraserait.
#
# Repo public EPSILON-install : héberge ce script + docker-compose.prod.yml (sans secret).
# L'image ghcr.io/ioup3409/epsilon reste PRIVÉE → le script demande un token GitHub.
# Un seul token, qui sert au pull de l'image ET à lire le registre de modules privé :
#   - Classic      : scopes read:packages + repo
#   - Fine-grained : packages read + Contents:read sur EPSILON-modules

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/ioup3409/EPSILON-install/main"
IMAGE="ghcr.io/ioup3409/epsilon"
GH_USER="ioup3409"
INSTALL_DIR="${EPSILON_INSTALL_DIR:-/opt/epsilon}"

# ── Mode ──────────────────────────────────────────────────────────────────────
# 🔴 Une mise à jour d'EPSILON remplace l'IMAGE, elle ne rejoue pas ce script. Tout ce qu'il
# pose sur la machine hors de Docker (l'agent hôte) doit donc pouvoir être reposé SEUL — sans
# retélécharger le compose, sans tirer d'image, sans redémarrer EPSILON.
AGENT_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --agent-only) AGENT_ONLY=1 ;;
    *) echo "Option inconnue : $arg (seule --agent-only existe)" >&2; exit 2 ;;
  esac
done

# ── Couleurs ──────────────────────────────────────────────────────────────────
B='\033[1;34m' G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' N='\033[0m'
info()    { echo -e "${B}[EPSILON]${N} $*"; }
success() { echo -e "${G}[EPSILON]${N} $*"; }
warn()    { echo -e "${Y}[EPSILON]${N} $*"; }
error()   { echo -e "${R}[EPSILON]${N} $*"; exit 1; }

# Réessaie une commande en cas d'échec réseau transitoire (DNS, timeout registre).
# retry <max> <délai_s> <commande...>
retry() {
  local max="$1" delay="$2"; shift 2
  local n=1
  until "$@"; do
    [ "$n" -ge "$max" ] && return 1
    warn "Échec réseau (tentative $n/$max) — nouvel essai dans ${delay}s…"
    sleep "$delay"
    n=$((n + 1))
  done
}

if [[ "$AGENT_ONLY" != "1" ]]; then
echo ""
echo "  ███████╗██████╗ ███████╗██╗██╗      ██████╗ ███╗   ██╗"
echo "  ██╔════╝██╔══██╗██╔════╝██║██║     ██╔═══██╗████╗  ██║"
echo "  █████╗  ██████╔╝███████╗██║██║     ██║   ██║██╔██╗ ██║"
echo "  ██╔══╝  ██╔═══╝ ╚════██║██║██║     ██║   ██║██║╚██╗██║"
echo "  ███████╗██║     ███████║██║███████╗╚██████╔╝██║ ╚████║"
echo "  ╚══════╝╚═╝     ╚══════╝╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝"
echo ""
fi

# ── Vérification OS ───────────────────────────────────────────────────────────
[[ "$OSTYPE" == "linux-gnu"* ]] || error "Ce script est pour Linux. Sur Windows, utilisez install.bat."

# ── Sudo ──────────────────────────────────────────────────────────────────────
SUDO=""
if [[ $EUID -ne 0 ]]; then
  command -v sudo &>/dev/null || error "Lancez le script en root ou installez sudo."
  SUDO="sudo"
fi

# ── Agent hôte NATIF — le service, son compte, et SON runtime ─────────────────
# 🔑 Pourquoi un composant HORS Docker, alors que tout le reste y est : le matériel
# de la machine (broches GPIO, ports série, disques, son) n'est PAS visible depuis
# un conteneur — les fichiers de périphérique n'y existent pas. Un module EPSILON
# qui pilote du matériel a donc besoin d'un exécutant côté machine. Décision de
# l'utilisateur du 2026-09-09 ; voir docs/plans/epsilon-hardware-modules.md.
#
# 🔴 Ce que ce bloc N'ACCORDE PAS : aucun groupe supplémentaire, donc l'agent ne
# peut toucher AUCUN périphérique. L'accès à un disque ou à une broche se déclare
# plus tard, appareil par appareil, quand un administrateur le coche dans EPSILON.
# Au repos l'agent ne voit rien, et c'est ce qui protège — pas une garde qu'on
# pourrait oublier d'écrire.
#
# ⚠️ Refusable : EPSILON_SKIP_HOST_AGENT=1 (variable d'environnement, ou ligne dans
# .env) pour une installation qui n'a aucun matériel à piloter. Le reste marche sans lui.
#
# Code de retour : 0 = installé, OU impossible par nature sur cette machine (refusé,
# pas de systemd) — relancer n'y changerait rien ; 1 = échec qu'un nouvel essai peut
# lever (compte, volume, Node). EPSILON relance au démarrage suivant sur un 1, pas sur un 0.
#
# 🔴 **L'agent est OPTIONNEL : aucune de ses défaillances ne doit abandonner
# l'installation.** Appelée dans un `if`, cette fonction s'exécute SANS `set -e` (règle
# de bash) : chaque geste dont l'échec compte est donc vérifié explicitement.
install_host_agent() {
  if [[ "${EPSILON_SKIP_HOST_AGENT:-0}" == "1" ]]; then
    info "Agent hôte natif : non installé (EPSILON_SKIP_HOST_AGENT=1)."
    warn "Conséquence PRÉCISE : les modules matériels seront refusés à l'installation."
    return 0
  fi

  local AGENT_USER="epsilon-agent"
  local AGENT_DIR="$INSTALL_DIR/agent"
  local AGENT_UNIT="/etc/systemd/system/epsilon-host-agent.service"
  # 🔑 Ph. A3 — le point de contact entre EPSILON et l'agent. Il vit dans un volume Docker,
  # et un volume Docker est un DOSSIER DE LA MACHINE : l'agent natif l'emprunte (BindPaths=
  # ci-dessous), au même chemin que dans les conteneurs. Rien ne change donc du côté
  # d'EPSILON — ni son conteneur, ni docker-compose.yml, ni docker-compose.override.yml.
  # ⚠️ Ces deux valeurs répètent backend/core/Host/protocol.js (AGENT_SOCKET_VOLUME,
  # AGENT_SOCKET_DIR) ; un test les tient alignées.
  local AGENT_SOCK_VOLUME="epsilon-host-sock"
  local AGENT_SOCK_DIR="/run/epsilon-host"

  # `/run/systemd/system` n'existe que si systemd TOURNE — un `systemctl` présent dans un
  # conteneur ou un chroot ne suffit pas.
  if ! command -v systemctl &>/dev/null || [[ ! -d /run/systemd/system ]]; then
    warn "systemd absent — l'agent hôte natif n'est pas installé."
    warn "Conséquence PRÉCISE : les modules matériels (GPIO, port série, disques, son)"
    warn "seront refusés à l'installation, avec un message. Tout le reste fonctionne."
    return 0
  fi

  info "Installation de l'agent hôte (accès au matériel de la machine)…"

  # Compte de service dédié : pas de connexion, pas de home, aucun groupe en plus.
  # 🔑 « Aucun groupe » n'est pas un oubli, c'est le niveau de départ voulu.
  if ! id -u "$AGENT_USER" &>/dev/null; then
    $SUDO useradd --system --no-create-home --shell /usr/sbin/nologin "$AGENT_USER" || true
    if id -u "$AGENT_USER" &>/dev/null; then
      info "Compte de service « $AGENT_USER » créé (sans droits sur le matériel)."
    fi
  fi
  if ! id -u "$AGENT_USER" &>/dev/null; then
    warn "Compte « $AGENT_USER » impossible à créer — agent hôte non installé."
    warn "Conséquence PRÉCISE : les modules matériels seront refusés à l'installation."
    return 1
  fi

  # ── Le point de contact : le dossier du volume, lu dans Docker, jamais supposé ──
  # 🔴 `Mountpoint` dépend du dossier de données de Docker, qui n'est pas partout
  # /var/lib/docker. On le demande. ⚠️ `$SUDO test` et non `[[ -d ]]` : ce dossier n'est
  # pas traversable par un utilisateur ordinaire, et le test mentirait par « absent ».
  local SOCK_SOURCE
  SOCK_SOURCE="$($DK volume inspect --format '{{.Mountpoint}}' "$AGENT_SOCK_VOLUME" 2>/dev/null || true)"
  if [[ -z "$SOCK_SOURCE" ]] || ! $SUDO test -d "$SOCK_SOURCE"; then
    warn "Volume « $AGENT_SOCK_VOLUME » introuvable — EPSILON a-t-il déjà démarré sur cette machine ?"
    warn "Agent hôte non installé ; relancez une fois EPSILON démarré."
    return 1
  fi
  # Le seul endroit où l'agent écrit. EPSILON (root dans son conteneur) y accède toujours.
  $SUDO chown "$AGENT_USER:$AGENT_USER" "$SOCK_SOURCE" || true
  $SUDO chmod 770 "$SOCK_SOURCE" || true

  # Le code appartient à root et l'agent ne fait que le LIRE : un agent qui pourrait
  # réécrire son propre programme n'aurait plus de frontière du tout.
  local RELEASES="$AGENT_DIR/releases"
  $SUDO mkdir -p "$RELEASES" || true
  $SUDO chown root:root "$AGENT_DIR" "$RELEASES" || true
  $SUDO chmod 755 "$AGENT_DIR" "$RELEASES" || true

  # ── De quelle image extraire ? Celle qui TOURNE, pas une étiquette ──────────
  # 🔴 `:latest` peut désigner une image plus récente que celle d'EPSILON — tirée par une
  # mise à jour annulée, par exemple. Un Node et une version venus de là feraient refuser
  # le canal par le cœur. Ordre : ce qu'EPSILON a désigné lui-même, sinon le conteneur
  # en service, et seulement en dernier recours l'étiquette de .env.
  local IMAGE_REF="${EPSILON_AGENT_IMAGE:-}"
  if [[ -z "$IMAGE_REF" ]]; then
    local CORE_CTN
    CORE_CTN="$($DK compose ps -q epsilon 2>/dev/null | head -n 1 || true)"
    if [[ -n "$CORE_CTN" ]]; then
      IMAGE_REF="$($DK inspect --format '{{.Image}}' "$CORE_CTN" 2>/dev/null || true)"
    fi
  fi
  if [[ -z "$IMAGE_REF" ]]; then IMAGE_REF="${IMAGE}:${EPSILON_VERSION:-latest}"; fi

  # 🔴 La version se lit DANS L'IMAGE, jamais dans .env. Le cœur compare l'identité
  # de son propre build à celle que l'agent annonce ; `.env` porte un TAG (« latest »),
  # pas la version bakée. Deux valeurs différentes ⇒ le contrôle refuserait à tort.
  local CORE_VERSION
  CORE_VERSION="$($DK run --rm --entrypoint sh "$IMAGE_REF" -c 'printenv EPSILON_VERSION' 2>/dev/null | tr -d '\r\n' || true)"
  if [[ -z "$CORE_VERSION" ]]; then CORE_VERSION="dev"; fi

  # ── Une RELEASE par artefact, CÔTE À CÔTE (ph. A4) ──────────────────────────
  # 🔴 Jamais d'écrasement en place : l'agent est le canal de secours, le casser casse le
  # moyen de le réparer — sur une machine sans écran. Chaque image a son dossier
  # `releases/<identifiant>` (son Node, son programme, sa version), et `current` désigne
  # celle en service. On ne bascule qu'après que la nouvelle a répondu au `hello`, et la
  # précédente est gardée : revenir en arrière, c'est refaire pointer un lien.
  local IMAGE_ID
  IMAGE_ID="$($DK image inspect --format '{{.Id}}' "$IMAGE_REF" 2>/dev/null || true)"
  IMAGE_ID="${IMAGE_ID#sha256:}"
  if [[ -z "$IMAGE_ID" ]]; then
    warn "Image « $IMAGE_REF » introuvable — agent hôte non mis à jour."
    return 1
  fi
  local RELEASE_ID="${IMAGE_ID:0:12}"
  local RELEASE_DIR="$RELEASES/$RELEASE_ID"
  local CURRENT="$AGENT_DIR/current"
  local PREVIOUS_ID=""
  if [[ -L "$CURRENT" ]]; then PREVIOUS_ID="$(basename "$(readlink "$CURRENT")")"; fi

  # 🔑 UNE seule liste des restrictions du service : elle écrit l'unité ET encadre
  # l'épreuve du `hello`. Deux listes finiraient par diverger, et l'épreuve validerait
  # alors une release dans un cadre qui n'est pas celui où elle tournera.
  local AGENT_SANDBOX=(NoNewPrivileges=yes ProtectSystem=strict ProtectHome=yes PrivateTmp=yes)

  local ALREADY_CURRENT=0
  if [[ "$PREVIOUS_ID" == "$RELEASE_ID" ]]; then
    if $SUDO test -f "$RELEASE_DIR/agent.env"; then ALREADY_CURRENT=1; fi
  fi
  if [[ "$ALREADY_CURRENT" == "1" ]]; then
    info "Agent hôte : la release $RELEASE_ID (version $CORE_VERSION) est déjà en service."
  else
    local STAGING="$RELEASES/.staging-$RELEASE_ID-$$"
    $SUDO rm -rf "$STAGING" || true
    if ! $SUDO mkdir -p "$STAGING"; then
      warn "Dossier $STAGING impossible à créer — agent hôte non mis à jour."
      return 1
    fi

    # ── Le Node de la release : on ESSAIE, puis on VÉRIFIE ────────────────────
    # 1er choix : le binaire de l'image EPSILON. Même artefact que le cœur, donc
    #             aucune dérive de version, et rien à installer sur la machine.
    # 🔴 Mais un binaire construit pour l'image peut être incompatible avec les
    #    bibliothèques système de CETTE machine. On ne le suppose pas : on
    #    l'exécute pour de vrai, et on ne le garde que s'il répond.
    # 2e choix : le gestionnaire de paquets de la machine.
    local NODE_OK=0
    local TMP_CTN="epsilon-node-extract-$$"
    if $DK create --name "$TMP_CTN" "$IMAGE_REF" &>/dev/null; then
      if $DK cp "$TMP_CTN:/usr/local/bin/node" "/tmp/$TMP_CTN-node" &>/dev/null; then
        $SUDO install -m 755 -o root -g root "/tmp/$TMP_CTN-node" "$STAGING/node" || true
        # ⚠️ LA vérification qui décide. `--version` suffit : si les bibliothèques
        #    manquent, le binaire ne démarre même pas.
        if "$STAGING/node" --version &>/dev/null; then
          NODE_OK=1
          info "Runtime : Node extrait de l'image ($("$STAGING/node" --version)) — compatible."
        else
          warn "Le Node de l'image ne s'exécute pas sur cette machine (bibliothèques système différentes)."
          $SUDO rm -f "$STAGING/node" || true
        fi
      fi
      rm -f "/tmp/$TMP_CTN-node" || true
      $DK rm -f "$TMP_CTN" &>/dev/null || true
    else
      warn "Extraction depuis l'image impossible — on passera par le gestionnaire de paquets."
    fi

    # Repli : Node de la machine. ⚠️ Sa version est INDÉPENDANTE de celle du cœur —
    # c'est le prix du repli, et c'est pourquoi il n'est pas le premier choix.
    # 🔴 `< /dev/null` : quand EPSILON rejoue ce script, il le lui passe par l'ENTRÉE
    # standard. Un gestionnaire de paquets qui poserait une question lirait la suite du
    # script comme réponse — et le script s'arrêterait au milieu, sans erreur.
    if [[ "$NODE_OK" != "1" ]]; then
      if ! command -v node &>/dev/null; then
        info "Installation de Node via le gestionnaire de paquets…"
        if command -v apt-get &>/dev/null; then
          curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash - || true
          $SUDO apt-get install -y nodejs < /dev/null || true
        elif command -v dnf &>/dev/null; then
          $SUDO dnf install -y nodejs < /dev/null || true
        elif command -v apk &>/dev/null; then
          $SUDO apk add --no-cache nodejs < /dev/null || true
        fi
      fi
      if command -v node &>/dev/null; then
        $SUDO ln -sfn "$(command -v node)" "$STAGING/node" || true
        NODE_OK=1
        warn "Runtime : Node de la machine ($(node --version)) — version indépendante du cœur."
      fi
    fi
    if [[ "$NODE_OK" != "1" ]]; then
      warn "Aucun Node utilisable — l'agent hôte natif n'est pas installé."
      warn "Conséquence PRÉCISE : les modules matériels seront refusés à l'installation."
      warn "Tout le reste d'EPSILON fonctionne normalement."
      $SUDO rm -rf "$STAGING" || true
      return 1
    fi

    # ── Le programme : la liste des fichiers est CALCULÉE par l'image elle-même ──
    # `host-agent-files.js` suit les imports de l'agent : aucune liste tenue à la main,
    # donc aucun fichier oublié le jour où l'agent en importe un de plus.
    # ⚠️ `bash` + `pipefail` DANS l'image : sans eux, une liste en échec donnerait une
    # archive VIDE et un code de retour nul — une release sans programme.
    if ! $DK run --rm --entrypoint bash "$IMAGE_REF" -c \
          'set -o pipefail; cd /app && node backend/scripts/host-agent-files.js | tar -cf - -T -' \
        | $SUDO tar -xf - --no-same-owner -C "$STAGING" \
      || ! $SUDO test -f "$STAGING/backend/scripts/host-agent.js" \
      || ! $SUDO test -f "$STAGING/backend/scripts/host-agent-probe.js"; then
      warn "Programme de l'agent impossible à extraire de l'image — agent hôte non mis à jour."
      $SUDO rm -rf "$STAGING" || true
      return 1
    fi
    # Lisible (et traversable) par le compte de l'agent ; modifiable par root seul.
    $SUDO chmod -R u=rwX,go=rX "$STAGING" || true

    # 🔑 La version VOYAGE avec le programme : l'unité lit `current/agent.env`, donc
    # changer de release change aussi la version annoncée — sans réécrire l'unité.
    if ! printf 'EPSILON_VERSION=%s\n' "$CORE_VERSION" | $SUDO tee "$STAGING/agent.env" > /dev/null; then
      warn "Version de la release impossible à écrire — agent hôte non mis à jour."
      $SUDO rm -rf "$STAGING" || true
      return 1
    fi

    # ── L'ÉPREUVE : la nouvelle release répond-elle au `hello` ? ───────────────
    # Lancée sous le compte de l'agent, avec les restrictions de son service et son
    # `agent.env`, sur un socket TEMPORAIRE : l'agent en place n'est jamais dérangé.
    # La version attendue est passée en argument — celle lue dans l'image —, jamais
    # reprise de l'environnement de la release, qui la comparerait à elle-même.
    local PROBE=(--quiet --wait --pipe --collect
      -p "User=$AGENT_USER" -p "Group=$AGENT_USER" -p "EnvironmentFile=$STAGING/agent.env")
    local p
    for p in "${AGENT_SANDBOX[@]}"; do PROBE+=(-p "$p"); done
    local PROBE_OUT
    if PROBE_OUT="$($SUDO systemd-run "${PROBE[@]}" \
          "$STAGING/node" "$STAGING/backend/scripts/host-agent-probe.js" "$CORE_VERSION" < /dev/null 2>&1)"; then
      info "Épreuve de la release $RELEASE_ID : l'agent répond au hello (version $CORE_VERSION)."
    else
      warn "La release $RELEASE_ID ne répond pas au hello — la release en service est CONSERVÉE."
      warn "Sonde : $PROBE_OUT"
      $SUDO rm -rf "$STAGING" || true
      return 1
    fi

    # ── La bascule : ATOMIQUE, et seulement maintenant ─────────────────────────
    # Ce dossier n'est pas celui en service (sinon on serait passé par « déjà en
    # service » plus haut) : le remplacer ne touche rien de vivant.
    $SUDO rm -rf "$RELEASE_DIR" || true
    if ! $SUDO mv -T "$STAGING" "$RELEASE_DIR"; then
      warn "Release $RELEASE_ID impossible à mettre en place — la release en service est CONSERVÉE."
      $SUDO rm -rf "$STAGING" || true
      return 1
    fi
    # `mv -T` d'un lien sur un autre est un renommage : aucun instant sans `current`.
    if ! $SUDO ln -sfn "releases/$RELEASE_ID" "$AGENT_DIR/current.new" \
      || ! $SUDO mv -Tf "$AGENT_DIR/current.new" "$CURRENT"; then
      warn "Bascule vers la release $RELEASE_ID impossible — la release en service est CONSERVÉE."
      return 1
    fi
    if [[ -n "$PREVIOUS_ID" ]]; then
      success "Agent hôte : release $RELEASE_ID en service (version $CORE_VERSION) — la précédente ($PREVIOUS_ID) est conservée."
    else
      success "Agent hôte : release $RELEASE_ID en service (version $CORE_VERSION)."
    fi
  fi

  # ── Ménage : la release en service et la précédente, rien d'autre ──────────
  # Chaque release emporte son Node (~120 Mo) : sans ménage, une carte SD se remplirait
  # d'une version par mise à jour. Deux suffisent pour revenir en arrière.
  local d name
  for d in "$RELEASES"/* "$RELEASES"/.staging-*; do
    if [[ ! -e "$d" ]]; then continue; fi
    name="$(basename "$d")"
    if [[ "$name" != "$RELEASE_ID" && "$name" != "$PREVIOUS_ID" ]]; then
      $SUDO rm -rf "$d" || true
    fi
  done
  # Disposition de la 0.5.5 (un Node posé à même le dossier) : remplacée par les releases.
  $SUDO rm -f "$AGENT_DIR/node" "$AGENT_DIR/host-agent.js" || true

  if ! $SUDO tee "$AGENT_UNIT" > /dev/null << UNIT_EOF
[Unit]
Description=Agent hôte EPSILON — le canal entre EPSILON et cette machine
Documentation=https://github.com/ioup3409/EPSILON
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=$AGENT_USER
Group=$AGENT_USER
# Aucun SupplementaryGroups : au repos l'agent ne touche AUCUN périphérique.
# L'accès s'accorde appareil par appareil, depuis EPSILON, et se retire de même.
# La release en service, à travers le lien « current » : changer de version, c'est
# refaire pointer ce lien — l'unité, elle, ne change plus.
ExecStart=$AGENT_DIR/current/node $AGENT_DIR/current/backend/scripts/host-agent.js
# La version VOYAGE avec le programme : chaque release porte la sienne.
EnvironmentFile=$AGENT_DIR/current/agent.env
Environment=EPSILON_HOST_AGENT_SOCKET=$AGENT_SOCK_DIR/agent.sock
# Le point de contact avec EPSILON : le dossier du volume Docker, prêté au service au
# même chemin que dans les conteneurs. Le compte de l'agent ne peut pas traverser le
# dossier de données de Docker ; c'est systemd, avant de lui céder la main, qui monte.
BindPaths=$SOCK_SOURCE:$AGENT_SOCK_DIR
# « + » = exécuté par systemd lui-même. Rend le dossier à l'agent s'il a été recréé
# entre-temps (docker compose down -v) — sans quoi l'agent ne pourrait plus y écrire.
ExecStartPre=+/bin/chown $AGENT_USER:$AGENT_USER $SOCK_SOURCE
Restart=on-failure
RestartSec=5
# Durcissement : l'agent lit la machine, il ne la modifie pas — sauf son point de contact.
# (Mêmes lignes que celles qui encadrent l'épreuve du hello : une seule liste.)
$(printf '%s\n' "${AGENT_SANDBOX[@]}")

[Install]
WantedBy=multi-user.target
UNIT_EOF
  then
    warn "Unité systemd impossible à écrire ($AGENT_UNIT) — agent hôte non installé."
    return 1
  fi

  $SUDO systemctl daemon-reload || true
  $SUDO systemctl enable epsilon-host-agent.service &>/dev/null || true
  success "Service « epsilon-host-agent » installé (version annoncée : $CORE_VERSION)."
  # ⚠️ PAS de `start` ici, et ce n'est pas un oubli : l'agent en conteneur sert encore, et
  #    les deux écriraient le même socket. Choisir l'agent natif et le démarrer, c'est le
  #    rôle d'EPSILON (ph. A5), pas de l'installateur.
  info "Le service reste arrêté : c'est EPSILON qui le démarrera."
  return 0
}
# ── Fin de l'agent hôte ───────────────────────────────────────────────────────

# ── Contexte Docker ───────────────────────────────────────────────────────────
# Juste après l'install de Docker, l'ajout au groupe `docker` ne s'applique qu'à
# une nouvelle session → le socket est inaccessible sans sudo dans CETTE session.
# On bascule donc sur `sudo docker` si le socket n'est pas joignable. login + pull
# + up partagent ainsi le même contexte (cohérence des credentials).
docker_context() {
  if docker info >/dev/null 2>&1; then
    DK="docker"
  else
    warn "Groupe docker pas encore actif dans cette session → utilisation de sudo."
    DK="$SUDO docker"
  fi
}

# ── Agent seul : ni Docker, ni compose, ni image — l'agent, et on s'arrête ────
if [[ "$AGENT_ONLY" == "1" ]]; then
  [[ -d "$INSTALL_DIR" ]] || error "Aucune installation d'EPSILON dans $INSTALL_DIR (EPSILON_INSTALL_DIR pour un autre dossier)."
  cd "$INSTALL_DIR"
  command -v docker &>/dev/null || error "Docker absent — EPSILON n'est pas installé sur cette machine."
  # .env peut porter EPSILON_SKIP_HOST_AGENT=1 : un refus écrit une fois doit valoir pour
  # tous les passages, y compris ceux qu'EPSILON déclenche lui-même.
  if [[ -f .env ]]; then set -a; source .env; set +a; fi
  docker_context
  if install_host_agent; then exit 0; else exit 1; fi
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

# ── docker-compose.override.yml — JAMAIS écrasé ───────────────────────────────
# 🔴 La ligne ci-dessus RÉÉCRIT docker-compose.yml à chaque passage de ce script.
# Tout réglage propre à la machine — au premier chef le rattachement d'un disque —
# doit donc vivre ailleurs, sinon il disparaît SILENCIEUSEMENT à la mise à jour et
# l'entrepôt de fichiers devient inaccessible : le dossier accordé dans EPSILON
# pointerait sur un chemin que le conteneur ne voit plus.
# Compose fusionne ce fichier automatiquement — c'est pourquoi aucune commande
# `compose` de ce script n'utilise `-f` (qui désactiverait justement la fusion).
# Même traitement que .env : créé s'il manque, jamais touché s'il existe.
if [[ ! -f docker-compose.override.yml ]]; then
  cat > docker-compose.override.yml << 'OVERRIDE_EOF'
# docker-compose.override.yml — CE FICHIER EST LE VÔTRE. EPSILON n'y touche jamais.
#
# Docker Compose le fusionne automatiquement avec docker-compose.yml à chaque
# démarrage. C'est le SEUL endroit où mettre vos réglages : docker-compose.yml est
# réécrit à chaque installation ou mise à jour, celui-ci ne l'est pas.
#
# ── Rendre un disque de la machine visible par EPSILON ────────────────────────
#
# Un disque monté sur la machine n'est PAS visible depuis EPSILON tant qu'il n'est
# pas déclaré ici : un conteneur ne voit pas les montages de son hôte.
#
# Marche à suivre :
#   1. montez le disque sur la machine (/etc/fstab) et vérifiez qu'il contient
#      bien vos fichiers ;
#   2. décommentez le bloc ci-dessous et adaptez les chemins ;
#   3. relancez :  docker compose up -d
#   4. dans EPSILON, accordez le dossier (Administration ▸ Emplacements) — le
#      chemin à saisir est celui de `target`.
#
# services:
#   epsilon:
#     volumes:
#       # Même chemin des deux côtés : c'est le plus simple à retenir, et c'est
#       # celui que vous saisirez dans EPSILON.
#       - type: bind
#         source: /mnt/disque-data
#         target: /mnt/disque-data
#         bind:
#           # false : Docker ne fabrique pas le dossier s'il manque. Le démarrage
#           # échoue alors franchement, au lieu de présenter un dossier VIDE dans
#           # lequel on croirait ses fichiers perdus. Un disque non monté doit se
#           # voir tout de suite.
#           create_host_path: false
#           # rslave : si vous démontez puis remontez le disque côté machine, le
#           # conteneur suit. Sans cela il continuerait de voir l'ancien contenu.
#           propagation: rslave
#
#       # Un disque de sauvegarde se rattache en lecture seule :
#       - type: bind
#         source: /mnt/sauvegarde
#         target: /mnt/sauvegarde
#         read_only: true
#         bind:
#           create_host_path: false
OVERRIDE_EOF
  success "docker-compose.override.yml créé — vos réglages y survivront aux mises à jour."
else
  warn "docker-compose.override.yml existant conservé (vos réglages sont préservés)."
fi

# ── Configuration .env ────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  info "Configuration initiale..."

  # Lecture depuis /dev/tty → fonctionne même via `curl | bash` (où stdin = le script).
  # GH_TOKEN peut aussi être fourni en variable d'environnement (mode automatisé).
  if [ -e /dev/tty ]; then
    read -rp "  Port d'écoute [3000] : " PORT </dev/tty
    [ -z "${GH_TOKEN:-}" ] && { read -rsp "  GitHub token (packages:read + Contents:read EPSILON-modules) : " GH_TOKEN </dev/tty; echo ""; }
  fi

  PORT="${PORT:-3000}"
  GH_TOKEN="${GH_TOKEN:-}"

  if [[ -z "$GH_TOKEN" ]]; then
    error "Token GitHub requis (read:packages) pour tirer l'image privée. Relancez avec un terminal ou GH_TOKEN=... en variable d'env."
  fi
  cat > .env << EOF
EPSILON_PORT=${PORT}
EPSILON_VERSION=latest
GH_TOKEN=${GH_TOKEN}
EOF
  success ".env créé."
else
  warn ".env existant conservé (supprimez-le pour reconfigurer)."
fi

# Charger les variables
set -a; source .env; set +a

docker_context

# ── Authentification ghcr.io ──────────────────────────────────────────────────
if [[ -n "${GH_TOKEN:-}" ]]; then
  info "Connexion à ghcr.io..."
  echo "$GH_TOKEN" | $DK login ghcr.io -u "$GH_USER" --password-stdin
else
  error "GH_TOKEN manquant — impossible de tirer l'image privée."
fi

# ── Pull & start ──────────────────────────────────────────────────────────────
info "Téléchargement de l'image EPSILON..."
if ! retry 5 6 $DK compose pull; then
  warn "Téléchargement échoué après 5 tentatives — réseau/DNS du serveur instable."
  warn "Configurez un DNS fiable puis relancez l'installation :"
  echo  "    echo '{\"dns\": [\"1.1.1.1\", \"8.8.8.8\"]}' | sudo tee /etc/docker/daemon.json"
  echo  "    sudo systemctl restart docker"
  error "Abandon."
fi

info "Démarrage d'EPSILON..."
retry 3 6 $DK compose up -d

# ── Agent hôte natif — voir install_host_agent() plus haut ─────────────────────
# Après `compose up` : le volume du point de contact existe désormais, et le conteneur
# d'EPSILON en service désigne l'image dont extraire le Node.
if ! install_host_agent; then
  warn "Agent hôte natif non installé — EPSILON réessaiera lui-même à son prochain démarrage."
fi

IP=$(hostname -I | awk '{print $1}')
PORT="${EPSILON_PORT:-3000}"

# ── Attente du serveur de configuration ───────────────────────────────────────
# Le conteneur démarre en arrière-plan et sert le wizard de configuration (rapide,
# aucun build à ce stade). Le build du frontend a lieu APRÈS la configuration,
# pendant le redémarrage — le wizard web gère cette attente et redirige tout seul.
info "Démarrage d'EPSILON…"
info "L'URL de configuration s'affichera dès que l'interface est prête."
READY=0
for _ in $(seq 1 180); do                       # ~15 min max (180 × 5 s)
  if curl -sf "http://localhost:${PORT}/api/setup/status" >/dev/null 2>&1; then
    READY=1; break
  fi
  printf '.'
  sleep 5
done
echo ""

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
if [ "$READY" = "1" ]; then
  success "EPSILON démarré — à configurer dans le navigateur."
  echo ""
  echo "  → Configuration : http://${IP}:${PORT}/setup   (ouvrir dans un navigateur)"
  echo "    (après validation du wizard, le frontend se construit puis l'app s'ouvre)"
else
  warn "Le démarrage prend plus de temps que prévu, ou a échoué."
  echo "  → Suivez l'avancement : cd $INSTALL_DIR && sudo docker compose logs -f epsilon"
  echo "  → Dès qu'il est prêt  : http://${IP}:${PORT}/setup"
fi
echo ""
# ⚠️ `cd` puis `compose` SANS `-f` : passer `-f docker-compose.yml` désignerait ce
# seul fichier et ferait ignorer docker-compose.override.yml — donc les disques que
# l'administrateur y a rattachés. Un `down` ainsi lancé travaillerait sur une autre
# définition que celle qui tourne.
echo "  → Logs   : cd $INSTALL_DIR && sudo docker compose logs -f epsilon"
echo "  → Arrêt  : cd $INSTALL_DIR && sudo docker compose down"
echo "  → Rattacher un disque : $INSTALL_DIR/docker-compose.override.yml (marche à suivre dans le fichier)"
echo "  → Mise à jour : depuis l'interface admin EPSILON"
echo ""
