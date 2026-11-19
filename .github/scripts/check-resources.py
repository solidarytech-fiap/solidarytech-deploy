"""Politica de rightsizing: todo container precisa de requests E limits.

Uso: kustomize build k8s/overlays/prod | python3 .github/scripts/check-resources.py
"""
import sys

import yaml

bad = []
for doc in yaml.safe_load_all(sys.stdin):
    if not doc or doc.get("kind") not in ("Deployment", "CronJob", "Job"):
        continue
    if doc["kind"] == "CronJob":
        spec = doc["spec"]["jobTemplate"]["spec"]["template"]["spec"]
    else:
        spec = doc["spec"]["template"]["spec"]
    for c in spec.get("containers", []) + spec.get("initContainers", []):
        res = c.get("resources", {})
        name = f'{doc["kind"]}/{doc["metadata"]["name"]}:{c["name"]}'
        if not res.get("requests") or not res.get("limits"):
            bad.append(name)
        else:
            print(f"ok  {name}  requests={res['requests']} limits={res['limits']}")

if bad:
    print("SEM requests/limits:", ", ".join(bad))
    sys.exit(1)
