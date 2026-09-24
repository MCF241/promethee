# Guide d'utilisation du script d'installation

**Prométhée — `./install.sh`**

Ce guide s'adresse à la personne qui installe Prométhée sur une machine, qu'elle
soit informaticienne ou non. Il décrit ce que fait le script, ce qu'il demande,
et quoi faire quand quelque chose se passe mal.

> Pour la procédure manuelle équivalente, étape par étape, voir
> [`promethee_guide_installation.pdf`](promethee_guide_installation.pdf).

---

## 1. Avant de commencer

### Ce dont vous avez besoin

| | |
|---|---|
| **Un gestionnaire de conteneurs** | Docker, Podman, ou `container` (Apple). Voir §2. |
| **Le code source** | Récupéré avec `git clone`, ou fourni par votre service informatique. |
| **Une clé d'API pour le modèle de langage** | Sans elle, l'application démarre mais le chat reste sans réponse. |

### Ce dont vous n'avez **pas** besoin

**Les droits d'administrateur.** Le script n'utilise jamais `sudo` et ne modifie
rien en dehors du dossier du projet. Les ports qu'il utilise (8000, 6333, 6334,
3900, 3901) sont tous au-dessus de 1024, donc libres d'accès pour un utilisateur
ordinaire.

En revanche, **installer le gestionnaire de conteneurs demande, lui, des droits
d'administrateur**. C'est la seule étape qui en réclame, et elle n'a lieu qu'une
fois. Si vous ne les avez pas, passez au §2.

---

## 2. Le gestionnaire de conteneurs

Prométhée **ne s'installe pas comme une application autonome**. Il est composé de
cinq services qui doivent démarrer dans un ordre précis :

| Service | Rôle |
|---|---|
| `promethee` | L'application elle-même (interface web + moteur) |
| `qdrant` | Base vectorielle — recherche documentaire et mémoire long terme |
| `garage` | Stockage des fichiers de l'utilisateur |
| `garage-config` | Prépare la configuration du stockage, puis s'arrête |
| `garage-init` | Crée l'espace de stockage, puis s'arrête |

Coordonner ces cinq services est précisément le travail d'un gestionnaire de
conteneurs. C'est pourquoi il en faut un, et pourquoi le script commence par
vous le rappeler et vous demander confirmation.

### Les trois gestionnaires acceptés

| Gestionnaire | Statut |
|---|---|
| **Docker** — Docker Desktop ou Docker Engine | Éprouvé |
| **Podman** | Éprouvé |
| **`container`** — moteur d'Apple, macOS 26+ | Accepté sous réserve, voir ci-dessous |

Le script les détecte tout seul et choisit le plus adapté. Vous n'avez rien à
indiquer.

