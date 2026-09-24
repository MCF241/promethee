#!/usr/bin/env bash
# =============================================================================
#  Prométhée — Assistant IA avancé
# =============================================================================
#  Auteur  : Pierre COUGET ktulu.analog@gmail.com
#  Licence : GNU Affero General Public License v3.0 (AGPL-3.0)
#            https://www.gnu.org/licenses/agpl-3.0.html
#  Année   : 2026
# -----------------------------------------------------------------------------
#  Ce fichier fait partie du projet Prométhée.
#  Vous pouvez le redistribuer et/ou le modifier selon les termes de la
#  licence AGPL-3.0 publiée par la Free Software Foundation.
# =============================================================================
#
#  install.sh — Installation guidée de la pile de conteneurs
#
#  Automatise la procédure de documentation/promethee_guide_installation.pdf :
#  prérequis, génération des secrets, récupération du GARAGE_NODE_ID (l'étape
#  manuelle la plus délicate), puis démarrage et vérification de la pile.
#
#  Le moteur de conteneurs est détecté automatiquement via
#  scripts/container-engine.sh : Docker, sinon Podman, sinon le moteur natif
#  d'Apple (« container ») — ce dernier seulement s'il a reçu un plugin compose
#  tiers, Apple n'en fournissant pas.
#
#  Deux modes :
#    local    — l'application n'écoute que sur 127.0.0.1, pour un poste de
#               travail personnel.
#    serveur  — l'application écoute sur toutes les interfaces, pour une
#               instance partagée, derrière un reverse proxy le cas échéant.
#
#  Le mode ne change pas l'image construite : depuis frontend/src/lib/config.ts,
#  le frontend émet des URL relatives et suit donc l'origine sur laquelle il est
#  servi. Il ne joue que sur l'adresse d'écoute, le port et la documentation
#  affichée en fin d'installation.
#
#  Usage : ./install.sh [options]   (./install.sh --help pour le détail)
# =============================================================================

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Détection du moteur de conteneurs ─────────────────────────────────────────
if [[ ! -f scripts/container-engine.sh ]]; then
    printf "Erreur : scripts/container-engine.sh introuvable. Lancez ce script depuis la racine du dépôt.\n" >&2
    exit 1
fi
# shellcheck source=scripts/container-engine.sh
source scripts/container-engine.sh

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers d'affichage ───────────────────────────────────────────────────────
info()    { printf "%b\n" "${BLUE}[INFO]${NC}  $*"; }
success() { printf "%b\n" "${GREEN}[OK]${NC}    $*"; }
warn()    { printf "%b\n" "${YELLOW}[WARN]${NC}  $*"; }
error()   { printf "%b\n" "${RED}[ERR]${NC}   $*" >&2; }
header()  { printf "%b\n" "\n${BOLD}${CYAN}▶ $*${NC}"; }
die()     { error "$*"; exit 1; }

# ── Options ───────────────────────────────────────────────────────────────────
MODE=""
PORT=""
DOMAINE=""
ASSUME_YES=0
DO_START=1
REINSTALL=0
MOTEUR=""
ENGINE=""

ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yml"
GARAGE_CONTAINER="promethee-garage"
APP_CONTAINER="promethee-app"

