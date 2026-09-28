# HardenThis · infrastructure

HardenThis was a defensive cybersecurity training platform. Each user launched a lab: a
deliberately misconfigured machine that they had to fix from a terminal in their browser. The
project didn't work out and we shut it down.

This repository contains the infrastructure, published without the secrets. I wrote it with my
co-founder (see [My part](#my-part)).

Tools: Terraform, AWS (VPC, ECS Fargate, EC2, ECR, IAM, S3, CloudWatch, VPC endpoints),
Docker Compose, Traefik, PostgreSQL, systemd, Cloudflare.

## Contents

| Folder           | Contents                                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------------------- |
| `terraform-vps/` | The final version. AWS is only used for the labs.                                                             |
| `vps/`           | The site on a VPS with Docker Compose (Traefik, NestJS, Next.js, PostgreSQL, Redis) and the database backups. |
| `terraform/`     | The first version, all on AWS, split into modules. Destroyed, kept for reference.                             |

## Final architecture

```
browser
    │
Cloudflare (hardenthis.com, api.hardenthis.com)
    │
VPS, Docker Compose
    Traefik ──► Next.js frontend
            ──► NestJS backend ──► PostgreSQL, Redis
            ──► lab-<id>.hardenthis.com ──┐
                                          │ ports 7681 (terminal) and 9999 (validation)
AWS eu-west-3                             ▼
    ECS Fargate or EC2: one lab per user, created on demand then destroyed
    ECR (lab images), CloudWatch Logs, VPC endpoints
```

The backend creates the lab through the AWS API, then writes the `lab-<id>` route to Redis.
Traefik reads Redis and routes the user's terminal to their lab.

## Lab isolation

A lab gives the user root access, so the boundary can't be the container: it is the AWS network
(`terraform-vps/main.tf`).

- **Ingress**: only from the VPS IP, on ports 7681 (ttyd terminal) and 9999 (validation).
- **Egress**: no rule to `0.0.0.0/0`. Image pulls and log shipping go through private VPC
  endpoints (`ecr.api`, `ecr.dkr`, `logs`, plus an S3 gateway endpoint for the image layers).
- **DNS**: only the VPC's internal resolver.
- **Lab IAM role**: no permissions.

A lab can't open any connection to the Internet: no crypto mining, no attacks on third parties
from our AWS account. Known limitation: low-bandwidth DNS tunneling is still possible through the
VPC resolver. Blocking it would require Route 53 Resolver DNS Firewall, which is a paid service.

To check after a change: start a lab, then `curl -m 5 https://example.com` in its terminal must
fail.

## IAM permissions

Each access has its own IAM user, with the bare minimum:

- `backend-vps` starts and stops labs. It can only stop EC2 instances tagged
  `ManagedBy=hardenthis` and can only pass the lab roles.
- `labs-ci` pushes to the labs ECR repository only, plus what Packer needs to build the EC2
  images.
- `vps-backup` writes and reads back the backups, with no delete permission: a stolen key can't
  wipe the history.

## Backups

In `vps/backup/`:

- `pg-backup.sh` runs a `pg_dump` every night (systemd timer), checks the archive, then uploads
  it to a private, encrypted, versioned S3 bucket with 30-day retention.
- The database password never leaves the container: `pg_dump` runs inside it.
- `restore-test.sh` restores a dump into a throwaway database and compares the row count of each
  table with the live database.
- healthchecks.io sends an alert if the backup didn't run.

## Moving from AWS to a VPS

The first version put everything on AWS: ALB, Traefik on EC2, ECS Fargate for the site, RDS,
ElastiCache, NAT Gateway, Secrets Manager. At AWS list prices it cost about $140 a month, mostly
because of the always-on resources: the NAT Gateway ($34) and the site's two Fargate containers
($27).

We moved the site to a VPS (about €10 a month) and kept only the labs on AWS, billed per use. The
VPC endpoints added later to isolate the labs cost $24 a month: that is a security choice. Total:
about $35 a month.

## My part

- the network isolation of the labs (Internet egress cut off, VPC endpoints);
- the database backups, the restore test and the alert;
- restricting the site to Cloudflare IPs in Traefik;
- hardening the first version (Redis over TLS, RDS, Secrets Manager) and the backend's IAM
  permissions.

## Using the code

```bash
cd terraform-vps
cp terraform.tfvars.example terraform.tfvars   # set vps_public_ip
terraform init
terraform plan
```

The `backend "s3"` block points to the project's state bucket: replace it with your own.

## What is not published

The real variable files, the `.env` files, the keys, the Terraform state, the application code and
the lab contents.
