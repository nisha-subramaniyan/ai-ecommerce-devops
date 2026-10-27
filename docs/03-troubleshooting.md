# Troubleshooting

General method: **what changed -> read the logs -> check the object's events -> fix -> re-run the health check.**

| Symptom | Likely cause | Fix |
|---|---|---|
| `permission denied ... /var/run/docker.sock` | your user is not in the `docker` group | `sudo usermod -aG docker $USER && newgrp docker` |
| Port already in use (8080/8081/9090/3001/5601) | another process listens there | `ss -tulpn \| grep 8080`, stop it or change the host port in the compose/kind file |
| `docker compose up`: backend restarts, "database init failed" | DB still starting or wrong password | `docker compose -f docker/docker-compose.yml logs db backend`; the backend retries for ~60 s; check `DB_PASSWORD` is not changed after the volume was created (`docker compose down -v` resets) |
| Pods `ImagePullBackOff` / `ErrImagePull` | image not pushed, wrong tag, or kind nodes cannot reach the registry | `docker images \| grep localhost:5001`; `curl localhost:5001/v2/_catalog`; re-run `./scripts/deploy.sh cluster` (re-applies the registry mapping) and `./scripts/deploy.sh build <tag>`; `kubectl -n shop describe pod <pod>` |
| Pods `CrashLoopBackOff` | app crashes, usually DB connection | `kubectl -n shop logs <pod> --previous`; verify `shop-postgres` pod is Ready; secret/password match |
| Pod `Running` but not `Ready` | readiness probe `/ready` fails (DB unreachable) | `kubectl -n shop describe pod`, check Postgres |
| `http://localhost:8081` refused | ingress controller not ready / kind cluster created without port mapping | `kubectl -n ingress-nginx get pods`; cluster must be created from `kubernetes/kind-config.yaml` (delete and recreate if not) |
| 502/504 from Nginx | backend pods not ready or Service selector mismatch | `kubectl -n shop get endpoints backend` (empty = no ready pods / selector mismatch) |
| `helm upgrade` fails: "resource ... exists and cannot be imported" | objects created earlier with `kubectl apply` | delete the raw objects (see guide Step 6.3) then retry |
| Jenkins: `docker: command not found` or permission denied | socket not mounted / not root | use `jenkins/docker-compose.yml` unchanged (mounts the socket, `user: root`) |
| Jenkins: `kubectl`/`helm` cannot connect | missing or wrong kubeconfig | recreate: `kind get kubeconfig --internal --name shop > jenkins/kubeconfig`; Jenkins must be on the `kind` network; restart Jenkins |
| `jenkins/docker-compose.yml`: network `kind` not found | cluster not created yet | create the cluster first (`./scripts/deploy.sh cluster`) |
| Jenkins "Health Check" cannot reach `host.docker.internal:8081` | host-gateway mapping missing | keep `extra_hosts` in the compose file; Docker 20.10+ required |
| `npm audit` fails the pipeline | real vulnerable dependency | `cd application/backend && npm audit fix`, commit the updated lockfile |
| gitleaks fails | a secret-like string is in the repo/history | remove it, **rotate the real secret**, and purge it from history if committed |
| Trivy fails with CRITICAL | vulnerable base image/package | rebuild with a newer base tag (`node:20-alpine` is re-pulled with `docker pull`), or fix the dependency |
| Prometheus target `shop-backend` DOWN | wrong network or app down | monitoring compose joins `shop_backend-net`; start the app compose first; `docker network ls` |
| Grafana panels "No data" | no traffic yet or data source wrong | generate requests; Connections -> Data sources -> Prometheus URL `http://prometheus:9090` |
| ServiceMonitor not created | CRD missing | install kube-prometheus-stack first, then `helm upgrade shop ... --reuse-values` |
| Elasticsearch exits / "max virtual memory areas too low" | kernel setting | `sudo sysctl -w vm.max_map_count=262144` |
| Elasticsearch/Kibana very slow or killed | not enough RAM | stop other stacks (`docker compose ... down`); give Docker Desktop/WSL more memory (`.wslconfig`: `memory=8GB`) |
| Kibana shows no logs | Filebeat cannot read container logs or names do not match | `docker compose -f logging/elk/docker-compose.elk.yml logs filebeat`; container names must start with `shop-` (Compose project name `shop`) |
| `terraform init` provider download fails | no internet / proxy | retry on a normal network |
| Terraform kind: "cluster already exists" | cluster created by script earlier | `kind delete cluster --name shop`, then apply |
| Ansible: `community.general.ufw` not found | collection missing | `ansible-galaxy collection install community.general` |
| Ansible `Permission denied` | need sudo password | add `-K` |
| `analyze.py --elastic` connection refused | ELK not running or index empty | `curl localhost:9200/_cat/indices`; generate some traffic first |

## Useful diagnostic commands

```bash
kubectl -n shop get pods,svc,ingress,endpoints
kubectl -n shop describe pod <pod>              # Events at the bottom
kubectl -n shop logs deploy/shop-backend --tail=100
kubectl get events -A --sort-by=.lastTimestamp | tail -20
helm status shop -n shop && helm history shop -n shop
docker compose -f docker/docker-compose.yml ps
docker stats --no-stream
```