> **Réserve sur le moteur d'Apple.** Apple a écarté la prise en charge native de
> Compose ([apple/container#239](https://github.com/apple/container/pull/239)) au
> profit d'un mécanisme de plugins. Un plugin tiers est donc nécessaire, par
> exemple [container-compose/compose](https://github.com/container-compose/compose),
> et les services doivent tourner (`container system start`). Ces plugins
> réimplémentent Compose partiellement : ils risquent de ne pas respecter l'ordre
> de démarrage dont dépend le stockage. Le script vous prévient et demande
> confirmation, avec **non** par défaut. Préférez Docker ou Podman.

### Si aucun n'est installé

Répondez **non** à la question posée au démarrage du script. Il affichera un
message vous invitant à contacter votre administrateur système ou votre service
informatique, et s'arrêtera sans rien modifier.

**Vous pouvez transmettre ce guide tel quel à votre service informatique :** ce
qu'on lui demande est d'installer l'un des trois gestionnaires ci-dessus sur la
machine. Rien de plus — le reste de l'installation ne nécessite aucun privilège.

---

## 3. Installation

Depuis le dossier du projet :

```bash
./install.sh
```

Lancé **sans aucun argument**, il fonctionne en mode interactif : il pose trois
questions, puis se déroule seul.

> Le mode interactif suppose un vrai terminal. Si le script est lancé dans un
> contexte sans terminal (script automatisé, intégration continue, redirection),
> il le détecte, bascule seul en mode `--yes` et exige alors `--mode`.

### Question 1 — Poursuivre ?

Le rappel décrit au §2, avec une confirmation **Oui / Non**. Répondez **oui** si
un gestionnaire de conteneurs est installé sur la machine.

### Question 2 — Mode d'installation

| Mode | L'application est joignable… | Pour qui |
|---|---|---|
| **1) local** | …uniquement depuis cette machine | Un poste de travail personnel |
| **2) serveur** | …depuis le réseau | Une instance partagée entre plusieurs personnes |

En mode serveur, le script demande aussi l'adresse publique de l'instance (par
exemple `https://ia.exemple.fr`). Laissez vide si vous y accédez par son adresse
IP.

Ce choix ne change rien à l'application installée : il règle seulement qui peut
la joindre.

### Question 3 — Avez-vous déjà une clé d'API ?

Prométhée a besoin d'un modèle de langage pour répondre. Le script demande donc
si vous disposez déjà d'une clé.

- **Oui** — il vous demande ensuite l'adresse du serveur, la clé et le nom du
  modèle. Les valeurs connues sont proposées par défaut : appuyez sur Entrée
  pour les conserver. La clé n'est pas affichée pendant la saisie.
- **Non** — l'installation **continue quand même**. Le script affiche la marche
  à suivre, marque une pause pour vous laisser la lire, puis poursuit. La pile
  sera installée et démarrée ; seul le chat restera sans réponse jusqu'à ce que
  vous renseigniez la clé.

Si une clé est déjà présente dans votre `.env`, la question n'est pas posée.

> **Ajouter la clé plus tard** — inscrivez-la dans `.env` à la ligne
> `OPENAI_API_KEY=`, puis appliquez avec `./prom.sh up promethee`. Utilisez bien
> `up` et non `restart` : un redémarrage simple ne relit pas `.env`.

### Ce qu'il fait ensuite, sans intervention

1. **Vérifie les prérequis** — gestionnaire, ports disponibles, outils.
2. **Prépare la configuration** — crée le fichier `.env` et y génère les mots de
   passe et clés de sécurité, de façon aléatoire et unique à votre installation.
3. **Récupère l'identifiant du stockage** — l'étape la plus délicate de la
   procédure manuelle, entièrement automatisée ici.
4. **Construit et démarre** la pile. **Comptez plusieurs minutes** à la première
   installation : l'interface est compilée et les bibliothèques téléchargées.
5. **Vérifie** que tout répond, et affiche l'adresse d'accès.

### À la fin

Le script affiche l'adresse de l'application. Ouvrez-la dans un navigateur :
l'interface vous propose de **créer le compte administrateur**. Faites-le avant
d'ouvrir l'accès à d'autres personnes.

---

## 4. Options

Le script fonctionne sans aucune option. Celles-ci servent aux cas particuliers.

| Option | Effet |
|---|---|
| `--mode local` / `--mode serveur` | Choisit le mode sans poser la question |
| `--port <numéro>` | Change le port d'écoute (8000 par défaut) |
| `--domaine <url>` | Adresse publique, en mode serveur |
| `--moteur docker\|podman\|container` | Impose le gestionnaire au lieu de le détecter |
| `--reinstall` | Repart d'une configuration neuve (l'ancienne est sauvegardée) |
| `--no-start` | Prépare tout sans construire ni démarrer |
| `-y`, `--yes` | Ne pose aucune question et accepte les valeurs par défaut. `--mode` devient alors obligatoire |
| `--help` | Affiche l'aide complète |

Exemples :

```bash
./install.sh --mode local -y                                  # poste personnel, sans question
./install.sh --mode serveur --domaine https://ia.exemple.fr   # instance partagée
./install.sh --reinstall                                      # tout reprendre à zéro
```

### Relancer le script sans rien casser

`./install.sh` est **rejouable**. Relancé sur une installation existante, il
conserve les mots de passe, les clés et la configuration du modèle déjà en
place, et ne met à jour que ce qui a changé. Vous pouvez donc le relancer pour
basculer de local à serveur, ou changer de port.

Seule l'option `--reinstall` repart de zéro — et elle sauvegarde l'ancienne
configuration dans un fichier `.env.bak.<date>` avant toute chose.

---

## 5. Après l'installation

Le script `./prom.sh` gère la pile au quotidien :

```bash
./prom.sh status            # état des services
./prom.sh logs promethee    # journal de l'application
./prom.sh restart           # redémarrer
./prom.sh down              # arrêter (les données sont conservées)
./prom.sh up                # redémarrer après un arrêt
./prom.sh help              # toutes les commandes
```

> ⚠️ **N'utilisez jamais `./prom.sh down --volumes`** sur une installation qui
> contient des données réelles : cette commande efface définitivement les
> documents, les conversations et les fichiers des utilisateurs.

---

## 6. En cas de problème

### « Gestionnaire de conteneurs requis » puis arrêt

Vous avez répondu **non**, ou aucun gestionnaire n'est installé. Voir §2.

### « Podman ne répond pas : la machine n'est probablement pas démarrée »

```bash
podman machine start
```

### « Le moteur "container" d'Apple est installé mais ses services ne tournent pas »

