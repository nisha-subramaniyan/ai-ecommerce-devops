# AI-Powered E-Commerce DevOps & Cloud-Native Delivery Platform

A complete, free-to-run DevOps platform around an e-commerce application: **Git/GitHub -> Jenkins -> Docker -> Registry -> Kubernetes (Helm) -> Prometheus/Grafana -> ELK -> AI incident analysis**, with Terraform, Ansible and DevSecOps checks. Follows the Davine Technologies architecture report.

> New here? Read **[docs/01-implementation-guide.md](docs/01-implementation-guide.md)** - a step-by-step walkthrough that explains what, why and how for every component.

## Quick start (free, local)

Requirements: Linux / WSL2 / macOS with Docker, 8 GB+ RAM.

```bash
./scripts/setup.sh                                    # install tools (once)

# 1) Docker Compose
./scripts/deploy.sh compose                           # http://localhost:8080

# 2) Kubernetes (kind) + Helm
./scripts/deploy.sh down                              # free RAM first
./scripts/deploy.sh local                             # http://localhost:8081

# 3) Add the platform layers (one at a time to save RAM)
docker compose -f jenkins/docker-compose.yml up -d --build           # CI/CD     http://localhost:8090
docker compose -f monitoring/docker-compose.monitoring.yml up -d     # Metrics   :9090 / :3001
docker compose -f logging/elk/docker-compose.elk.yml up -d           # Logs      :5601
python3 ai/incident-analysis/analyze.py --file ai/incident-analysis/sample_logs/db_timeout.log
```

## Repository layout

```
application/       backend (Node/Express + Postgres) and frontend (static)
scripts/           setup, deploy, deploy-strategy, health-check, backup, cleanup, logs (Bash)
docker/            Dockerfile, Dockerfile.frontend, nginx.conf, docker-compose.yml, .dockerignore
jenkins/           Jenkinsfile, Jenkins image (Dockerfile), compose, plugins
.github/workflows/ GitHub Actions CI (alternative pipeline)
terraform/         main/provider/variables/outputs, modules (kind-cluster, aws-ec2), environments/
ansible/           inventory, playbook, group_vars, roles (common, docker, app)
kubernetes/        namespace, deployment, service, configmap, secret, ingress, hpa, postgres, kind-config
helm/ecommerce/    Helm chart (rolling, canary, blue-green, autoscaling, ServiceMonitor)
monitoring/        Prometheus, alert rules, Grafana provisioning + dashboard, kube-prometheus-stack values
logging/elk/       Elasticsearch, Logstash, Kibana, Filebeat
security/          run-scans.sh, linux-hardening.sh, network-policy.yaml
ai/                incident-analysis (rules / Ollama / Claude), tests, sample logs
docs/              implementation guide, architecture, troubleshooting
```

## Branching model
`main` (deployable) <- `develop` <- `feature/*`; changes enter through Pull Requests, which run `.github/workflows/ci.yml`.

## Pipeline
`GitHub push -> Jenkins -> checkout -> install -> build -> test -> security (gitleaks, npm audit, trivy) -> docker build -> image scan -> push -> helm deploy -> health check (auto-rollback on failure)`

## Endpoints
| URL | What |
|---|---|
| http://localhost:8080 | app via Docker Compose |
| http://localhost:8081 | app via Kubernetes ingress |
| `/health`, `/ready`, `/metrics`, `/api/version` | backend operational endpoints (through `:3000` or the proxied `/api/...`) |
| http://localhost:8090 | Jenkins |
| http://localhost:9090 / :3001 | Prometheus / Grafana (admin/admin) |
| http://localhost:5601 | Kibana |

## Security notes
Demo passwords (`demo-only-change-me`, Grafana `admin/admin`) and the disabled Elasticsearch security are **lab-only**. Provide real values with `--set postgres.password=...`, `.env` files or Kubernetes Secrets created out-of-band; never commit them.

## Documentation
1. [Implementation guide](docs/01-implementation-guide.md)
2. [Architecture](docs/02-architecture.md)
3. [Troubleshooting](docs/03-troubleshooting.md)

