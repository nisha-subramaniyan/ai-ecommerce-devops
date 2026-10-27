#!/usr/bin/env python3
"""AI-assisted incident analysis for the e-commerce platform.

Pipeline (matches the architecture report):
    application logs -> centralized logging (Elasticsearch / file / stdin) -> error extraction
    -> AI analysis -> {error classification, severity, possible root cause, suggested remediation}

Three interchangeable "brains" - all free:
    rules     (default) offline, deterministic pattern knowledge base. Always works, great for demos and tests.
    ollama    a free local LLM (https://ollama.com), e.g. `ollama pull llama3.2`. No data leaves your laptop.
    anthropic uses Claude if ANTHROPIC_API_KEY is set (paid API; optional).

Only the Python standard library is used, so there is nothing to pip install.

Examples:
    python3 analyze.py --file sample_logs/db_timeout.log
    python3 analyze.py --elastic http://localhost:9200 --minutes 30
    python3 analyze.py --file app.log --engine ollama --model llama3.2
    docker logs shop-backend-1 2>&1 | python3 analyze.py --stdin
"""
import argparse
import json
import os
import sys
import urllib.request
from collections import Counter
from datetime import datetime, timezone

# ---------------------------------------------------------------- knowledge base
# (regex fragment, category, severity, root cause, remediation steps)
RULES = [
    (("etimedout", "timeout", "timed out", "connection refused", "econnrefused", "econnreset"),
     "Database / network connectivity", "HIGH",
     "The backend cannot reach a dependency (usually PostgreSQL) - the database pod/container is down, "
     "overloaded, or a Service/DNS/NetworkPolicy change blocks traffic.",
     ["Check the database is running: `kubectl -n shop get pods` / `docker compose ps`",
      "Look at DB logs: `kubectl -n shop logs deploy/shop-postgres`",
      "Verify DATABASE_URL and the shop-secret password match",
      "Check NetworkPolicies and Service names (`kubectl -n shop get svc,networkpolicy`)",
      "If recent deploy: `helm rollback shop -n shop`"]),
    (("authentication failed", "password authentication", "eacces", "permission denied", "unauthorized", "forbidden"),
     "Authentication / authorization", "HIGH",
     "A credential or permission is wrong - often a rotated/mismatched secret or a file/volume permission problem.",
     ["Compare the secret the app uses with the one the database was initialised with",
      "Check pod securityContext / volume permissions",
      "Rotate and re-apply secrets, then restart: `kubectl -n shop rollout restart deploy/shop-backend`"]),
    (("out of memory", "oomkilled", "heap out of memory", "enomem", "javascript heap"),
     "Resource exhaustion (memory)", "CRITICAL",
     "The container exceeded its memory limit and was killed, or a memory leak is growing over time.",
     ["`kubectl -n shop describe pod <pod>` - look for OOMKilled",
      "Review Grafana memory panel for a steady climb (leak) vs a spike (load)",
      "Raise limits temporarily in helm values and investigate the leak",
      "Scale out: `kubectl -n shop scale deploy/shop-backend --replicas=4`"]),
    (("enospc", "no space left", "disk full"),
     "Resource exhaustion (disk)", "CRITICAL",
     "The node or volume is out of disk space (logs, images, or database growth).",
     ["Run `scripts/cleanup.sh --deep`", "Check `df -h` and PVC usage", "Add log rotation / increase volume size"]),
    (("econnrefused 127.0.0.1:5432", "relation", "does not exist", "syntax error", "sql"),
     "Database query / schema", "MEDIUM",
     "A query failed - missing table/migration or invalid SQL after a release.",
     ["Check the latest migration/deploy", "Inspect the failing query in the stack trace", "Roll back if it started after a deploy"]),
    (("cannot find module", "module_not_found", "syntaxerror", "unexpected token", "referenceerror", "typeerror"),
     "Application code / build error", "HIGH",
     "The running image has a code or dependency defect (bad build, missing dependency, new bug).",
     ["Identify the first bad deploy: `helm history shop -n shop`", "Roll back: `helm rollback shop -n shop`",
      "Reproduce locally with `docker compose up --build` and fix in a feature branch"]),
    (("imagepullbackoff", "errimagepull", "pull access denied", "manifest unknown"),
     "Image / registry", "HIGH",
     "Kubernetes cannot pull the image - wrong tag, registry unreachable or missing credentials.",
     ["Check the tag exists in the registry", "`kubectl -n shop describe pod <pod>` for the pull error",
      "Verify the registry address configured for the cluster"]),
    (("429", "too many requests", "rate limit"),
     "Traffic / rate limiting", "MEDIUM",
     "A client or upstream is being throttled; possible traffic spike or abusive client.",
     ["Check request-rate panel in Grafana", "Scale out or add rate limiting at the ingress"]),
]
SEV_ORDER = {"LOW": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}
DEFAULT = ("Unclassified application error", "MEDIUM",
           "No known pattern matched. Needs human investigation of the stack trace and recent changes.",
           ["Read the full stack trace", "Check what changed recently: `helm history shop -n shop`, `git log -5`",
            "Correlate the time with Grafana metrics"])


