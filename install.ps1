# EPSILON — Script d'installation Windows (PowerShell)
# Usage one-line : powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.ps1 | iex"
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

# ── Configuration .env ────────────────────────────────────────────────────────
if (-not (Test-Path ".env")) {
    Write-Info "Configuration initiale..."

    $PORT = Read-Host "  Port d'écoute [3000]"
    if (-not $PORT) { $PORT = "3000" }

    $GH_TOKEN = Read-Host "  GitHub token (read:packages, pour l'image privée)"
    if (-not $GH_TOKEN) { Write-Err "Token GitHub requis (read:packages) pour tirer l'image privée." }

    $WATCHTOWER_TOKEN = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))

    $envContent = @"
EPSILON_PORT=$PORT
EPSILON_VERSION=latest
WATCHTOWER_TOKEN=$WATCHTOWER_TOKEN
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

# ── Résumé ────────────────────────────────────────────────────────────────────
$PORT = [System.Environment]::GetEnvironmentVariable("EPSILON_PORT", "Process")
if (-not $PORT) { $PORT = "3000" }

Write-Host ""
Write-Success "EPSILON installé et démarré !"
Write-Host ""
Write-Host "  → Interface  : http://localhost:$PORT" -ForegroundColor Green
Write-Host "  → Logs       : docker compose -f $INSTALL_DIR\docker-compose.yml logs -f epsilon" -ForegroundColor Gray
Write-Host "  → Arrêt      : docker compose -f $INSTALL_DIR\docker-compose.yml down" -ForegroundColor Gray
Write-Host "  → Mise à jour : depuis l'interface admin EPSILON" -ForegroundColor Gray
Write-Host ""
