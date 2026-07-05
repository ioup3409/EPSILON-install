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

## Accès sécurisé (HTTPS)

Par défaut, EPSILON est servi en **HTTP** — parfait pour un réseau local de confiance. Vous pouvez passer en **HTTPS** (le cadenas de sécurité) sans certificat payant ni service externe : EPSILON génère sa **propre autorité de certification locale**, entièrement hors-ligne.

### 1. Activer le HTTPS

Depuis l'administration : **Réseau ▸ Certificats**.

1. **Générer le certificat** — EPSILON crée une autorité racine + un certificat serveur valable pour l'adresse IP et le nom du serveur.
2. **Activer HTTPS**, puis **redémarrer** EPSILON (l'activation initiale exige un redémarrage) :
   ```bash
   docker compose -f /opt/epsilon/docker-compose.yml restart epsilon   # Linux
   ```
   Sur Windows : `docker compose -f C:\epsilon\docker-compose.yml restart epsilon`.

Le HTTPS est alors servi sur le **port 443** ; le port HTTP (3000) redirige automatiquement vers lui.

> **Port déjà occupé ?** Si le port 443 est déjà utilisé sur le serveur, ajoutez une ligne `EPSILON_HTTPS_PORT=8443` (ou autre) dans le fichier `.env` du dossier d'installation, puis `docker compose up -d`.

### 2. Installer le certificat racine sur les postes clients

Comme l'autorité est locale (et non une autorité publique payante), chaque poste qui accède à EPSILON doit **faire confiance** au certificat racine — **une seule fois par poste**. Sans cela, le navigateur affichera un avertissement de sécurité.

Depuis **Réseau ▸ Certificats**, cliquez sur **« Télécharger le certificat racine »**, puis installez-le :

| Système | Où l'installer |
|---|---|
| **Windows** | Double-cliquer le fichier ▸ *Installer le certificat* ▸ **Utilisateur actuel** ▸ *Placer dans le magasin* : **Autorités de certification racines de confiance**. |
| **macOS** | Ouvrir dans **Trousseau d'accès** ▸ double-clic sur le certificat ▸ **Toujours approuver**. |
| **Linux** | Copier dans `/usr/local/share/ca-certificates/` puis `sudo update-ca-certificates`. |
| **iOS / Android** | Ouvrir le fichier ▸ installer le profil / les identifiants, puis l'activer dans *Réglages ▸ Certificats de confiance*. |

L'écran **Certificats** de l'administration affiche les instructions détaillées pour chaque système.

> **Chrome/Edge** mettent en cache la vérification TLS : après avoir installé le certificat, redémarrez complètement le navigateur (`chrome://restart`). **Firefox** utilise son propre magasin de certificats (à importer séparément si vous l'utilisez).

### Nom réseau `.local` — limitation sous Docker

EPSILON propose un nom de type `epsilon.local` (mDNS) pour accéder au serveur sans retenir son adresse IP. **Cette fonction ne fonctionne pas dans l'installation Docker** : la découverte mDNS repose sur du multicast réseau que le pont Docker ne laisse pas passer, et le mode « réseau hôte » qui le permettrait est incompatible avec le provisioning automatique des services d'EPSILON.

👉 **Accédez au serveur par son adresse IP** (ex: `https://192.168.1.20`). Pour un nom stable, réservez une IP fixe (bail DHCP) ou ajoutez une entrée DNS sur votre réseau. Le certificat généré couvre l'IP et le nom d'hôte du serveur.

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
