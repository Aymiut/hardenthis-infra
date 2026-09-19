# Sauvegardes Postgres — hardenthis

Sauvegarde quotidienne de la base Postgres du VPS vers un bucket S3 **privé,
chiffré et versionné** (`hardenthis-prod-backups`, région `eu-west-3`).

## Architecture

```
VPS (hardenthis user, groupe docker)
  └─ timer systemd (03:30 UTC) ─▶ pg-backup.sh
       ├─ docker exec hardenthis-postgres-1  pg_dump -Fc   (lecture seule)
       ├─ vérifie l'archive (pg_restore --list)
       └─ docker run amazon/aws-cli  s3 cp ──▶ s3://hardenthis-prod-backups/
                                                  postgres/<db>/AAAA/MM/JJ/hardenthis-<UTC>.dump
```

- **Format** : `pg_dump -Fc` (custom, compressé, restaurable sélectivement).
- **Le mot de passe DB ne quitte jamais le conteneur** : `pg_dump` lit
  `POSTGRES_PASSWORD` depuis l'environnement du conteneur Postgres.
- **Credentials AWS** : IAM user dédié `hardenthis-prod-vps-backup` (least-priv :
  `PutObject`/`GetObject`/`ListBucket` sur ce bucket **uniquement**, pas de
  `Delete`). Stockés dans `/opt/hardenthis/backup/backup-creds.env` (chmod 600).
- **Rétention** : lifecycle S3 — objets courants expirés à 30 j, versions
  non-courantes 7 j plus tard. (Pas géré par le script.)
- **Infra AWS** : définie dans `infra/terraform-vps/backups.tf`.

## Fichiers (sur le VPS : `/opt/hardenthis/backup/`)

| Fichier | Rôle |
|---|---|
| `pg-backup.sh` | Le job de sauvegarde (dump → vérif → upload S3). |
| `restore-test.sh` | Vérifie qu'un dump S3 est restaurable (base scratch jetable). |
| `backup-creds.env` | Clés AWS de l'IAM `vps-backup` (chmod 600, **non versionné**). |
| `hardenthis-backup.service` / `.timer` | Unités systemd (planification). |

## Installation du timer (one-shot, nécessite root)

```bash
sudo install -m 644 /opt/hardenthis/backup/hardenthis-backup.service /etc/systemd/system/
sudo install -m 644 /opt/hardenthis/backup/hardenthis-backup.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hardenthis-backup.timer
sudo systemctl list-timers hardenthis-backup.timer   # vérifier le prochain déclenchement
```

## Lancer une sauvegarde à la main

```bash
/opt/hardenthis/backup/pg-backup.sh
```

## Vérifier qu'une sauvegarde est restaurable (sans toucher la prod)

```bash
# lister les sauvegardes
aws s3 ls --recursive s3://hardenthis-prod-backups/postgres/   # ou via la console

# restaurer dans une base scratch jetable et comparer à la prod
/opt/hardenthis/backup/restore-test.sh postgres/hardenthis/AAAA/MM/JJ/hardenthis-<UTC>.dump
```

Le script crée `hardenthis_restore_test`, y restaure le dump, compare le nombre
de lignes de **chaque table** avec la base live, puis supprime la base scratch.
Seules des tables volatiles (`refreshtokens`, `verification_tokens`) peuvent
légitimement différer si le dump est antérieur.

## RESTAURATION RÉELLE (cas catastrophe — à faire en connaissance de cause)

> ⚠️ Écrase des données. Ne le faire que sur décision explicite.

```bash
KEY="postgres/hardenthis/AAAA/MM/JJ/hardenthis-<UTC>.dump"
TMP=$(mktemp -d)
set -a; source /opt/hardenthis/backup/backup-creds.env; set +a

# 1. récupérer le dump
docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION=eu-west-3 -v "$TMP:/data" amazon/aws-cli \
  s3 cp "s3://hardenthis-prod-backups/$KEY" /data/restore.dump
docker cp "$TMP/restore.dump" hardenthis-postgres-1:/tmp/restore.dump

# 2. (recommandé) couper le backend pour éviter les écritures concurrentes
cd /opt/hardenthis && docker compose stop backend

# 3. restaurer dans la base de prod (--clean --if-exists remplace les objets)
docker exec hardenthis-postgres-1 sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
     --clean --if-exists --no-owner /tmp/restore.dump'

# 4. relancer le backend
docker compose start backend
docker exec hardenthis-postgres-1 rm -f /tmp/restore.dump; rm -rf "$TMP"
```

## Monitoring — dead-man's-switch (healthchecks.io)

Le job logge toujours dans le journal systemd :
```bash
journalctl -u hardenthis-backup.service -n 50
```

En plus, `pg-backup.sh` ping un **dead-man's-switch** : healthchecks.io alerte
si le succès n'arrive pas dans la fenêtre attendue. Avantage sur un simple
`OnFailure=` : ça détecte aussi le cas où **le job n'a jamais tourné** (VPS
éteint, timer désactivé, docker mort) — pas seulement un échec d'exécution.

Le script envoie trois signaux (via `HEALTHCHECK_URL`) :
- `…/start` — au démarrage (donne la durée du run + détecte un job qui hang) ;
- `…` (succès) — en fin de job, réarme le timer ;
- `…/fail` — sur erreur, avec le message d'échec en corps de requête.

**Le ping est optionnel** : si `HEALTHCHECK_URL` n'est pas défini, les pings sont
ignorés silencieusement — une config d'alerting absente ne peut **jamais** casser
la sauvegarde elle-même.

### Mise en place (une fois)

1. Sur [healthchecks.io](https://healthchecks.io) (free tier suffit), créer un
   check : **Period = 1 day**, **Grace = 1 hour**, nom `hardenthis-pg-backup`.
   Brancher une intégration de notif (email / Slack / Discord).
2. Copier l'URL de ping du check (`https://hc-ping.com/<uuid>`).
3. L'ajouter à `/opt/hardenthis/backup/backup-creds.env` (chmod 600, non versionné) :
   ```bash
   HEALTHCHECK_URL=https://hc-ping.com/<uuid>
   ```
4. Tester : `/opt/hardenthis/backup/pg-backup.sh` → le check doit passer **up**
   sur le dashboard (et un run raté doit le passer **down** + notifier).

> ⚠️ Le déploiement du script sur le VPS est **manuel** (le dépôt `infra` n'a pas
> de CI). Copier `pg-backup.sh` mis à jour dans `/opt/hardenthis/backup/` ; aucun
> `daemon-reload` n'est nécessaire (seuls les `.service`/`.timer` en exigent un).
