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
#  container-engine.sh — Détection du moteur de conteneurs
#
#  Bibliothèque sourcée par install.sh et prom.sh, pour que les deux scripts
#  s'accordent sur le moteur à utiliser. Trois moteurs peuvent être présents :
#
#    docker     Docker Engine / Docker Desktop        → docker compose
#    podman     Podman (rootless, machine sur macOS)  → podman compose
#    container  Moteur natif d'Apple (macOS 26+)      → plugin compose tiers
#
#  Le moteur d'Apple n'embarque pas de compose : la demande a été écartée en
#  amont (apple/container#239), les mainteneurs renvoyant vers le mécanisme de
#  plugins installés sous /usr/local/libexec/container/plugins. Des plugins
#  tiers fournissent bien `container compose` — ce moteur n'est donc pas rejeté
#  a priori : on teste si un tel plugin répond.
#
#  Deux réserves quand il est retenu :
#    - les verbes de plugins n'apparaissent que services démarrés
#      (`container system start`) ; sinon la CLI répond « Plugins are
#      unavailable » à toute sous-commande inconnue, ce qui ne dit rien de la
#      présence effective d'un compose ;
#    - ces plugins réimplémentent la spécification Compose partiellement, or la
#      pile dépend de `depends_on: condition: service_healthy` pour séquencer
#      garage-config → garage → garage-init.
#
#  Compatible bash 3.2 (bash par défaut de macOS) : pas de tableaux.
#
#  Variables définies par ce_detect :
#    CE_ENGINE        docker | podman
#    CE_ENGINE_LABEL  libellé lisible
#    CE_COMPOSE       commande compose complète ("podman compose", …)
#    CE_FOUND         moteurs détectés, séparés par des espaces
#    CE_ERROR         message d'erreur si la détection échoue
# =============================================================================

CE_ENGINE=""
CE_ENGINE_LABEL=""
CE_COMPOSE=""
CE_FOUND=""
CE_ERROR=""
# Vaut 1 quand le moteur retenu est « container » via un plugin compose tiers :
# les appelants avertissent alors du caractère partiel de l'implémentation.
CE_CONTAINER_PLUGIN=0

ce_has() { command -v "$1" >/dev/null 2>&1; }

