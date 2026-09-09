# EPSILON — Script d'installation Windows (PowerShell)
# Usage one-line : powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.ps1 | iex"
#
# ⚠️ SOURCE DE VÉRITÉ : dépôt EPSILON. Publié vers EPSILON-install à chaque tag par la CI.
#    Ne pas éditer la copie d'EPSILON-install : la prochaine release l'écraserait.
#
# Repo public EPSILON-install : ce script + docker-compose.prod.yml (sans secret).
# L'image ghcr.io/ioup3409/epsilon reste PRIVÉE → token read:packages demandé.

$ErrorActionPreference = "Stop"
$REPO_RAW  = "https://raw.githubusercontent.com/ioup3409/EPSILON-install/main"
$INSTALL_DIR = if ($env:EPSILON_INSTALL_DIR) { $env:EPSILON_INSTALL_DIR } else { "C:\epsilon" }

function Write-Info    { Write-Host "[EPSILON] $args" -ForegroundColor Cyan }
function Write-Success { Write-Host "[EPSILON] $args" -ForegroundColor Green }
function Write-Warn    { Write-Host "[EPSILON] $args" -ForegroundColor Yellow }
function Write-Err     { Write-Host "[EPSILON] $args" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  ███████╗██████╗ ███████╗██╗██╗      ██████╗ ███╗   ██╗" -ForegroundColor Cyan
Write-Host "  ██╔════╝██╔══██╗██╔════╝██║██║     ██╔═══██╗████╗  ██║" -ForegroundColor Cyan
Write-Host "  █████╗  ██████╔╝███████╗██║██║     ██║   ██║██╔██╗ ██║" -ForegroundColor Cyan
Write-Host "  ██╔══╝  ██╔═══╝ ╚════██║██║██║     ██║   ██║██║╚██╗██║" -ForegroundColor Cyan
Write-Host "  ███████╗██║     ███████║██║███████╗╚██████╔╝██║ ╚████║" -ForegroundColor Cyan
Write-Host "  ╚══════╝╚═╝     ╚══════╝╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝" -ForegroundColor Cyan
Write-Host ""

# ── Docker ────────────────────────────────────────────────────────────────────
$dockerOk = $false
try { docker info 2>$null | Out-Null; $dockerOk = $true } catch {}

if (-not $dockerOk) {
    Write-Warn "Docker non détecté ou non démarré."
    $installed = $false
    try { docker --version 2>$null | Out-Null; $installed = $true } catch {}

    if (-not $installed) {
        Write-Info "Installation de Docker Desktop via winget..."
        try {
            winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
            Write-Warn "Docker Desktop installé. Redémarrez Windows, puis relancez install.bat."
            Write-Host "  Téléchargement direct : https://www.docker.com/products/docker-desktop/" -ForegroundColor Yellow
        } catch {
            Write-Warn "winget non disponible. Installez Docker Desktop manuellement :"
            Write-Host "  https://www.docker.com/products/docker-desktop/" -ForegroundColor Yellow
        }
        Read-Host "Appuyez sur Entrée pour quitter"
        exit 0
    } else {
        Write-Warn "Docker installé mais non démarré. Lancez Docker Desktop puis relancez ce script."
        Read-Host "Appuyez sur Entrée pour quitter"
        exit 0
    }
}

Write-Info "Docker détecté."

# ── Répertoire d'installation ─────────────────────────────────────────────────
Write-Info "Répertoire : $INSTALL_DIR"
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Set-Location $INSTALL_DIR

# ── Téléchargement docker-compose.prod.yml ────────────────────────────────────
Write-Info "Téléchargement de la configuration..."
Invoke-WebRequest "$REPO_RAW/docker-compose.prod.yml" -OutFile "docker-compose.yml"

# ── docker-compose.override.yml — JAMAIS écrasé ───────────────────────────────
# 🔴 La ligne ci-dessus RÉÉCRIT docker-compose.yml à chaque passage de ce script.
# Tout réglage propre à la machine — au premier chef le rattachement d'un disque —
# doit donc vivre ailleurs, sinon il disparaît SILENCIEUSEMENT à la mise à jour et
# l'entrepôt de fichiers devient inaccessible. Compose fusionne ce fichier
# automatiquement : c'est pourquoi aucune commande `compose` n'utilise `-f`.
# Même traitement que .env : créé s'il manque, jamais touché s'il existe.
if (-not (Test-Path "docker-compose.override.yml")) {
    $overrideTemplate = @'
# docker-compose.override.yml — CE FICHIER EST LE VÔTRE. EPSILON n'y touche jamais.
#
# Docker Compose le fusionne automatiquement avec docker-compose.yml à chaque
# démarrage. C'est le SEUL endroit où mettre vos réglages : docker-compose.yml est
# réécrit à chaque installation ou mise à jour, celui-ci ne l'est pas.
#
# ── Rendre un dossier de la machine visible par EPSILON ───────────────────────
#
# Un dossier de la machine n'est PAS visible depuis EPSILON tant qu'il n'est pas
# déclaré ici : un conteneur ne voit pas les montages de son hôte.
#
# Marche à suivre :
#   1. vérifiez que le dossier existe et contient bien vos fichiers ;
#   2. décommentez le bloc ci-dessous et adaptez les chemins ;
#   3. relancez :  docker compose up -d
#   4. dans EPSILON, accordez le dossier (Administration > Emplacements) — le
#      chemin à saisir est celui de `target`.
#
# services:
#   epsilon:
#     volumes:
#       # À gauche le chemin Windows, à droite celui que verra EPSILON — c'est ce
#       # dernier que vous saisirez dans l'application.
#       - type: bind
#         source: D:\Donnees
#         target: /mnt/donnees
#         bind:
#           # false : Docker ne fabrique pas le dossier s'il manque. Le démarrage
#           # échoue alors franchement, au lieu de présenter un dossier VIDE dans
#           # lequel on croirait ses fichiers perdus.
#           create_host_path: false
#
#       # Un dossier de sauvegarde se rattache en lecture seule :
#       - type: bind
#         source: D:\Sauvegarde
#         target: /mnt/sauvegarde
#         read_only: true
#         bind:
#           create_host_path: false
'@
    # 🔴 Écriture SANS BOM. `Out-File -Encoding utf8` en PowerShell 5.1 ajoute une
    # marque d'ordre d'octets invisible en tête de fichier — piège déjà rencontré
    # sur ce projet. Ici elle se retrouverait avant la première clé YAML.
    [System.IO.File]::WriteAllText(
        (Join-Path $INSTALL_DIR "docker-compose.override.yml"),
        $overrideTemplate,
        (New-Object System.Text.UTF8Encoding $false))
    Write-Success "docker-compose.override.yml créé — vos réglages y survivront aux mises à jour."
} else {
    Write-Warn "docker-compose.override.yml existant conservé (vos réglages sont préservés)."
}

# ── Configuration .env ────────────────────────────────────────────────────────
if (-not (Test-Path ".env")) {
    Write-Info "Configuration initiale..."

    $PORT = Read-Host "  Port d'écoute [3000]"
    if (-not $PORT) { $PORT = "3000" }

    $GH_TOKEN = Read-Host "  GitHub token (read:packages, pour l'image privée)"
    if (-not $GH_TOKEN) { Write-Err "Token GitHub requis (read:packages) pour tirer l'image privée." }

    $envContent = @"
EPSILON_PORT=$PORT
EPSILON_VERSION=latest
GH_TOKEN=$GH_TOKEN
"@
    $envContent | Out-File -FilePath ".env" -Encoding utf8 -NoNewline
    Write-Success ".env créé."
} else {
    Write-Warn ".env existant conservé (supprimez-le pour reconfigurer)."
}

# Charger les variables depuis .env
Get-Content ".env" | ForEach-Object {
    if ($_ -match "^([^#=]+)=(.*)$") {
        [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
    }
}

# ── Authentification ghcr.io ──────────────────────────────────────────────────
$GH_TOKEN = [System.Environment]::GetEnvironmentVariable("GH_TOKEN", "Process")
if ($GH_TOKEN) {
    Write-Info "Connexion à ghcr.io..."
    $GH_TOKEN | docker login ghcr.io -u ioup3409 --password-stdin
} else {
    Write-Err "GH_TOKEN manquant — impossible de tirer l'image privée."
}

# ── Pull & start ──────────────────────────────────────────────────────────────
Write-Info "Téléchargement de l'image EPSILON..."
docker compose pull

Write-Info "Démarrage d'EPSILON (premier démarrage : build frontend ~2-3 min)..."
docker compose up -d

# ── Agent hôte natif — REFUS EXPLICITE sous Windows ───────────────────────────
# 🔴 Un refus DIT, jamais un silence. Sur Linux, l'installateur pose un service
# système (« epsilon-host-agent ») qui donne aux modules matériels l'accès aux
# broches GPIO, ports série, disques et cartes son de la machine. Ce service
# repose sur systemd et sur les règles de périphérique du noyau Linux : ni l'un
# ni l'autre n'existe ici.
#
# ⚠️ Pourquoi l'écrire au lieu de se taire : sans ce message, un administrateur
# Windows installerait un module matériel, verrait un refus à l'installation, et
# chercherait la cause dans le module. Elle est ici, et elle est structurelle.
# ⇒ Ne PAS remplacer par une émulation partielle : une capacité annoncée qui ne
#    marche qu'à moitié coûte plus cher qu'une capacité absente et dite.
Write-Host ""
Write-Warn "Agent hôte natif : non installé sur Windows (systemd absent)."
Write-Host "    Conséquence PRÉCISE : les modules qui pilotent du MATÉRIEL — GPIO," -ForegroundColor Gray
Write-Host "    port série, préparation de disque, audio de la machine — seront refusés" -ForegroundColor Gray
Write-Host "    à l'installation, avec un message. Tout le reste d'EPSILON fonctionne." -ForegroundColor Gray
Write-Host "    Pour ces usages, la cible est une machine Linux (Raspberry Pi, serveur)." -ForegroundColor Gray

# ── Résumé ────────────────────────────────────────────────────────────────────
$PORT = [System.Environment]::GetEnvironmentVariable("EPSILON_PORT", "Process")
if (-not $PORT) { $PORT = "3000" }

Write-Host ""
Write-Success "EPSILON installé et démarré !"
Write-Host ""
Write-Host "  → Interface  : http://localhost:$PORT" -ForegroundColor Green
# ⚠️ `cd` puis `compose` SANS `-f` : passer `-f docker-compose.yml` désignerait ce
# seul fichier et ferait ignorer docker-compose.override.yml — donc les dossiers que
# l'administrateur y a rattachés.
Write-Host "  → Logs       : cd $INSTALL_DIR ; docker compose logs -f epsilon" -ForegroundColor Gray
Write-Host "  → Arrêt      : cd $INSTALL_DIR ; docker compose down" -ForegroundColor Gray
Write-Host "  → Rattacher un dossier : $INSTALL_DIR\docker-compose.override.yml" -ForegroundColor Gray
Write-Host "  → Mise à jour : depuis l'interface admin EPSILON" -ForegroundColor Gray
Write-Host ""