usage() {
    local B="$BOLD" C="$CYAN" N="$NC"
    printf "\n"
    printf "%b\n" "${B}install.sh${N} — Installation guidée de la pile de conteneurs Prométhée"
    printf "\n"
    printf "%b\n" "${B}USAGE${N}"
    printf "  ./install.sh [options]\n"
    printf "\n"
    printf "%b\n" "${B}OPTIONS${N}"
    printf "  %b\n" "${C}--mode${N} local|serveur"
    printf "      local   → l'application n'écoute que sur 127.0.0.1 (poste personnel)\n"
    printf "      serveur → l'application écoute sur 0.0.0.0 (instance partagée)\n"
    printf "      Sans cette option, le mode est demandé de façon interactive.\n"
    printf "\n"
    printf "  %b\n" "${C}--port${N} <numéro>"
    printf "      Port exposé sur l'hôte (défaut : 8000).\n"
    printf "\n"
    printf "  %b\n" "${C}--domaine${N} <url>"
    printf "      Mode serveur : URL publique de l'instance, par exemple\n"
    printf "      https://promethee.example.org. Sert à renseigner ALLOWED_ORIGINS\n"
    printf "      et à afficher la bonne adresse en fin d'installation.\n"
    printf "\n"
    printf "  %b\n" "${C}--moteur${N} docker|podman|container"
    printf "      Force le moteur de conteneurs. Par défaut il est détecté\n"
    printf "      automatiquement : Docker, sinon Podman, sinon le moteur d'Apple\n"
    printf "      (ce dernier exigeant un plugin compose tiers).\n"
    printf "\n"
    printf "  %b\n" "${C}--reinstall${N}"
    printf "      Repart d'un .env neuf. L'ancien est sauvegardé horodaté.\n"
    printf "\n"
    printf "  %b\n" "${C}--no-start${N}"
    printf "      S'arrête après la préparation du .env et du GARAGE_NODE_ID,\n"
    printf "      sans construire ni démarrer la pile complète.\n"
    printf "\n"
    printf "  %b\n" "${C}-y, --yes${N}"
    printf "      Non interactif : accepte les valeurs par défaut. --mode devient\n"
    printf "      alors obligatoire.\n"
    printf "\n"
    printf "  %b\n" "${C}-h, --help${N}"
    printf "      Affiche cette aide.\n"
    printf "\n"
    printf "%b\n" "${B}EXEMPLES${N}"
    printf "  ./install.sh                                      # installation interactive\n"
    printf "  ./install.sh --mode local -y                      # poste personnel, sans question\n"
    printf "  ./install.sh --mode serveur --domaine https://ia.exemple.fr -y\n"
    printf "  ./install.sh --mode local --no-start              # préparer .env sans démarrer\n"
    printf "\n"
    printf "%b\n" "${B}VOIR AUSSI${N}"
    printf "  documentation/promethee_guide_installation.pdf    # procédure détaillée\n"
    printf "  ./prom.sh help                                    # gestion de la pile au quotidien\n"
    printf "\n"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)       MODE="${2:-}";    shift 2 ;;
        --mode=*)     MODE="${1#*=}";   shift   ;;
        --port)       PORT="${2:-}";    shift 2 ;;
        --port=*)     PORT="${1#*=}";   shift   ;;
        --domaine|--domain)   DOMAINE="${2:-}";  shift 2 ;;
        --domaine=*|--domain=*) DOMAINE="${1#*=}"; shift ;;
        --moteur|--engine)     MOTEUR="${2:-}";  shift 2 ;;
        --moteur=*|--engine=*) MOTEUR="${1#*=}"; shift   ;;
        --reinstall)  REINSTALL=1;      shift   ;;
        --no-start)   DO_START=0;       shift   ;;
        -y|--yes)     ASSUME_YES=1;     shift   ;;
        -h|--help)    usage; exit 0             ;;
        *)            error "Option inconnue : $1"; usage; exit 1 ;;
    esac
done

# Sans terminal interactif (pipe, CI), on ne peut rien demander.
if [[ ! -t 0 ]] && [[ "$ASSUME_YES" -eq 0 ]]; then
    ASSUME_YES=1
    warn "Entrée non interactive détectée — passage en mode --yes."
fi

if [[ -n "$MOTEUR" && "$MOTEUR" != "docker" && "$MOTEUR" != "podman" && "$MOTEUR" != "container" ]]; then
    die "Moteur invalide : '$MOTEUR'. Valeurs acceptées : docker, podman, container."
fi
if [[ -n "$MODE" && "$MODE" != "local" && "$MODE" != "serveur" ]]; then
    die "Mode invalide : '$MODE'. Valeurs acceptées : local, serveur."
fi
if [[ "$ASSUME_YES" -eq 1 && -z "$MODE" ]]; then
    die "En mode non interactif, --mode local|serveur est obligatoire."
fi

# ── Helpers de saisie ─────────────────────────────────────────────────────────

