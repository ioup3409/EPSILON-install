# EPSILON — Installation

Installation on-premise d'**EPSILON** via Docker, en une seule commande.

EPSILON est livré sous forme d'image Docker. Le serveur n'a besoin que de **Docker** — ni Node.js, ni base de données à installer manuellement : tout est embarqué et géré automatiquement.

---

## Prérequis

- Un serveur **Linux** (x86-64 ou ARM64 / Raspberry Pi 64-bit) **ou** un poste **Windows** avec Docker Desktop.
- **Docker** — installé automatiquement par le script sous Linux s'il est absent. Sous Windows, installez [Docker Desktop](https://www.docker.com/products/docker-desktop/) au préalable.
- Un **token d'accès** (`read:packages`) fourni avec votre licence EPSILON — nécessaire pour télécharger l'image.

---

## Installation

### Linux

```bash
curl -sSL https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ioup3409/EPSILON-install/main/install.ps1 | iex"
```

Le script :

1. installe Docker si nécessaire (Linux) ;
2. demande le **port d'écoute** (3000 par défaut) et votre **token** ;
3. se connecte au registre, télécharge l'image et démarre EPSILON.

> Le token n'est utilisé que pour `docker login` (téléchargement de l'image). Il n'est stocké que localement, dans le fichier `.env` du dossier d'installation.

---

## Premier démarrage — configuration

Au tout premier lancement, EPSILON ouvre un **assistant de configuration web**. Depuis n'importe quel navigateur sur le réseau :

```
http://<adresse-du-serveur>:3000/setup
```

L'assistant détecte votre environnement (PC, serveur, Raspberry Pi…) et propose un préréglage adapté. Vous choisissez la base de données, le cache, puis créez le **compte administrateur**. EPSILON redémarre alors automatiquement avec votre configuration et vous redirige vers l'application.

> Aucun écran ni clavier nécessaire sur le serveur : l'installation peut se faire entièrement à distance (SSH + navigateur).

---

## Gestion

Le dossier d'installation est `/opt/epsilon` (Linux) ou `C:\epsilon` (Windows).

```bash
# Voir les logs
docker compose -f /opt/epsilon/docker-compose.yml logs -f epsilon

# Arrêter
docker compose -f /opt/epsilon/docker-compose.yml down

# Redémarrer
docker compose -f /opt/epsilon/docker-compose.yml up -d
```

---

## Mises à jour

Les mises à jour se déclenchent **depuis l'administration d'EPSILON** (module *Plateforme*) — pas besoin de relancer l'installation. EPSILON se met à jour lui-même et redémarre sans perdre vos données.

---

## Support

Pour obtenir un token d'accès ou en cas de problème, contactez votre fournisseur EPSILON.
