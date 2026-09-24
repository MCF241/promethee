#!/usr/bin/env bash
# =============================================================================
#  Prométhée — Assistant IA avancé
# =============================================================================
#  Auteur  : Pierre COUGET ktulu.analog@gmail.com
#  Licence : GNU Affero General Public License v3.0 (AGPL-3.0)
#  Année   : 2026
# -----------------------------------------------------------------------------
#  test_install.sh — Tests du script d'installation
#
#  Exercice à froid de la logique d'install.sh qui ne dépend ni d'un moteur de
#  conteneurs ni du réseau : manipulation du .env, génération des secrets,
#  extraction du Node ID Garage, choix du mode, idempotence.
#
#  Les étapes qui démarrent réellement des conteneurs (4 et 5) ne sont pas
#  couvertes ici : elles se vérifient par une installation réelle.
#
#  Usage : bash tests/test_install.sh        (depuis la racine du dépôt)
# =============================================================================
set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# install.sh se termine par `main "$@"` : on retire cette ligne pour pouvoir
# sourcer ses fonctions sans déclencher une installation.
sed '$d' "$RACINE/install.sh" > "$TMP/lib.sh"
mkdir -p "$TMP/scripts"
cp "$RACINE/scripts/container-engine.sh" "$TMP/scripts/"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf "  \033[0;32m✓\033[0m %s\n" "$1"; }
ko() { FAIL=$((FAIL+1)); printf "  \033[0;31m✗\033[0m %s\n     attendu : [%s]\n     obtenu  : [%s]\n" "$1" "$2" "$3"; }
eq() { [[ "$2" == "$3" ]] && ok "$1" || ko "$1" "$2" "$3"; }

cd "$TMP" || exit 1
set -- --mode local -y
# shellcheck disable=SC1091
source "$TMP/lib.sh" >/dev/null 2>&1
set +e   # lib.sh active `set -e` ; ce harnais teste des codes de retour

echo "── Manipulation du .env ──"
ENV_FILE="$TMP/t.env"
cat > "$ENV_FILE" <<'ENVEOF'
# commentaire
PROMETHEE_SECRET_KEY=
SERVER_PORT=8000
#GARAGE_NODE_ID=ancien-commente
ALLOWED_ORIGINS=["http://localhost:5173"]
ENVEOF
set_env SERVER_PORT 9443
eq "remplace une clé existante" "9443" "$(get_env SERVER_PORT)"
set_env BIND_ADDRESS 127.0.0.1
eq "ajoute une clé absente" "127.0.0.1" "$(get_env BIND_ADDRESS)"
eq "ligne commentée ignorée par get_env" "" "$(get_env GARAGE_NODE_ID)"
set_env GARAGE_NODE_ID abc123
eq "clé commentée non écrasée" "1" "$(grep -c '^#GARAGE_NODE_ID=ancien-commente$' "$ENV_FILE")"
eq "nouvelle clé ajoutée malgré l'homonyme commenté" "abc123" "$(get_env GARAGE_NODE_ID)"
set_env OPENAI_API_BASE 'https://a.b/v1?x=1&y=2'
eq "valeur avec / ? & =" 'https://a.b/v1?x=1&y=2' "$(get_env OPENAI_API_BASE)"
set_env OPENAI_API_KEY 'sk-a\b/c&d$e"f'
eq 'valeur avec \ $ " &' 'sk-a\b/c&d$e"f' "$(get_env OPENAI_API_KEY)"
set_env ALLOWED_ORIGINS '["https://ia.exemple.fr"]'
eq "JSON ALLOWED_ORIGINS" '["https://ia.exemple.fr"]' "$(get_env ALLOWED_ORIGINS)"
eq "pas de doublon après réécriture" "1" "$(grep -c '^SERVER_PORT=' "$ENV_FILE")"
eq "commentaire d'en-tête préservé" "1" "$(grep -c '^# commentaire$' "$ENV_FILE")"
eq "permissions 600" "600" "$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE")"

echo "── Génération des secrets ──"
k="$(gen_access_key)"
[[ "$k" =~ ^GK[0-9a-f]{24}$ ]] && ok "gen_access_key respecte GK + 24 hex" || ko "gen_access_key" "GK+24hex" "$k"
h="$(gen_hex 32)"
[[ "$h" =~ ^[0-9a-f]{64}$ ]] && ok "gen_hex 32 → 64 hex" || ko "gen_hex" "64 hex" "$h"
[[ "$(gen_hex 32)" != "$h" ]] && ok "deux appels donnent des secrets différents" || ko "gen_hex unicité" "≠" "="

echo "── ensure_secret : ne jamais écraser un secret en place ──"
ENV_FILE="$TMP/t2.env"
printf 'PROMETHEE_SECRET_KEY=\nGARAGE_RPC_SECRET=changez-moi-en-production\nGARAGE_SECRET_KEY=deja-la\n' > "$ENV_FILE"
ensure_secret PROMETHEE_SECRET_KEY gen_hex "x" >/dev/null
ensure_secret GARAGE_RPC_SECRET    gen_hex "x" >/dev/null
ensure_secret GARAGE_SECRET_KEY    gen_hex "x" >/dev/null
[[ "$(get_env PROMETHEE_SECRET_KEY)" =~ ^[0-9a-f]{64}$ ]] && ok "clé vide → générée" || ko "clé vide" "64 hex" "?"
[[ "$(get_env GARAGE_RPC_SECRET)" =~ ^[0-9a-f]{64}$ ]] && ok "placeholder → régénéré" || ko "placeholder" "64 hex" "?"
eq "secret déjà renseigné → conservé" "deja-la" "$(get_env GARAGE_SECRET_KEY)"

echo "── Extraction du Node ID Garage (sortie réelle de la commande) ──"
sortie='====================      Garage node ID         ====================

56f7d01ee626b9672eb88de512607f13a79c53cb90b8f5d2195bd40cf6b147d6@garage:3901

=========================================================='
node_id="$(printf '%s' "$sortie" | grep -oE '[0-9a-f]{64}' | head -n1)"
eq "hex avant le @ isolé" "56f7d01ee626b9672eb88de512607f13a79c53cb90b8f5d2195bd40cf6b147d6" "$node_id"
eq "l'adresse @garage:3901 est écartée" "" "$(printf '%s' "$node_id" | grep -o '@')"

echo "── Détection de port ──"
port_busy 6333; r=$?
[[ "$r" == "0" || "$r" == "1" || "$r" == "2" ]] && ok "port_busy renvoie un code exploitable ($r)" || ko "port_busy" "0|1|2" "$r"

printf "\n\033[1m%d réussis, %d échoués\033[0m\n" "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