# ask <nom_variable> <question> [défaut]
ask() {
    local __var="$1" __q="$2" __def="${3:-}" __ans=""
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        printf -v "$__var" '%s' "$__def"
        return 0
    fi
    if [[ -n "$__def" ]]; then
        read -r -p "$(printf "%b" "${CYAN}?${NC} ${__q} [${__def}] : ")" __ans || true
    else
        read -r -p "$(printf "%b" "${CYAN}?${NC} ${__q} : ")" __ans || true
    fi
    [[ -z "$__ans" ]] && __ans="$__def"
    printf -v "$__var" '%s' "$__ans"
}

# ask_secret <nom_variable> <question> [défaut] — saisie masquée
ask_secret() {
    local __var="$1" __q="$2" __def="${3:-}" __ans=""
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        printf -v "$__var" '%s' "$__def"
        return 0
    fi
    local __hint="laisser vide pour conserver la valeur actuelle"
    [[ -z "$__def" ]] && __hint="laisser vide pour renseigner plus tard"
    read -r -s -p "$(printf "%b" "${CYAN}?${NC} ${__q} (${__hint}) : ")" __ans || true
    printf "\n"
    [[ -z "$__ans" ]] && __ans="$__def"
    printf -v "$__var" '%s' "$__ans"
}

# confirm <question> [o|n] — défaut appliqué en mode non interactif
confirm() {
    local q="$1" def="${2:-o}" ans="" prompt="[o/N]"
    [[ "$def" == "o" ]] && prompt="[O/n]"
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        [[ "$def" == "o" ]] && return 0 || return 1
    fi
    read -r -p "$(printf "%b" "${CYAN}?${NC} ${q} ${prompt} : ")" ans || true
    [[ -z "$ans" ]] && ans="$def"
    case "$ans" in
        o|O|oui|Oui|OUI|y|Y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Helpers .env ──────────────────────────────────────────────────────────────

# get_env <clé> — valeur courante, chaîne vide si absente
get_env() {
    [[ -f "$ENV_FILE" ]] || return 0
    grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

# set_env <clé> <valeur> — remplace la ligne existante, l'ajoute sinon.
# Passe par ENVIRON pour qu'aucun caractère de la valeur (/, &, \) ne soit
# réinterprété, contrairement à un sed.
set_env() {
    local key="$1" value="$2" tmp
    tmp="$(mktemp)"
    KEY="$key" VALUE="$value" awk '
        BEGIN { key = ENVIRON["KEY"]; value = ENVIRON["VALUE"]; done = 0 }
        !done && index($0, key "=") == 1 { print key "=" value; done = 1; next }
        { print }
        END { if (!done) print key "=" value }
    ' "$ENV_FILE" > "$tmp"
    mv "$tmp" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

gen_hex()        { openssl rand -hex "${1:-32}"; }
gen_access_key() { printf 'GK%s' "$(openssl rand -hex 12)"; }

# ── Helpers Docker ────────────────────────────────────────────────────────────

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# port_busy <port> → 0 occupé, 1 libre, 2 indéterminé
port_busy() {
    local p="$1"
    if need_cmd lsof; then
        lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && return 0 || return 1
    elif need_cmd ss; then
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}\$" && return 0 || return 1
    elif need_cmd nc; then
        nc -z 127.0.0.1 "$p" >/dev/null 2>&1 && return 0 || return 1
    fi
    return 2
}

# wait_healthy <conteneur> [timeout_s] — attend healthy, ou running si le
# conteneur n'a pas de healthcheck déclaré.
wait_healthy() {
    local name="$1" timeout="${2:-180}" waited=0 status=""
    while [[ "$waited" -lt "$timeout" ]]; do
        status="$($ENGINE inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || true)"
        case "$status" in
            healthy|running) printf "\n"; return 0 ;;
            exited|dead)     printf "\n"; return 1 ;;
        esac
        printf "."
        sleep 3
        waited=$((waited + 3))
    done
    printf "\n"
    return 1
}