```bash
container system start
```

Et vérifiez qu'un plugin compose y est installé — voir la réserve au §2.

### « Le port 8000 est déjà occupé »

Un autre programme utilise ce port. Deux solutions : arrêter ce programme, ou
installer Prométhée sur un autre port avec `./install.sh --port 8081`.

Pour savoir quel programme l'occupe :

```bash
lsof -nP -iTCP:8000 -sTCP:LISTEN
```

### « Le dépôt n'est pas accessible depuis la machine Podman »

Sur macOS, Podman exécute les conteneurs dans une machine virtuelle qui ne voit
que votre dossier personnel. Si le projet est ailleurs, le script vous indique la
commande exacte à appliquer. La solution la plus simple reste de déplacer le
dossier du projet dans votre dossier personnel.

### « Le GARAGE_NODE_ID de .env ne correspond pas au nœud en cours »

Normal après une réinstallation du stockage : l'identifiant est régénéré.
Répondez **oui** pour mettre la configuration à jour.

### L'application démarre mais le chat ne répond pas

Trois causes, par ordre de fréquence :

1. **Clé d'API absente ou invalide** — renseignez `OPENAI_API_KEY` dans `.env`.
2. **URL du serveur LLM sans son suffixe `/v1`** — `https://albert.api.etalab.gouv.fr`
   au lieu de `https://albert.api.etalab.gouv.fr/v1`. Les appels partent alors sur
   `/chat/completions` et le serveur répond **404 Not Found**.
3. **Modèle inexistant au catalogue** — les fournisseurs renomment leurs modèles.
   Même symptôme, un **404**. Pour lister ceux réellement disponibles :

   ```bash
   curl -H "Authorization: Bearer <votre-clé>" https://votre-serveur/v1/models
   ```

Après correction de `.env` :

```bash
./prom.sh up promethee
```

> ⚠️ **Utilisez `up`, pas `restart`.** Un `restart` relance le processus sans
> recréer le conteneur : les variables d'environnement restent celles du
> démarrage précédent, et vos modifications de `.env` semblent sans effet.
> `prom.sh` vous le rappelle désormais quand vous redémarrez l'application.

### L'interface reste bloquée sur « Chargement… »

Votre navigateur conserve un jeton de connexion devenu invalide — après une
réinstallation, une rotation des secrets, ou simplement parce qu'il a expiré.
L'application enchaîne alors les erreurs 401 **sans revenir à l'écran de
connexion**.

Solution : videz le stockage local du site. Dans Chrome ou Firefox, ouvrez les
outils de développement (F12), onglet **Application** ou **Stockage**, puis
supprimez les entrées du site — ou plus simplement, ouvrez l'application dans
une fenêtre de navigation privée pour confirmer le diagnostic.

> Il s'agit d'un défaut connu de l'interface : le retour automatique à l'écran
> de connexion sur jeton invalide n'est pas encore implémenté.

### Le chat fonctionne mais la recherche documentaire (RAG) ne trouve rien

Vérifiez `EMBEDDING_MODE` et `EMBEDDING_MODEL` dans `.env`. Si le journal affiche :

```
[RAG] EMBEDDING_MODE '' non supporté (seul 'api' est disponible)
```

c'est que la vectorisation est désactivée. Le chat continue de fonctionner, mais
rien n'est indexé ni retrouvé. Renseignez :

```env
EMBEDDING_MODE=api
EMBEDDING_MODEL=bge-m3
```

puis `./prom.sh up promethee`.

### Autre chose

Consultez le journal :

```bash
./prom.sh logs promethee
```

Puis transmettez-le à votre service informatique, avec le chapitre 5
« Dépannage » de [`promethee_guide_installation.pdf`](promethee_guide_installation.pdf).

---

## 7. Sécurité

- Le fichier **`.env` contient tous les secrets** de l'installation. Le script le
  restreint automatiquement à votre seul compte (permissions `600`). Ne le
  partagez pas, ne le versionnez pas.
- Les sauvegardes `.env.bak.*` contiennent les **anciens** secrets et sont
  exclues du dépôt Git au même titre.
- En **mode local**, rien n'est exposé sur le réseau.
- En **mode serveur**, le port de l'application est ouvert sur toutes les
  interfaces. Filtrez-le au pare-feu si l'instance ne doit pas être publique. La
  base vectorielle et le stockage, eux, restent dans tous les cas inaccessibles
  depuis l'extérieur.
- Derrière un reverse proxy en HTTPS, celui-ci doit relayer les en-têtes
  `Upgrade` et `Connection`, sans quoi le chat restera muet.

---

*Prométhée — Pierre COUGET, 2026 — logiciel sous licence AGPL-3.0*
