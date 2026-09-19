# HardenThis · infrastructure

HardenThis était une plateforme d'entraînement à la cybersécurité défensive. Chaque utilisateur
lançait un lab : une machine volontairement mal configurée, qu'il devait corriger depuis un
terminal dans son navigateur. Le projet n'a pas fonctionné et nous l'avons arrêté.

Ce dépôt contient l'infrastructure, publiée sans les secrets. Je l'ai écrite avec mon associé
(voir [Ma part](#ma-part)).

Outils : Terraform, AWS (VPC, ECS Fargate, EC2, ECR, IAM, S3, CloudWatch, VPC endpoints),
Docker Compose, Traefik, PostgreSQL, systemd, Cloudflare.

## Contenu

| Dossier          | Contenu                                                                                                              |
| ---------------- | -------------------------------------------------------------------------------------------------------------------- |
| `terraform-vps/` | La version finale. AWS ne sert plus qu'aux labs.                                                                     |
| `vps/`           | Le site sur un VPS avec Docker Compose (Traefik, NestJS, Next.js, PostgreSQL, Redis) et les sauvegardes de la base. |
| `terraform/`     | La première version, tout sur AWS, découpée en modules. Détruite, gardée pour référence.                             |

## Architecture finale

```
navigateur
    │
Cloudflare (hardenthis.com, api.hardenthis.com)
    │
VPS, Docker Compose
    Traefik ──► frontend Next.js
            ──► backend NestJS ──► PostgreSQL, Redis
            ──► lab-<id>.hardenthis.com ──┐
                                          │ ports 7681 (terminal) et 9999 (validation)
AWS eu-west-3                             ▼
    ECS Fargate ou EC2 : un lab par utilisateur, créé à la demande puis détruit
    ECR (images des labs), CloudWatch Logs, VPC endpoints
```

Le backend crée le lab avec l'API AWS, puis écrit la route `lab-<id>` dans Redis. Traefik lit
Redis et envoie le terminal de l'utilisateur vers son lab.

## Isolation des labs

Un lab donne un accès root à l'utilisateur. La limite ne peut donc pas être dans le conteneur :
elle est dans le réseau AWS (`terraform-vps/main.tf`).

- **Entrée** : seulement depuis l'IP du VPS, sur les ports 7681 (terminal ttyd) et 9999
  (validation).
- **Sortie** : aucune règle vers `0.0.0.0/0`. Le téléchargement de l'image et l'envoi des logs
  passent par des VPC endpoints privés (`ecr.api`, `ecr.dkr`, `logs`, et un endpoint gateway S3
  pour les couches d'image).
- **DNS** : seulement le résolveur interne du VPC.
- **Rôle IAM du lab** : aucune permission.

Un lab ne peut ouvrir aucune connexion vers Internet : pas de minage, pas d'attaque vers des tiers
depuis notre compte AWS. Limite connue : un tunnel DNS à bas débit reste possible via le résolveur
du VPC. Le bloquer demanderait Route 53 Resolver DNS Firewall, qui est payant.

Pour vérifier après une modification : lancer un lab, puis `curl -m 5 https://example.com` dans son
terminal doit échouer.

## Droits IAM

Chaque accès a son propre utilisateur IAM, avec le minimum :

- `backend-vps` lance et arrête les labs. Il ne peut arrêter que les instances EC2 taguées
  `ManagedBy=hardenthis` et ne peut transmettre que les rôles des labs.
- `labs-ci` pousse dans le seul dépôt ECR des labs, avec en plus ce dont Packer a besoin pour
  construire les images EC2.
- `vps-backup` écrit et relit les sauvegardes, sans droit de suppression : une clé volée ne peut
  pas effacer l'historique.

## Sauvegardes

Dans `vps/backup/` :

- `pg-backup.sh` fait un `pg_dump` chaque nuit (timer systemd), vérifie l'archive, puis l'envoie
  dans un bucket S3 privé, chiffré et versionné, avec 30 jours de rétention.
- Le mot de passe de la base ne sort jamais du conteneur : `pg_dump` tourne à l'intérieur.
- `restore-test.sh` restaure un dump dans une base jetable et compare le nombre de lignes de chaque
  table avec la base en service.
- healthchecks.io envoie une alerte si la sauvegarde n'a pas tourné.

## Passage d'AWS à un VPS

La première version mettait tout sur AWS : ALB, Traefik sur EC2, ECS Fargate pour le site, RDS,
ElastiCache, NAT Gateway, Secrets Manager. Elle coûtait environ 119 $ par mois. Nous avons déplacé
le site sur un VPS à 10-15 € par mois et gardé sur AWS uniquement les labs, facturés à l'usage.

Les VPC endpoints ajoutés ensuite pour isoler les labs coûtent environ 24 € par mois. C'est un
choix de sécurité.

## Ma part

- l'isolation réseau des labs (sortie Internet coupée, VPC endpoints) ;
- les sauvegardes de la base, le test de restauration et l'alerte ;
- le filtrage du site aux IP de Cloudflare dans Traefik ;
- le durcissement de la première version (Redis en TLS, RDS, Secrets Manager) et les droits IAM
  du backend.

## Utiliser le code

```bash
cd terraform-vps
cp terraform.tfvars.example terraform.tfvars   # renseigner vps_public_ip
terraform init
terraform plan
```

Le bloc `backend "s3"` pointe vers le bucket d'état du projet : il faut le remplacer par le vôtre.

## Ce qui n'est pas publié

Les fichiers de variables réels, les `.env`, les clés, l'état Terraform, le code de l'application
et le contenu des labs.