# ── Avertissement préalable ───────────────────────────────────────────────────
# Prométhée n'existe pas en version autonome : la pile compte cinq services qui
# doivent être orchestrés. On l'annonce avant toute vérification technique, pour
# qu'un utilisateur non informaticien sache immédiatement ce qui est attendu de
# sa machine — et vers qui se tourner si la condition n'est pas remplie.
avertissement_prerequis() {
    printf "\n"
    printf "%b\n" "${BOLD}${YELLOW}⚠  Gestionnaire de conteneurs requis${NC}"
    printf "\n"
    printf "%s\n" "Prométhée ne s'installe pas comme une application autonome. Il repose"
    printf "%s\n" "sur cinq services — l'application, une base vectorielle, un stockage de"
    printf "%s\n" "fichiers et deux services d'initialisation — qui doivent être démarrés"
    printf "%s\n" "dans le bon ordre par un gestionnaire de conteneurs."
    printf "\n"
    printf "%s\n" "L'un des trois suivants doit donc être installé sur cette machine :"
    printf "\n"
    printf "%b\n" "   • ${BOLD}Docker${NC} — Docker Desktop ou Docker Engine"
    printf "%b\n" "   • ${BOLD}Podman${NC}"
    printf "%b\n" "   • ${BOLD}container${NC} — le moteur d'Apple (macOS 26+), muni d'un plugin compose"
    printf "\n"
    printf "%s\n" "Leur installation demande des droits d'administrateur. Le présent script,"
    printf "%s\n" "lui, n'en demande aucun : il ne fait qu'utiliser le gestionnaire en place."
    printf "\n"

    confirm "Poursuivre l'installation ?" "o" && return 0

    printf "\n"
    printf "%b\n" "${BOLD}Installation interrompue.${NC}"
    printf "\n"
    printf "%s\n" "Rapprochez-vous de votre administrateur système ou de votre service"
    printf "%s\n" "informatique. Demandez-leur d'installer l'un des trois gestionnaires"
    printf "%s\n" "ci-dessus sur cette machine, puis relancez :"
    printf "\n"
    printf "%b\n" "   ${BOLD}./install.sh${NC}"
    printf "\n"
    printf "%s\n" "Le guide documentation/guide_installation_script.md décrit la marche à"
    printf "%s\n" "suivre et peut leur être transmis tel quel."
    printf "\n"
    exit 0
}

# ── Étape 1 — Prérequis ───────────────────────────────────────────────────────
step_prerequis() {
    header "Étape 1/5 — Vérification des prérequis"

    [[ -f "$COMPOSE_FILE" ]] || die "$COMPOSE_FILE introuvable. Lancez ce script depuis la racine du dépôt."
    [[ -f ".env.example" ]]  || die ".env.example introuvable. Le dépôt semble incomplet."

    ce_detect "$MOTEUR" || die "$CE_ERROR"
    ENGINE="$CE_ENGINE"
    DC="$CE_COMPOSE"
    success "Moteur : ${BOLD}${CE_ENGINE_LABEL}${NC} — $(ce_version)"
    success "Compose : ${BOLD}${DC}${NC} — $(ce_compose_version)"

    local autres
    autres="$(ce_others)"
    if [[ -n "$autres" ]]; then
        info "Également installé(s) sur la machine : $autres"
        case " $autres " in
            *" container "*)
                info "Le moteur d'Apple n'embarque pas de compose : il exige un plugin tiers pour monter cette pile." ;;
        esac
        [[ -z "$MOTEUR" ]] && info "Pour imposer un autre moteur : ./install.sh --moteur <nom>"
    fi

    ce_engine_ready || die "$CE_ERROR"
    success "${CE_ENGINE_LABEL} opérationnel"

    # Les plugins compose du moteur d'Apple sont des réimplémentations tierces,
    # et la pile repose entièrement sur le séquencement par healthcheck.
    if [[ "$CE_CONTAINER_PLUGIN" -eq 1 ]]; then
        warn "Compose est ici fourni par un plugin tiers du moteur d'Apple."
        warn "La pile séquence garage-config → garage → garage-init via"
        warn "'depends_on: condition: service_healthy'. Si le plugin n'honore pas"
        warn "cette condition, garage-init démarrera trop tôt et échouera."
        confirm "Continuer avec ce moteur ?" "n" || die "Installation interrompue. Podman ou Docker restent les moteurs éprouvés."
    fi

    need_cmd openssl || die "openssl est introuvable : il est nécessaire pour générer les secrets."
    success "openssl présent"

    need_cmd curl || warn "curl est absent : la vérification HTTP finale sera ignorée."

    # Podman sur macOS exécute les conteneurs dans une machine virtuelle. Le
    # dépôt doit y être visible, sinon le bind-mount de garage.toml (attendu par
    # garage-config) produira un fichier vide et Garage ne démarrera jamais.
    if [[ "$ENGINE" == "podman" && "$(uname -s)" == "Darwin" ]]; then
        if $ENGINE run --rm -v "$PWD:/probe:ro" alpine:3.19 test -s /probe/garage.toml >/dev/null 2>&1; then
            success "Le dépôt est accessible depuis la machine Podman"
        else
            error "Le dépôt n'est pas accessible depuis la machine Podman :"
            error "  $PWD"
            error "La machine Podman ne monte par défaut que votre dossier personnel."
            error "Déplacez le dépôt sous \$HOME, ou ajoutez le chemin au montage :"
            error "  podman machine stop"
            error "  podman machine set --volume $PWD:$PWD"
            error "  podman machine start"
            die "Installation interrompue."
        fi
    fi
}