# ce_in_found <nom> — le moteur figure-t-il parmi ceux détectés ?
ce_in_found() {
    case " $CE_FOUND " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

# ce_scan — recense les moteurs installés dans CE_FOUND
ce_scan() {
    CE_FOUND=""
    ce_has docker    && CE_FOUND="$CE_FOUND docker"
    ce_has podman    && CE_FOUND="$CE_FOUND podman"
    ce_has container && CE_FOUND="$CE_FOUND container"
    # Normalise les espaces de tête/fin
    CE_FOUND="$(printf '%s' "$CE_FOUND" | sed 's/^ *//; s/ *$//')"
    [ -n "$CE_FOUND" ]
}

# ce_detect [moteur_imposé] — choisit le moteur et son orchestrateur compose.
# Renvoie 0 si utilisable, 1 sinon (CE_ERROR renseigné).
ce_detect() {
    local force="${1:-}"

    CE_ENGINE=""; CE_ENGINE_LABEL=""; CE_COMPOSE=""; CE_ERROR=""; CE_CONTAINER_PLUGIN=0
    ce_scan || {
        CE_ERROR="Aucun moteur de conteneurs détecté. Installez Podman (brew install podman) ou Docker Desktop."
        return 1
    }

    if [ -n "$force" ]; then
        ce_in_found "$force" || {
            CE_ERROR="Moteur '$force' introuvable sur cette machine. Détecté(s) : $CE_FOUND"
            return 1
        }
        CE_ENGINE="$force"
    else
        # Docker d'abord (le plus courant), Podman ensuite, le moteur d'Apple en
        # dernier recours puisqu'il dépend d'un plugin compose tiers.
        if ce_in_found docker; then
            CE_ENGINE="docker"
        elif ce_in_found podman; then
            CE_ENGINE="podman"
        elif ce_in_found container; then
            CE_ENGINE="container"
        fi
    fi

    if [ -z "$CE_ENGINE" ]; then
        CE_ERROR="Aucun moteur utilisable. Installez Podman (brew install podman && podman machine init && podman machine start) ou Docker Desktop."
        return 1
    fi

    case "$CE_ENGINE" in
        docker)
            CE_ENGINE_LABEL="Docker"
            if docker compose version >/dev/null 2>&1; then
                CE_COMPOSE="docker compose"
            elif ce_has docker-compose; then
                # Piège classique sous Debian/Ubuntu : « apt install
                # docker-compose » installe la v1 (Python), abandonnée. Or
                # docker-compose.yml suit la Compose Specification (aucune clé
                # version:) et repose sur
                # depends_on: condition: service_completed_successfully, que la
                # v1 ne sait pas interpréter. Mieux vaut refuser franchement que
                # laisser la pile échouer de façon illisible.
                _ce_dcv="$(docker-compose version --short 2>/dev/null || docker-compose --version 2>/dev/null || true)"
                case "$_ce_dcv" in
                    1.*|*"version 1."*)
                        CE_ERROR="Seul docker-compose v1 est installé ($_ce_dcv). Cette version ne sait pas interpréter ce fichier compose, qui suit la Compose Specification et séquence les services via 'depends_on: condition: service_completed_successfully'. Installez le plugin Compose v2 — sous Debian/Ubuntu : 'apt install docker-compose-plugin' — puis relancez."
                        return 1
                        ;;
                esac
                CE_COMPOSE="docker-compose"
            else
                CE_ERROR="Docker est présent mais Docker Compose est introuvable. Installez le plugin v2 : https://docs.docker.com/compose/install/"
                return 1
            fi
            ;;
        container)
            CE_ENGINE_LABEL="container (Apple)"
            if ! container system status >/dev/null 2>&1; then
                CE_ERROR="Le moteur « container » d'Apple est installé mais ses services ne tournent pas. Lancez 'container system start' puis relancez. Attention : container n'embarque pas de compose, il faut qu'un plugin tiers y soit installé (par exemple https://github.com/container-compose/compose)."
                return 1
            fi
            if container compose --help >/dev/null 2>&1; then
                CE_COMPOSE="container compose"
                CE_CONTAINER_PLUGIN=1
            else
                CE_ERROR="Le moteur « container » d'Apple tourne, mais aucun plugin compose n'y est installé : Apple a écarté le compose natif (apple/container#239) et renvoie vers les plugins. Installez-en un (https://github.com/container-compose/compose), ou utilisez Podman / Docker."
                return 1
            fi
            ;;
        podman)
            CE_ENGINE_LABEL="Podman"
            # `podman compose` délègue à un provider externe et annonce à chaque
            # appel quel binaire il utilise ; cette bannière n'apporte rien ici.
            export PODMAN_COMPOSE_WARNING_LOGS=false
            if podman compose version >/dev/null 2>&1; then
                CE_COMPOSE="podman compose"
            elif ce_has podman-compose; then
                CE_COMPOSE="podman-compose"
            else
                CE_ERROR="Podman est présent mais aucun orchestrateur compose ne l'accompagne. Installez docker-compose (brew install docker-compose), que 'podman compose' utilisera automatiquement, ou podman-compose (pip install podman-compose)."
                return 1
            fi
            ;;
    esac

    return 0
}

# ce_engine_ready — le moteur répond-il ? CE_ERROR renseigné sinon.
ce_engine_ready() {
    CE_ERROR=""
    if [ "$CE_ENGINE" = "container" ]; then
        container system status >/dev/null 2>&1 && return 0
    elif "$CE_ENGINE" info >/dev/null 2>&1; then
        return 0
    fi
    case "$CE_ENGINE" in
        container)
            CE_ERROR="Le moteur « container » d'Apple ne répond pas. Lancez 'container system start' puis relancez."
            ;;
        podman)
            # Sur macOS, Podman passe par une machine virtuelle qui doit tourner.
            if podman machine list >/dev/null 2>&1; then
                CE_ERROR="Podman ne répond pas : la machine n'est probablement pas démarrée. Lancez 'podman machine start' puis relancez."
            else
                CE_ERROR="Podman ne répond pas. Vérifiez l'installation, puis 'podman machine init && podman machine start' sur macOS."
            fi
            ;;
        docker)
            CE_ERROR="Le démon Docker ne répond pas. Démarrez Docker Desktop (ou 'sudo systemctl start docker') puis relancez."
            ;;
    esac
    return 1
}

# ce_version — version courte du moteur retenu
ce_version() {
    "$CE_ENGINE" --version 2>/dev/null | head -n1
}

# ce_compose_version — version de l'orchestrateur compose retenu
ce_compose_version() {
    $CE_COMPOSE version 2>/dev/null | head -n1
}

# ce_others — moteurs détectés mais non retenus (chaîne vide si aucun)
ce_others() {
    local e out=""
    for e in $CE_FOUND; do
        [ "$e" = "$CE_ENGINE" ] && continue
        out="$out $e"
    done
    printf '%s' "$(printf '%s' "$out" | sed 's/^ *//; s/ *$//')"
}
