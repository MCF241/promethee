# Changelog — Prométhée AI

Toutes les modifications notables sont documentées dans ce fichier.  
Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) — versioning [SemVer](https://semver.org/lang/fr/).

---

## [Non publié]

### Corrigé
- **URL d'API figée dans le bundle de production — application inutilisable en mode serveur** : les points d'appel du frontend déclaraient chacun `const BASE = import.meta.env.VITE_API_URL ?? "http://localhost:8000"`, or ni le `Dockerfile` (`npm run build`) ni le `docker-compose.yml` ne transmettent `VITE_API_URL` au build — Vite figeait donc la valeur de repli dans le JS compilé. Comme `server/main.py` sert la SPA en *same-origin* (`app.mount("/", StaticFiles(...), html=True)`), un visiteur distant téléchargeait une application appelant `http://localhost:8000`, c'est-à-dire **sa propre machine** : l'application ne fonctionnait qu'en naviguant depuis l'hôte du conteneur
- **Schéma WebSocket figé en `ws://`** : `useAgentStream.ts` reposait sur `ws://localhost:8000` ; derrière TLS, un `ws://` appelé depuis une page `https://` est bloqué par le navigateur (*mixed content*), rendant le flux de chat inopérant en HTTPS. Le schéma est désormais déduit de `window.location.protocol` (`wss://` automatique)
- **`.env.example` — `ALLOWED_ORIGINS` sans valeur utile** : l'exemple `["http://localhost:8000"]` ne correspondait à aucune origine réelle — en production same-origin, CORS n'est pas déclenché, et en développement le navigateur émet depuis le port 5173 servi par Vite ; valeur alignée sur `["http://localhost:5173"]`, conformément au défaut déjà présent dans `server/main.py`
- **`prom.sh down --volumes` inutilisable sur macOS** : la confirmation reposait sur `${confirm,,}`, une expansion introduite par bash 4, alors que `/usr/bin/env bash` résout vers le bash 3.2 livré par macOS. La commande sortait en `bad substitution`. Sans conséquence sur les données — `set -e` coupait avant le `down -v` — mais la commande ne fonctionnait pas. Remplacée par un `case` compatible, acceptant désormais `o`/`oui` comme `y`/`yes`
- **Repli silencieux vers `docker-compose` v1** : la détection acceptait `docker-compose` sans vérifier sa version. Or sous Debian/Ubuntu, `apt install docker-compose` installe la v1 (Python, abandonnée), incapable d'interpréter ce `docker-compose.yml` — il suit la Compose Specification (aucune clé `version:`) et séquence les services via `depends_on: condition: service_completed_successfully`. La pile aurait échoué de façon illisible ; la détection refuse désormais la v1 en indiquant `apt install docker-compose-plugin`
- **`.env.example` — modèle LLM inexistant au catalogue Albert** : l'exemple proposait `mistralai/Mistral-Small-3.1-24B-Instruct-2503`, un identifiant que l'API n'expose plus (elle sert désormais `mistral-small-3-2-24b-instruct-2506`). Toute installation neuve partait donc sur un `404 Not Found` à la première question posée dans le chat, sans message explicite. Valeur mise à jour, avec la commande permettant de lister les modèles réellement disponibles et un rappel du suffixe `/v1` obligatoire sur `OPENAI_API_BASE`
- **`prom.sh restart` laissait croire que `.env` était relu** : `compose restart` relance le processus sans recréer le conteneur, donc les variables issues d'`env_file` restent celles du démarrage précédent — une modification de `.env` semble sans effet. La commande avertit désormais et oriente vers `./prom.sh up <service>`
- **`.env.example` — `EMBEDDING_MODE` et `EMBEDDING_MODEL` totalement absents** : `core/config.py` les fait défaut à la chaîne vide, et `core/rag_engine.py` n'accepte que `api` — toute installation neuve journalisait donc `[RAG] EMBEDDING_MODE '' non supporté` et démarrait avec le RAG et la mémoire long terme silencieusement désactivés, sans que rien ne le signale dans l'interface. Les deux variables sont désormais documentées et renseignées (`api` / `bge-m3`, le modèle d'embeddings d'Albert, vérifié à 1024 dimensions)
- **`.gitignore` — sauvegardes de `.env` non couvertes** : les motifs `.env` et `*.env` ne capturent pas `.env.bak.<horodatage>`, le nom des sauvegardes produites par `install.sh --reinstall`. Ces fichiers contiennent les anciens secrets ; le motif `.env.bak.*` a été ajouté

### Ajouté
- **Module `frontend/src/lib/config.ts`** : source unique des origines HTTP et WebSocket. `API_BASE` vaut `""` par défaut — les requêtes deviennent relatives et suivent le domaine sur lequel l'application est déployée, sans reconstruire l'image. `WS_BASE` est dérivé de `window.location`. Les deux restent surchargeables par `VITE_API_URL` / `VITE_WS_URL` pour les déploiements où le frontend est servi séparément
- **`frontend/.env.development`** : pointe explicitement le frontend vers FastAPI (port 8000) en développement, où Vite (port 5173) et l'API constituent deux origines distinctes — le flux de travail existant est inchangé
- **Script d'installation `install.sh`** : déroule la procédure de `documentation/promethee_guide_installation.pdf` — vérification des prérequis (Docker, démon, Compose, openssl, ports), génération des secrets (`PROMETHEE_SECRET_KEY`, `GARAGE_RPC_SECRET`, `GARAGE_SECRET_KEY`, `GARAGE_ACCESS_KEY` au format `GK` + 24 hex), démarrage de Garage seul, récupération automatique du `GARAGE_NODE_ID` puis build et vérification de la pile. Le choix **local** / **serveur** proposé au démarrage ne pilote que l'adresse d'écoute et la documentation affichée, l'image construite étant identique dans les deux cas. Le script est rejouable : il conserve les secrets et la clé API déjà renseignés (`--reinstall` pour repartir d'un `.env` neuf, l'ancien étant sauvegardé horodaté). Le script s'ouvre sur un avertissement expliquant qu'un gestionnaire de conteneurs est indispensable — Prométhée n'existe pas en version autonome, le RAG, la LTM et le VFS s'adossant directement à Qdrant et Garage — assorti d'une confirmation Oui/Non ; un refus renvoie l'utilisateur vers son administrateur système et interrompt l'installation sans rien modifier
- **Bibliothèque `scripts/container-engine.sh`** : détection du moteur de conteneurs, partagée par `install.sh` et `prom.sh` pour que les deux scripts s'accordent. Reconnaît **Docker** (`docker compose`, repli `docker-compose`) et **Podman** (`podman compose`, repli `podman-compose`, bannière du provider externe neutralisée par `PODMAN_COMPOSE_WARNING_LOGS`). Le moteur natif d'Apple (`container`, macOS 26+) est accepté en dernier recours : Apple ayant écarté le compose natif (apple/container#239) au profit des plugins, la détection teste dynamiquement si un plugin compose tiers répond, exige que les services soient démarrés (`container system start`, sans quoi la CLI répond « Plugins are unavailable » à toute sous-commande inconnue) et prévient que ces réimplémentations partielles peuvent ne pas honorer le `depends_on: condition: service_healthy` dont dépend la séquence garage-config → garage → garage-init. Moteur forçable par `--moteur` (install.sh) ou `PROMETHEE_MOTEUR` (prom.sh)
- **Guide `documentation/guide_installation_script.md`** : mode d'emploi du script destiné à la personne qui installe, y compris non informaticienne — ce qu'il faut avant de commencer, pourquoi un gestionnaire de conteneurs est nécessaire, le déroulé question par question, la référence des options, un chapitre de dépannage par message d'erreur et les points de sécurité. Transmissible tel quel à un service informatique
- **Contrôle de visibilité du dépôt depuis la machine Podman** : sur macOS, Podman exécute les conteneurs dans une VM qui ne monte que le dossier personnel par défaut. Un dépôt situé ailleurs produit un bind-mount vide de `garage.toml`, et Garage ne démarre jamais sans que la cause soit visible. `install.sh` teste le montage avant de lancer quoi que ce soit et indique la commande `podman machine set --volume` à appliquer
- **Étape « disposez-vous déjà d'une clé d'API ? »** : posée avant les questions sur le modèle de langage, plutôt que d'enchaîner des invites auxquelles l'utilisateur ne peut pas répondre. Sur « non », l'installation se poursuit normalement — seul le chat reste muet — après affichage de la marche à suivre (où obtenir une clé, quelle ligne de `.env` renseigner, `./prom.sh up promethee` pour appliquer) et une pause de lecture de 8 secondes, sautée en mode non interactif. La question n'est pas posée si une clé figure déjà dans `.env`
- **Variable `BIND_ADDRESS`** : adresse d'écoute de l'application sur l'hôte, `127.0.0.1` en installation locale et `0.0.0.0` en mode serveur. Le service `promethee` publiait auparavant son port sur toutes les interfaces sans alternative ; le défaut de `docker-compose.yml` reste `0.0.0.0`, les déploiements existants sont donc inchangés

### Modifié
- **11 points d'appel unifiés** : 10 déclarations locales de `BASE` / `WS_BASE` et une expression inline dans `App.tsx` remplacées par un import depuis `lib/config.ts`, réparties sur 9 fichiers — `lib/api.ts`, `lib/docx.ts`, `App.tsx`, `hooks/useAuth.ts`, `hooks/useAgentStream.ts`, `components/vfs/VfsPanel.tsx`, `components/rag/RagPanel.tsx`, `components/chat/ChatInput.tsx`, `components/admin/IngestPanel.tsx`
- **Proxy de développement retiré de `vite.config.ts`** : les règles `/api` et `/ws` étaient sans effet — le frontend n'a jamais appelé de route préfixée par `/api` (les routes réelles sont `/auth`, `/rag`, `/vfs`…), et le WebSocket vise directement le port 8000 via `VITE_WS_URL`. Cette configuration morte était à l'origine de l'affirmation erronée du README (« le frontend proxifie les requêtes API »)
- **Procédure manuelle du README explicitée pour Podman** : les commandes de la section Docker étaient écrites en `docker compose` / `docker exec` sans mention de l'équivalent Podman, alors que le dépôt prend désormais les deux en charge
- **`prom.sh` généralisé au moteur détecté** : les 12 appels `docker compose`, le `docker build` de `--backend-only` et les `docker image prune` passent par le moteur retenu. La commande `help` reste consultable sans moteur installé. Le fichier passe par ailleurs en mode exécutable (100644 → 100755), le README documentant son appel par `./prom.sh`

### Connu — non corrigé

- **Jeton expiré : l'interface reste bloquée sur « Chargement… »** : quand le JWT du
  `localStorage` n'est plus valide (expiration, rotation de `PROMETHEE_SECRET_KEY`,
  réinstallation), le frontend enchaîne les 401 sans jamais revenir à l'écran de
  connexion. Reproduit en conditions réelles : 10 appels en 401 d'affilée, page figée,
  débloquée seulement en vidant le `localStorage`. Le correctif relève de la gestion du
  401 côté frontend et sort du périmètre de cette branche ; contournement documenté dans
  `documentation/guide_installation_script.md`
- **`prom.sh build --backend-only` cible un tag d'image erroné** : le tag
  `promethee-docker-promethee:latest` est codé en dur alors que le nom réel dérive du
  répertoire du projet (`promethee-fork-promethee` ici). L'option est inopérante hors
  d'un dossier nommé `promethee-docker`

---

## [3.0.4] — 2026-05-24

### Corrigé
- **`tools/legifrance_tools.py` — import `date` shadowé** : `from datetime import date` renommé en `from datetime import date as _date_today` — l'ancien import était masqué par le paramètre `date: Optional[str]` dans 5 fonctions (`legifrance_consulter_code`, `legifrance_loi_decret`, `legifrance_historique_texte`, `legifrance_code_complet`, `legifrance_code_par_ancien_id`), provoquant une `AttributeError` silencieuse dès qu'aucune date n'était fournie ; le contournement `globals()["date"].today()` présent dans le fichier était inopérant pour la même raison
- **`tools/legifrance_tools.py` — `_fmt_search` extrayait l'ID de version au lieu du Chronical ID** : `SearchTitle` expose deux champs distincts : `id` (identifiant de version, ex: `JORFARTI000...`) et `cid` (Chronical ID stable, ex: `JORFTEXT000...`) ; le code utilisait `id`, causant un `400 Bad Request` systématique lors des appels à `legifrance_jorf` en aval
- **`tools/legifrance_tools.py` — `legifrance_sommaire_jorf` passait la date en string ISO** : l'endpoint `/consult/jorfCont` attend un `ConsultDateRequest` (`{year, month, dayOfMonth}`) pour les champs `start`/`end`, pas une string `YYYY-MM-DD` — la date était ignorée ou rejetée ; ajout du paramètre `date_fin` pour permettre la recherche sur une période (ex: mois entier)
- **`tools/legifrance_tools.py` — `legifrance_jorf` retournait une coquille vide** : la fonction comptait les articles sans les afficher et renvoyait vers `legifrance_jorf_part` sans fournir les IDs de sections nécessaires, laissant le modèle sans contenu exploitable ; les articles sont désormais retournés directement (jusqu'à 50), avec fallback sur les IDs de sections pour les textes volumineux

---

## [3.0.3] — 2026-05-24

### Ajouté
- **Génération Word côté client** : nouveau module `lib/docx.ts` basé sur la lib `docx` (npm) — produit un fichier `.docx` directement dans le navigateur sans round-trip serveur, avec rendu des graphiques ECharts en image PNG intégrée
- **Bouton ↓ .docx** dans l'ArtifactPanel : enregistre le document Word directement dans le VFS (`/exports/`) via le nouvel endpoint `POST /vfs/save-blob`
- **Endpoint `POST /vfs/save-blob`** : reçoit un blob binaire depuis le frontend et le persiste dans le VFS de l'utilisateur avec dédoublonnage automatique du nom de fichier
- **Bloc `word` dans l'ArtifactPanel** : détection et rendu des blocs ` ```word ``` ` comme artefacts dédiés (kind `word`) avec ReactMarkdown, support ECharts/Mermaid imbriqués
- **Module `lib/artifacts.ts`** : extraction des artefacts découplée de React, testable en isolation — support des blocs `word` avec parser d'imbrication et `reconstructWordContent`
- **Module `lib/mermaid-sanitizer.ts`** : correction préventive des erreurs LLM les plus fréquentes avant rendu Mermaid (accents, C4 → graph TD, séquences mal fermées, mots-clés réservés…)
- **Module `lib/echarts-defaults.ts`** : thème ECharts cohérent avec la charte CSS de Prométhée — `buildEChartsDefaults`, `mergeEChartsOption`, `cleanEChartsCode` (parseur caractère-par-caractère en remplacement des regex en cascade)

### Modifié
- **`MermaidBlock`** : sandbox singleton réutilisable (div hors-écran fixe) en remplacement de la création/destruction DOM à chaque render — `sanitizeMermaid` appelé avant chaque `mermaid.render()`
- **`EChartsBlock`** : `parseEChartsConfig` (cascades de regex) remplacé par `cleanEChartsCode` ; thème natif ECharts `"dark"` supprimé au profit des defaults CSS
- **`useArtifactPanel`** : délègue entièrement l'extraction à `lib/artifacts.ts`, réduit à la gestion d'état React pur
- **`MessageBubble`** : les blocs ` ```word ``` ` sont rendus comme du Markdown normal dans le chat (titres, listes, graphiques ECharts/Mermaid inline)
- **`prompts.yml`** : suppression de `export_tools` et `export_template_tools` de tous les profils rédactionnels — règle "Documents Word → bloc `word`" injectée dans 7 profils

### Supprimé
- `tools/export_tools.py` — remplacé par la génération Word côté client
- `tools/export_template_tools.py` — supprimé (gabarits personnalisés non utilisés)
- `skills/guide_export_docx_pdf.md` — supprimé (déclencheur du comportement erratique lors de l'export)
- `skills/guide_utilisation_templates.md` — supprimé

### Dépendances
- **Frontend** : ajout de `docx` (génération Word côté client)

---

## [3.0.2] — 2026-04-23

### Modifié
- 🐛 Correction d'une régression sur l'analyse d'image
- 🐛 Modification du fichier Docker pour fonctionner avec les proxies transparents (forçage HTTPS)

## [3.0.1] — 2026-04-22

### Modifié
- 🐛 Mise en cohérence de bibliothèques : suppression d'utilisation résiduelle de requests pour alignement sur httpx

### Ajouté
- 📚 Fonctions de recherche d'images dans web_tools (première source : Wikimedia)



## [3.0.0] — 2026-04-17

### Ajouté
- **Dockerisation complète** : stack Docker Compose (Prométhée + Qdrant + Garage + services init)
- **VFS avec Garage** : stockage des fichiers virtuels utilisateurs via Garage (compatible S3), en remplacement du VFS SQLite embarqué
- **Frontend React/TypeScript** (Vite) : interface web multi-utilisateurs en remplacement de l'interface Qt6 desktop
  - Authentification JWT, thème clair/sombre
  - Panneau VFS avec navigation, upload, téléchargement et quota
  - Panneau RAG, panneau Profils/Skills, panneau Admin
  - Panneau outils et composant ECharts pour la visualisation de graphiques
- **Multi-utilisateurs** : gestion complète des comptes, rôles et isolation des données
- **API FastAPI** avec WebSocket pour le streaming, routeurs REST pour auth, RAG, VFS, settings, admin
- **Bibliothèques de rendu** : LaTeX (KaTeX, assets locaux) et diagrammes Mermaid (v11, bundle local)
- **ECharts** : rendu de graphiques interactifs dans le chat via blocs `echarts`
- **Docker multi-stage** : build React intégré au Dockerfile, assets KaTeX/Mermaid téléchargés au build
- **Configuration Garage** : `garage.toml`, `Dockerfile.garage-init`, service `garage-config` Alpine pour la substitution de secrets

### Modifié
- Architecture passée de **mono-utilisateur desktop (Qt6)** à **web multi-utilisateurs (FastAPI + React)**
- VFS migré de SQLite local vers **stockage objet S3 (Garage)**
- Toutes les dépendances mises à jour (voir `requirements.txt` et `frontend/package.json`)

### Supprimé
- Interface Qt6 / PySide6
- VFS SQLite embarqué (remplacé par Garage)
- Dépendances Qt (`PySide6`, `pyqtgraph`, etc.)

---

## [2.2.4] — 2026-03

### Ajouté
- Export structuré du contenu de la réponse vers Word/LibreOffice depuis l'interface de chat (copier/coller brut markdown ou riche RTF)

### Corrigé
- Corrections de bugs sur des cas limites dans le RAG

---

## [2.2.3] — 2026-02

### Ajouté
- Outil de reformulation des comptes rendus oraux vers un style adapté à l'écrit
- Profil « Rédacteur » et skill dédié

### Corrigé
- Corrections de bugs dans le rendu LaTeX et Mermaid

---

## [2.2.2] — 2026-02

### Corrigé
- Corrections de bugs dans le RAG avec Qdrant

---

## [2.2.1] — 2026-01

### Ajouté
- Suppression de la mémoire long terme possible depuis l'interface

### Modifié
- Amélioration de la mémoire long terme (LTM) : réduction des souvenirs parasites
- Refactorisation de plusieurs modules pour améliorer la maintenabilité

### Corrigé
- Affichage des images dans le chat
- Correctifs divers sur l'interface utilisateur