# ── Étape 2 — Choix du mode ───────────────────────────────────────────────────
step_mode() {
    header "Étape 2/5 — Mode d'installation"

    if [[ -z "$MODE" ]]; then
        printf "\n"
        printf "%b\n" "  ${BOLD}1) local${NC}   — poste de travail personnel"
        printf "%s\n" "     L'application n'écoute que sur 127.0.0.1 : elle n'est joignable"
        printf "%s\n" "     que depuis cette machine. Rien n'est exposé sur le réseau."
        printf "\n"
        printf "%b\n" "  ${BOLD}2) serveur${NC} — instance partagée"
        printf "%s\n" "     L'application écoute sur toutes les interfaces et devient joignable"
        printf "%s\n" "     depuis le réseau, directement ou derrière un reverse proxy."
        printf "\n"
        local choix=""
        while [[ "$MODE" != "local" && "$MODE" != "serveur" ]]; do
            ask choix "Mode d'installation (1 ou 2)" "1"
            case "$choix" in
                1|local|locale)  MODE="local" ;;
                2|serveur|server) MODE="serveur" ;;
                *) warn "Réponse non comprise : tapez 1 ou 2." ;;
            esac
        done
    fi

    if [[ "$MODE" == "local" ]]; then
        BIND_ADDRESS="127.0.0.1"
    else
        BIND_ADDRESS="0.0.0.0"
    fi

    [[ -z "$PORT" ]] && ask PORT "Port d'écoute de l'application sur l'hôte" "8000"
    [[ "$PORT" =~ ^[0-9]+$ ]] || die "Port invalide : '$PORT'."
    [[ "$PORT" -ge 1 && "$PORT" -le 65535 ]] || die "Port hors plage : '$PORT'."

    if [[ "$MODE" == "serveur" && -z "$DOMAINE" ]]; then
        ask DOMAINE "URL publique de l'instance (laisser vide si accès par IP)" ""
    fi
    DOMAINE="${DOMAINE%/}"

    if [[ -n "$DOMAINE" ]]; then
        PUBLIC_URL="$DOMAINE"
    elif [[ "$MODE" == "local" ]]; then
        PUBLIC_URL="http://localhost:${PORT}"
    else
        PUBLIC_URL="http://$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "adresse-du-serveur"):${PORT}"
    fi

    success "Mode ${BOLD}${MODE}${NC} — écoute sur ${BIND_ADDRESS}:${PORT}"

    # Ports requis par la pile. Qdrant et Garage restent sur 127.0.0.1 quel que
    # soit le mode : seule l'application est exposée.
    local p occupe=0
    for p in "$PORT" 6333 6334 3900 3901; do
        if port_busy "$p"; then
            warn "Le port $p est déjà occupé."
            occupe=1
        fi
    done
    if [[ "$occupe" -eq 1 ]]; then
        warn "S'il s'agit d'une instance Prométhée déjà lancée, c'est normal — elle sera reconfigurée."
        confirm "Continuer malgré tout ?" "o" || die "Installation interrompue."
    else
        success "Ports 8000/6333/6334/3900/3901 disponibles"
    fi
}

