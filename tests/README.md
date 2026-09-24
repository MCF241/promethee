# Tests

## État actuel

Ce dossier ne contient pour l'instant que les tests du **script d'installation**,
écrits en shell parce que le code testé est lui-même du shell.

```bash
bash tests/test_install.sh
```

20 assertions, sans dépendance : ni moteur de conteneurs, ni réseau, ni accès au
`.env` réel du dépôt (tout se passe dans un répertoire temporaire).

## Ce qui est couvert

| Domaine | Vérifications |
|---|---|
| Manipulation du `.env` | Remplacement, ajout, absence de doublon, préservation des commentaires, permissions `600`, valeurs contenant `/ & $ " \` |
| Génération des secrets | Format `GK` + 24 hex, 64 hex, unicité entre deux appels |
| `ensure_secret` | Un secret déjà renseigné n'est **jamais** écrasé ; un placeholder l'est |
| Node ID Garage | Extraction des 64 hexadécimaux sur la sortie réelle de `garage node id`, en écartant l'adresse `@garage:3901` |
| Détection de port | Code de retour exploitable quel que soit l'outil disponible (`lsof`, `ss`, `nc`) |

## Ce qui n'est pas couvert

Les étapes 4 et 5 d'`install.sh` — démarrage de Garage, récupération du Node ID
sur un nœud réel, construction et démarrage de la pile — supposent un moteur de
conteneurs. Elles se vérifient par une installation réelle, pas ici.

## Tests Python

`CONTRIBUTING.md` prévoit `pytest tests/` pour le code Python. Cette suite n'est
pas encore écrite : aucun test Python n'existe dans le dépôt à ce jour.