# ---------------------------------------------------------------- log loading
def parse_line(line):
    """Return a dict for a log line; understands our JSON logs and plain text."""
    line = line.strip()
    if not line:
        return None
    if line.startswith("{"):
        try:
            d = json.loads(line)
            return {"time": d.get("@timestamp", ""), "level": str(d.get("level", "info")).lower(),
                    "message": str(d.get("message", "")) + (" | " + str(d["error"]) if d.get("error") else ""),
                    "raw": line}
        except json.JSONDecodeError:
            pass
    low = line.lower()
    level = "error" if any(w in low for w in ("error", "fatal", "exception", "failed", "panic")) else "info"
    return {"time": "", "level": level, "message": line, "raw": line}


def load_file(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return [e for e in map(parse_line, fh) if e]


def load_stdin():
    return [e for e in map(parse_line, sys.stdin) if e]


def load_elastic(url, minutes, index="shop-logs-*"):
    query = {"size": 500, "sort": [{"@timestamp": "desc"}],
             "query": {"bool": {"filter": [{"range": {"@timestamp": {"gte": f"now-{minutes}m"}}}],
                                "should": [{"match": {"level": "error"}}, {"match": {"app.level": "error"}}],
                                "minimum_should_match": 1}}}
    req = urllib.request.Request(f"{url.rstrip('/')}/{index}/_search", data=json.dumps(query).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        hits = json.load(r)["hits"]["hits"]
    out = []
    for h in hits:
        src = h["_source"]
        app = src.get("app", {})
        out.append({"time": src.get("@timestamp", ""), "level": str(app.get("level", src.get("level", "error"))).lower(),
                    "message": str(app.get("message", src.get("message", ""))), "raw": json.dumps(src)})
    return out


# ---------------------------------------------------------------- analysis
def classify(text):
    low = text.lower()
    for keys, category, sev, cause, fixes in RULES:
        if any(k in low for k in keys):
            return {"category": category, "severity": sev, "root_cause": cause, "remediation": fixes}
    c, s, r, f = DEFAULT
    return {"category": c, "severity": s, "root_cause": r, "remediation": f}


def rules_engine(events):
    errors = [e for e in events if e["level"] in ("error", "fatal", "critical")]
    if not errors:
        return {"status": "healthy", "summary": "No errors found in the analysed window.", "incidents": []}
    groups = {}
    for e in errors:
        # group by message with digits stripped so "order 17" and "order 18" collapse together
        key = "".join(ch for ch in e["message"] if not ch.isdigit())[:120]
        groups.setdefault(key, []).append(e)
    incidents = []
    for _key, evs in groups.items():
        text = " ".join(x["message"] for x in evs[:5])
        info = classify(text)
        incidents.append({"count": len(evs), "example": evs[0]["message"][:300],
                          "first_seen": evs[0]["time"], "last_seen": evs[-1]["time"], **info})
    # escalate when an error repeats a lot (an outage rather than a blip)
    for inc in incidents:
        if inc["count"] >= 10 and SEV_ORDER[inc["severity"]] < SEV_ORDER["CRITICAL"]:
            inc["severity"] = "CRITICAL" if inc["severity"] == "HIGH" else "HIGH"
            inc["note"] = "severity raised: error repeated 10+ times"
    incidents.sort(key=lambda i: (-SEV_ORDER[i["severity"]], -i["count"]))
    top = incidents[0]
    return {"status": "incident", "summary": f"{len(errors)} error events in {len(incidents)} distinct problem(s). "
            f"Most severe: {top['category']} ({top['severity']}).", "incidents": incidents}


def llm_prompt(events):
    errs = [e["message"][:300] for e in events if e["level"] in ("error", "fatal")][:25]
    return ("You are a senior SRE. Analyse these application errors from an e-commerce platform running on "
            "Kubernetes. Reply ONLY with JSON: {\"summary\":str,\"incidents\":[{\"category\":str,\"severity\":"
            "\"LOW|MEDIUM|HIGH|CRITICAL\",\"root_cause\":str,\"remediation\":[str]}]}.\n\nERRORS:\n" + "\n".join(errs))


def _json_from(text):
    start, end = text.find("{"), text.rfind("}")
    return json.loads(text[start:end + 1])


def ollama_engine(events, model):
    body = json.dumps({"model": model, "prompt": llm_prompt(events), "stream": False, "format": "json"}).encode()
    host = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
    with urllib.request.urlopen(urllib.request.Request(f"{host}/api/generate", data=body), timeout=300) as r:
        res = _json_from(json.load(r)["response"])
    res["status"] = "incident"
    return res


def anthropic_engine(events, model):
    key = os.environ["ANTHROPIC_API_KEY"]
    body = json.dumps({"model": model, "max_tokens": 1500,
                       "messages": [{"role": "user", "content": llm_prompt(events)}]}).encode()
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=body, headers={
        "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        res = _json_from(json.load(r)["content"][0]["text"])
    res["status"] = "incident"
    return res


def analyse(events, engine="rules", model=None):
    base = rules_engine(events)
    if engine == "rules" or base["status"] == "healthy":
        base["engine"] = "rules"
        return base
    try:
        res = ollama_engine(events, model or "llama3.2") if engine == "ollama" else \
              anthropic_engine(events, model or "claude-sonnet-5-5")
        res["engine"] = engine
        return res
    except Exception as exc:  # LLM unavailable -> fall back so the tool never fails during an incident
        base["engine"] = f"rules (fallback: {engine} failed: {exc})"
        return base


def render(report):
    lines = ["=" * 70, f" INCIDENT ANALYSIS  [{report.get('engine')}]  {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}",
             "=" * 70, f" {report['summary']}", ""]
    for n, inc in enumerate(report.get("incidents", []), 1):
        lines += [f"[{n}] {inc.get('category')}   severity: {inc.get('severity')}"
                  + (f"   occurrences: {inc['count']}" if "count" in inc else ""),
                  f"    example   : {inc.get('example', '-')}",
                  f"    root cause: {inc.get('root_cause')}", "    remediation:"]
        lines += [f"      {i}. {step}" for i, step in enumerate(inc.get("remediation", []), 1)]
        if inc.get("note"):
            lines.append(f"    note: {inc['note']}")
        lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--file"); src.add_argument("--stdin", action="store_true")
    src.add_argument("--elastic", metavar="URL")
    ap.add_argument("--minutes", type=int, default=30, help="look-back window for --elastic")
    ap.add_argument("--engine", choices=["rules", "ollama", "anthropic"], default="rules")
    ap.add_argument("--model"); ap.add_argument("--json", action="store_true", help="machine-readable output")
    a = ap.parse_args()
    events = load_file(a.file) if a.file else load_stdin() if a.stdin else load_elastic(a.elastic, a.minutes)
    report = analyse(events, a.engine, a.model)
    print(json.dumps(report, indent=2) if a.json else render(report))
    sys.exit(0 if report["status"] == "healthy" else 1)   # non-zero = incident found (usable in CI / cron)


if __name__ == "__main__":
    main()