# ── Étape 3 — Fichier .env ────────────────────────────────────────────────────

# cle_api_absente — message affiché quand l'utilisateur n'a pas encore sa clé.
# L'installation se poursuit : la pile se monte, seul le chat reste muet. On
# marque une pause pour que la consigne soit lue avant le défilement des logs.
cle_api_absente() {
    printf "\n"
    printf "%b\n" "${BOLD}${YELLOW}L'installation continue sans clé d'API.${NC}"
    printf "\n"
    printf "%s\n" "Tout sera installé et démarré normalement, mais le chat restera sans"
    printf "%s\n" "réponse tant qu'une clé n'aura pas été renseignée."
    printf "\n"
    printf "%b\n" "${BOLD}À faire plus tard, en trois étapes :${NC}"
    printf "\n"
    printf "%s\n" "  1. Obtenir une clé auprès de votre fournisseur."
    printf "%s\n" "     Albert (service public) : https://albert.api.etalab.gouv.fr"
    printf "%s\n" "  2. L'inscrire dans le fichier .env, à la ligne :"
    printf "%b\n" "        ${BOLD}OPENAI_API_KEY=votre-clé${NC}"
    printf "%s\n" "  3. Appliquer la modification :"
    printf "%b\n" "        ${BOLD}./prom.sh up promethee${NC}"
    printf "\n"
    printf "%s\n" "Utilisez bien 'up' et non 'restart' : un redémarrage simple ne relit"
    printf "%s\n" "pas le fichier .env."
    printf "\n"
    printf "%s\n" "Cette marche à suivre est reprise au chapitre 6 du guide"
    printf "%s\n" "documentation/guide_installation_script.md."
    printf "\n"

    # Pause de lecture, sautée en mode non interactif pour ne pas ralentir la CI.
    if [[ "$ASSUME_YES" -eq 0 ]]; then
        printf "%b" "${CYAN}Reprise de l'installation dans ${NC}"
        local n
        for n in 8 7 6 5 4 3 2 1; do printf "%b" "${BOLD}${n}${NC} "; sleep 1; done
        printf "\n\n"
    fi
}

# ensure_secret <clé> <fonction_de_génération> <libellé>
ensure_secret() {
    local key="$1" gen="$2" label="$3" cur
    cur="$(get_env "$key")"
    if [[ -z "$cur" || "$cur" == "changez-moi-en-production" ]]; then
        set_env "$key" "$("$gen")"
        success "$label généré"
    else
        info "$label déjà renseigné — conservé"
    fi
}

