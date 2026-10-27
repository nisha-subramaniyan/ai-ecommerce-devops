# Architecture

## 1. End-to-end delivery flow

```mermaid
flowchart TD
  DEV[Developer] -->|git push / PR| GH[GitHub]
  GH -->|poll or webhook| JK[Jenkins]
  GH -->|on push/PR| GA[GitHub Actions]
  JK --> B[Install + Build] --> T[Test] --> S[Security: gitleaks, npm audit, trivy config]
  S --> DB[Docker build] --> IS[Image scan: trivy] --> REG[(Container registry)]
  REG --> K8S[Kubernetes cluster]
  JK -->|helm upgrade| K8S
  K8S --> APP[Frontend + Backend + Postgres]
  APP --> ING[Ingress :8081]
  APP -->|/metrics| PROM[Prometheus] --> GRAF[Grafana]
  APP -->|stdout JSON logs| FB[Filebeat] --> LS[Logstash] --> ES[(Elasticsearch)] --> KB[Kibana]
  ES --> AI[AI incident analysis] --> INS[Severity, root cause, remediation]
  JK -->|health check fails| RB[helm rollback]
```

## 2. Infrastructure layers (underneath the delivery flow)

```mermaid
flowchart TD
  TF[Terraform: provisions] --> INFRA[Infrastructure: kind cluster or AWS EC2]
  INFRA --> AN[Ansible: configures servers] --> CFG[Docker, users, firewall, hardening]
  CFG --> K[Kubernetes / servers]
  SEC[Security: least privilege, scanning, secrets, hardening] -.applies to every layer.-> TF
  SEC -.-> AN
  SEC -.-> K
```

## 3. Runtime topology (Kubernetes)

```
Browser -> localhost:8081 -> kind node port mapping -> ingress-nginx
        -> Service "frontend" (:80) -> frontend pods (Nginx :8080, serves static files)
              -> /api/*  -> Service "backend" (:3000) -> backend pods (Node)  -> Service "shop-postgres" (:5432) -> Postgres pod + PVC
```

## 4. Technology -> role (as defined in the report)

| Category | Technology | Role in this repo |
|---|---|---|
| OS | Linux (Ubuntu/WSL) | runs everything; `scripts/setup.sh`, `security/linux-hardening.sh` |
| Version control / collaboration | Git, GitHub | branching `main`/`develop`/`feature/*`, PRs |
| Automation | Bash | `scripts/*.sh` |
| Web server / reverse proxy | Nginx | `docker/nginx.conf` |
| Containerisation | Docker, Compose | `docker/` |
| CI/CD | Jenkins (+ GitHub Actions alternative) | `jenkins/`, `.github/workflows/ci.yml` |
| Infrastructure | Terraform | `terraform/` (kind local, AWS EC2) |
| Configuration | Ansible | `ansible/` |
| Orchestration | Kubernetes (kind) | `kubernetes/`, `helm/` |
| Packaging | Helm | `helm/ecommerce` |
| Monitoring | Prometheus, Grafana | `monitoring/` |
| Logging | ELK (+ Filebeat) | `logging/elk/` |
| Security | gitleaks, npm audit, Trivy, hardening, NetworkPolicy | `security/`, pipeline stages |
| AI | rules engine / Ollama / Claude API | `ai/incident-analysis/` |
| Cloud | AWS (Terraform module) / Oracle Always Free (Ansible) | Step 16 of the guide |

## 5. Key design decisions

* **kind instead of a managed cloud cluster** - free and behaves like real Kubernetes; only the Terraform `target` differs for a cloud.
* **Local registry** (`localhost:5001`) - same push/pull flow as ECR/ACR/Docker Hub without a paid account.
* **Helm for deployments, raw YAML for learning** - both are kept so the objects can be explained and the release can be versioned/rolled back.
* **JSON logs + `/metrics` in the app** - the app is designed to be observable; ELK and Prometheus need no code changes.
* **Rules-first AI** - deterministic and free; an LLM is an optional upgrade with automatic fallback.
* **Security gates** - CRITICAL image vulnerabilities, high+ dependency issues and any detected secret fail the pipeline; misconfiguration findings are advisory.
* **Lab shortcuts (documented, not for production)** - Jenkins uses the host Docker socket; Elasticsearch has security disabled; default demo passwords; kind's CNI does not enforce NetworkPolicy.