step_env() {
    header "Étape 3/5 — Configuration (.env)"

    if [[ -f "$ENV_FILE" ]]; then
        if [[ "$REINSTALL" -eq 1 ]]; then
            local backup=".env.bak.$(date +%Y%m%d-%H%M%S)"
            cp "$ENV_FILE" "$backup"
            chmod 600 "$backup"
            warn "Ancien .env sauvegardé dans $backup"
            cp .env.example "$ENV_FILE"
            success "Nouveau .env créé depuis .env.example"
        else
            info ".env existant conservé — seules les valeurs manquantes sont complétées."
            info "Pour repartir d'un fichier neuf : ./install.sh --reinstall"
        fi
    else
        cp .env.example "$ENV_FILE"
        success ".env créé depuis .env.example"
    fi
    chmod 600 "$ENV_FILE"

    # Secrets — générés une seule fois, jamais écrasés silencieusement.
    ensure_secret PROMETHEE_SECRET_KEY gen_hex        "PROMETHEE_SECRET_KEY (clé JWT)"
    ensure_secret GARAGE_RPC_SECRET    gen_hex        "GARAGE_RPC_SECRET"
    ensure_secret GARAGE_SECRET_KEY    gen_hex        "GARAGE_SECRET_KEY (secret S3)"
    ensure_secret GARAGE_ACCESS_KEY    gen_access_key "GARAGE_ACCESS_KEY (identifiant S3)"

    # Garage refuse tout identifiant hors format GK + 24 hex.
    local access_key
    access_key="$(get_env GARAGE_ACCESS_KEY)"
    if [[ ! "$access_key" =~ ^GK[0-9a-f]{24}$ ]]; then
        warn "GARAGE_ACCESS_KEY ne respecte pas le format attendu (GK + 24 hex)."
        if confirm "Régénérer un identifiant valide ?" "o"; then
            set_env GARAGE_ACCESS_KEY "$(gen_access_key)"
            success "GARAGE_ACCESS_KEY régénéré"
        fi
    fi

    [[ -z "$(get_env GARAGE_BUCKET)" ]] && set_env GARAGE_BUCKET "promethee-vfs"

    # Réseau — dépend du mode choisi.
    set_env SERVER_PORT   "$PORT"
    set_env BIND_ADDRESS  "$BIND_ADDRESS"
    # Same-origin : FastAPI sert la SPA, CORS n'est pas déclenché. On aligne
    # tout de même la valeur sur l'origine réelle, utile si le frontend venait
    # à être servi séparément.
    set_env ALLOWED_ORIGINS "[\"${PUBLIC_URL}\"]"
    success "Réseau configuré — SERVER_PORT=$PORT, BIND_ADDRESS=$BIND_ADDRESS"

    # LLM — sans clé API, l'application démarre mais ne répond pas.
    printf "\n"
    info "Configuration du modèle de langage (modifiable plus tard dans .env)"

    # On demande d'abord si la clé est disponible : sans elle, inutile
    # d'enchaîner des questions auxquelles l'utilisateur ne peut pas répondre.
    if [[ -n "$(get_env OPENAI_API_KEY)" ]] || confirm "Disposez-vous déjà d'une clé d'API pour le modèle de langage ?" "o"; then
        local api_base api_key api_model
        ask        api_base  "URL du serveur LLM"  "$(get_env OPENAI_API_BASE)"
        ask_secret api_key   "Clé API du LLM"      "$(get_env OPENAI_API_KEY)"
        ask        api_model "Modèle à utiliser"   "$(get_env OPENAI_MODEL)"
        [[ -n "$api_base"  ]] && set_env OPENAI_API_BASE "$api_base"
        [[ -n "$api_key"   ]] && set_env OPENAI_API_KEY  "$api_key"
        [[ -n "$api_model" ]] && set_env OPENAI_MODEL    "$api_model"
    else
        cle_api_absente
    fi

    if [[ -z "$(get_env OPENAI_API_KEY)" ]]; then
        warn "OPENAI_API_KEY est vide : l'application démarrera, mais le chat restera sans réponse."
        warn "Renseignez-la dans .env puis relancez : ./prom.sh up promethee"
    else
        success "Modèle de langage configuré"
    fi
}

# ── Étape 4 — GARAGE_NODE_ID ──────────────────────────────────────────────────
# Étape critique du guide : Garage génère lui-même son identifiant au premier
# démarrage, et garage-init refuse de s'exécuter tant qu'il n'est pas connu.
step_node_id() {
    header "Étape 4/5 — Identifiant du nœud Garage"

    local actuel
    actuel="$(get_env GARAGE_NODE_ID)"

    info "Démarrage du service Garage seul…"
    $DC up -d garage || die "Impossible de démarrer Garage. Diagnostiquez avec : $DC logs garage"

    info "Attente du statut healthy (généralement moins d'une minute)"
    wait_healthy "$GARAGE_CONTAINER" 180 \
        || die "Garage n'est pas devenu healthy. Diagnostiquez avec : $DC logs garage"
    success "Garage est healthy"

    # La sortie est de la forme <64 hex>@garage:3901 ; on ne garde que l'hex.
    local node_id
    node_id="$($ENGINE exec "$GARAGE_CONTAINER" /garage -c /etc/garage/garage.toml node id 2>/dev/null \
               | grep -oE '[0-9a-f]{64}' | head -n1 || true)"

    [[ -n "$node_id" ]] || die "Impossible de lire le Node ID. Essayez manuellement : $ENGINE exec $GARAGE_CONTAINER /garage -c /etc/garage/garage.toml node id"

    if [[ -n "$actuel" && "$actuel" != "$node_id" ]]; then
        warn "Le GARAGE_NODE_ID de .env ne correspond pas au nœud en cours d'exécution :"
        warn "  .env : $actuel"
        warn "  nœud : $node_id"
        warn "Cela arrive après suppression du volume garage_meta."
        if confirm "Mettre .env à jour avec l'identifiant du nœud ?" "o"; then
            set_env GARAGE_NODE_ID "$node_id"
            success "GARAGE_NODE_ID mis à jour"
        else
            warn "Valeur conservée — garage-init échouera probablement."
        fi
    else
        set_env GARAGE_NODE_ID "$node_id"
        success "GARAGE_NODE_ID = $node_id"
    fi
}

# ── Étape 5 — Démarrage et vérification ───────────────────────────────────────
step_demarrage() {
    header "Étape 5/5 — Construction et démarrage de la pile"

    info "Premier build : plusieurs minutes (frontend React, paquets Python, KaTeX, Mermaid)."
    $DC up -d --build || die "Le démarrage a échoué. Consultez les logs : $DC logs"

    info "Attente de l'application"
    if wait_healthy "$APP_CONTAINER" 300; then
        success "Application healthy"
    else
        warn "L'application n'est pas passée healthy dans le délai imparti."
        warn "Inspectez : $DC logs promethee"
    fi

    if need_cmd curl; then
        if curl -fsS --max-time 10 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
            success "Point de contrôle /health accessible sur le port $PORT"
        else
            warn "Le point de contrôle /health ne répond pas encore sur le port $PORT."
        fi
    fi

    printf "\n"
    $DC ps || true
}

# ── Récapitulatif ─────────────────────────────────────────────────────────────
recap() {
    printf "\n"
    printf "%b\n" "${BOLD}${GREEN}═══ Installation terminée ═══${NC}"
    printf "\n"
    printf "%b\n" "  ${BOLD}Application${NC}    ${PUBLIC_URL}"
    printf "%b\n" "  ${BOLD}Qdrant${NC}         http://localhost:6333/dashboard  (local uniquement)"
    printf "%b\n" "  ${BOLD}Garage S3${NC}      http://localhost:3900            (local uniquement)"
    printf "\n"
    printf "%b\n" "  ${BOLD}Premier accès${NC}"
    printf "%s\n" "    L'interface propose la création du compte administrateur au premier"
    printf "%s\n" "    lancement. Créez-le avant d'ouvrir l'accès à d'autres utilisateurs."
    printf "\n"

    if [[ "$MODE" == "serveur" ]]; then
        printf "%b\n" "  ${BOLD}${YELLOW}Mode serveur — à vérifier${NC}"
        printf "%s\n" "    • Le port ${PORT} est exposé sur toutes les interfaces : filtrez-le au"
        printf "%s\n" "      pare-feu si l'instance ne doit pas être publique."
        printf "%s\n" "    • Derrière un reverse proxy, relayez les en-têtes Upgrade et Connection,"
        printf "%s\n" "      faute de quoi le WebSocket du chat restera muet."
        printf "%s\n" "    • Sous HTTPS, le frontend bascule seul en wss:// — rien à reconstruire."
        printf "\n"
    fi

    printf "%b\n" "  ${BOLD}Au quotidien${NC}"
    printf "%s\n" "    ./prom.sh status          état des services"
    printf "%s\n" "    ./prom.sh logs promethee  logs de l'application"
    printf "%s\n" "    ./prom.sh restart         redémarrage"
    printf "\n"
    printf "%b\n" "  Secrets et configuration : ${BOLD}.env${NC} (permissions 600) — à ne jamais committer."
    printf "\n"
}

# ── Déroulé ───────────────────────────────────────────────────────────────────
main() {
    printf "\n"
    printf "%b\n" "${BOLD}${CYAN}Prométhée — installation de la pile de conteneurs${NC}"
    printf "%s\n" "Guide d'utilisation : documentation/guide_installation_script.md"

    avertissement_prerequis
    step_prerequis
    step_mode
    step_env
    step_node_id

    if [[ "$DO_START" -eq 0 ]]; then
        printf "\n"
        success "Préparation terminée (--no-start)."
        info "Pour démarrer la pile : $DC up -d --build"
        exit 0
    fi

    step_demarrage
    recap
}

main "$@"
