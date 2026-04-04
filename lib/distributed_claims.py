#!/usr/bin/env python3
"""
SHTD Flow — Distributed task coordination via S3.

Extends task_claims.py with:
- S3-based distributed locking (fleet scenarios, not just local)
- Spec claim concept (claim spec generation rights for a feature)
- Conflict detection (race window, second instance backs off)
- Heartbeat/lease expiry (configurable timeout, default 10min)
- Metrics (contention rate, completion time, latency)

S3 Layout:
    s3://{bucket}/shtd-claims/{project}/tasks/{task_id}.json
    s3://{bucket}/shtd-claims/{project}/specs/{spec_name}.json
    s3://{bucket}/shtd-claims/{project}/heartbeats/{instance_id}.json
    s3://{bucket}/shtd-claims/{project}/metrics.jsonl

Env vars:
    SHTD_S3_BUCKET       — S3 bucket for claim storage (required)
    SHTD_INSTANCE_ID     — unique instance identifier (default: local-{pid})
    SHTD_LEASE_TIMEOUT   — claim expiry in seconds (default: 600)
    SHTD_RACE_WINDOW     — race detection window in seconds (default: 5)
    AWS_PROFILE          — AWS credentials profile
    AWS_DEFAULT_REGION   — AWS region (default: us-east-2)

Usage:
    python distributed_claims.py claim T001 --project my-project --session abc123
    python distributed_claims.py spec-claim 042-feature --project my-project --session abc123
    python distributed_claims.py heartbeat --project my-project
    python distributed_claims.py status --project my-project
    python distributed_claims.py metrics --project my-project
"""

import argparse, json, os, sys
from datetime import datetime, timezone

LEASE_TIMEOUT = int(os.environ.get("SHTD_LEASE_TIMEOUT", "600"))  # 10min default
RACE_WINDOW = int(os.environ.get("SHTD_RACE_WINDOW", "5"))  # 5s race detection


def _now():
    return datetime.now(timezone.utc).isoformat()


def _age_seconds(iso_ts):
    try:
        dt = datetime.fromisoformat(iso_ts.replace("Z", "+00:00"))
        return (datetime.now(timezone.utc) - dt).total_seconds()
    except:
        return float("inf")


def _s3_client():
    import boto3
    profile = os.environ.get("AWS_PROFILE")
    region = os.environ.get("AWS_DEFAULT_REGION", "us-east-2")
    session = boto3.Session(profile_name=profile, region_name=region)
    return session.client("s3")


def _bucket():
    b = os.environ.get("SHTD_S3_BUCKET")
    if not b:
        print(json.dumps({"error": "SHTD_S3_BUCKET not set"}))
        sys.exit(1)
    return b


def _prefix(project):
    return f"shtd-claims/{project}"


def _s3_get(s3, bucket, key):
    try:
        resp = s3.get_object(Bucket=bucket, Key=key)
        return json.loads(resp["Body"].read().decode())
    except s3.exceptions.NoSuchKey:
        return None
    except Exception as e:
        if "NoSuchKey" in str(e) or "404" in str(e):
            return None
        raise


def _s3_put(s3, bucket, key, data):
    s3.put_object(
        Bucket=bucket, Key=key,
        Body=json.dumps(data, indent=2).encode(),
        ContentType="application/json"
    )


def _s3_list(s3, bucket, prefix):
    results = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            results.append(obj["Key"])
    return results


def _s3_delete(s3, bucket, key):
    try:
        s3.delete_object(Bucket=bucket, Key=key)
    except:
        pass


def _log_metric(s3, bucket, project, event, data):
    key = f"{_prefix(project)}/metrics.jsonl"
    entry = {"ts": _now(), "event": event, **data}
    existing = ""
    try:
        resp = s3.get_object(Bucket=bucket, Key=key)
        existing = resp["Body"].read().decode()
    except:
        pass
    existing += json.dumps(entry) + "\n"
    s3.put_object(Bucket=bucket, Key=key, Body=existing.encode(), ContentType="text/plain")


# --- Task Claims ---

def claim_task(task_id, project, session, instance_id):
    s3 = _s3_client()
    bucket = _bucket()
    key = f"{_prefix(project)}/tasks/{task_id}.json"

    existing = _s3_get(s3, bucket, key)
    if existing:
        age = _age_seconds(existing.get("heartbeat", existing.get("claimed_at", "")))
        if age < LEASE_TIMEOUT:
            claim_age = _age_seconds(existing.get("claimed_at", ""))
            if claim_age < RACE_WINDOW:
                _log_metric(s3, bucket, project, "race_detected", {
                    "task": task_id, "winner": existing["instance"],
                    "loser": instance_id
                })
            print(json.dumps({
                "claimed": False, "owner": existing.get("instance"),
                "session": existing.get("session", "?")[:12],
                "expires_in": int(LEASE_TIMEOUT - age)
            }))
            return False
        else:
            _log_metric(s3, bucket, project, "lease_expired", {
                "task": task_id, "prev_owner": existing["instance"],
                "age_seconds": int(age)
            })

    claim_data = {
        "task": task_id, "session": session, "instance": instance_id,
        "claimed_at": _now(), "heartbeat": _now(), "status": "active"
    }
    _s3_put(s3, bucket, key, claim_data)
    _log_metric(s3, bucket, project, "task_claimed", {
        "task": task_id, "instance": instance_id
    })
    print(json.dumps({"claimed": True, "task": task_id}))
    return True


def release_task(task_id, project, session, instance_id, status="completed"):
    s3 = _s3_client()
    bucket = _bucket()
    key = f"{_prefix(project)}/tasks/{task_id}.json"

    existing = _s3_get(s3, bucket, key)
    if existing and existing.get("instance") == instance_id:
        duration = _age_seconds(existing.get("claimed_at", ""))
        _s3_delete(s3, bucket, key)
        _log_metric(s3, bucket, project, "task_released", {
            "task": task_id, "instance": instance_id,
            "status": status, "duration_seconds": int(duration)
        })
        print(json.dumps({"released": True, "task": task_id, "duration": int(duration)}))
        return True

    print(json.dumps({"released": False, "reason": "not_owner"}))
    return False


# --- Spec Claims ---

def claim_spec(spec_name, project, session, instance_id):
    """Claim exclusive spec generation rights for a feature."""
    s3 = _s3_client()
    bucket = _bucket()
    key = f"{_prefix(project)}/specs/{spec_name}.json"

    existing = _s3_get(s3, bucket, key)
    if existing:
        age = _age_seconds(existing.get("heartbeat", existing.get("claimed_at", "")))
        if age < LEASE_TIMEOUT:
            print(json.dumps({
                "claimed": False, "type": "spec", "owner": existing.get("instance"),
                "expires_in": int(LEASE_TIMEOUT - age)
            }))
            return False
        _log_metric(s3, bucket, project, "spec_lease_expired", {
            "spec": spec_name, "prev_owner": existing["instance"]
        })

    claim_data = {
        "spec": spec_name, "session": session, "instance": instance_id,
        "claimed_at": _now(), "heartbeat": _now(), "status": "speccing"
    }
    _s3_put(s3, bucket, key, claim_data)
    _log_metric(s3, bucket, project, "spec_claimed", {
        "spec": spec_name, "instance": instance_id
    })
    print(json.dumps({"claimed": True, "type": "spec", "spec": spec_name}))
    return True


def release_spec(spec_name, project, instance_id, status="completed"):
    s3 = _s3_client()
    bucket = _bucket()
    key = f"{_prefix(project)}/specs/{spec_name}.json"

    existing = _s3_get(s3, bucket, key)
    if existing and existing.get("instance") == instance_id:
        _s3_delete(s3, bucket, key)
        _log_metric(s3, bucket, project, "spec_released", {
            "spec": spec_name, "instance": instance_id, "status": status
        })
        print(json.dumps({"released": True, "type": "spec", "spec": spec_name}))
        return True
    print(json.dumps({"released": False, "type": "spec"}))
    return False


# --- Heartbeat ---

def heartbeat(project, instance_id):
    """Update heartbeat for all claims owned by this instance."""
    s3 = _s3_client()
    bucket = _bucket()
    prefix = _prefix(project)
    updated = 0

    for sub in ("tasks", "specs"):
        keys = _s3_list(s3, bucket, f"{prefix}/{sub}/")
        for key in keys:
            data = _s3_get(s3, bucket, key)
            if data and data.get("instance") == instance_id:
                data["heartbeat"] = _now()
                _s3_put(s3, bucket, key, data)
                updated += 1

    hb_key = f"{prefix}/heartbeats/{instance_id}.json"
    _s3_put(s3, bucket, hb_key, {
        "instance": instance_id, "heartbeat": _now(),
        "claims_refreshed": updated
    })

    print(json.dumps({"heartbeat": True, "instance": instance_id, "refreshed": updated}))


# --- Status ---

def status(project):
    s3 = _s3_client()
    bucket = _bucket()
    prefix = _prefix(project)
    result = {"project": project, "tasks": {}, "specs": {}, "instances": []}

    for key in _s3_list(s3, bucket, f"{prefix}/tasks/"):
        data = _s3_get(s3, bucket, key)
        if data:
            age = _age_seconds(data.get("heartbeat", data.get("claimed_at", "")))
            tid = data.get("task", os.path.basename(key).replace(".json", ""))
            result["tasks"][tid] = {
                "instance": data.get("instance"),
                "session": data.get("session", "?")[:12],
                "age": int(age),
                "expired": age >= LEASE_TIMEOUT
            }

    for key in _s3_list(s3, bucket, f"{prefix}/specs/"):
        data = _s3_get(s3, bucket, key)
        if data:
            age = _age_seconds(data.get("heartbeat", data.get("claimed_at", "")))
            name = data.get("spec", os.path.basename(key).replace(".json", ""))
            result["specs"][name] = {
                "instance": data.get("instance"),
                "age": int(age),
                "expired": age >= LEASE_TIMEOUT
            }

    for key in _s3_list(s3, bucket, f"{prefix}/heartbeats/"):
        data = _s3_get(s3, bucket, key)
        if data:
            age = _age_seconds(data.get("heartbeat", ""))
            result["instances"].append({
                "instance": data.get("instance"),
                "last_heartbeat_age": int(age),
                "alive": age < LEASE_TIMEOUT
            })

    print(json.dumps(result, indent=2))


# --- Metrics ---

def metrics(project):
    s3 = _s3_client()
    bucket = _bucket()
    key = f"{_prefix(project)}/metrics.jsonl"

    try:
        resp = s3.get_object(Bucket=bucket, Key=key)
        lines = resp["Body"].read().decode().strip().split("\n")
    except:
        print(json.dumps({"error": "no metrics data"}))
        return

    events = []
    for line in lines:
        try:
            events.append(json.loads(line))
        except:
            continue

    counts = {}
    durations = []
    races = 0
    expirations = 0
    instances = set()

    for e in events:
        ev = e.get("event", "")
        counts[ev] = counts.get(ev, 0) + 1
        if e.get("instance"):
            instances.add(e["instance"])
        if ev == "task_released" and e.get("duration_seconds"):
            durations.append(e["duration_seconds"])
        if ev == "race_detected":
            races += 1
        if ev in ("lease_expired", "spec_lease_expired"):
            expirations += 1

    total_claims = counts.get("task_claimed", 0)
    contention_rate = races / total_claims if total_claims > 0 else 0
    avg_duration = sum(durations) / len(durations) if durations else 0

    result = {
        "project": project,
        "total_events": len(events),
        "event_counts": counts,
        "unique_instances": len(instances),
        "contention_rate": round(contention_rate, 3),
        "races_detected": races,
        "lease_expirations": expirations,
        "avg_task_duration_seconds": int(avg_duration),
        "task_completions": counts.get("task_released", 0),
    }
    print(json.dumps(result, indent=2))


# --- CLI ---

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="SHTD Distributed Task Coordination")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("claim", help="Claim a task")
    sp.add_argument("task_id")
    sp.add_argument("--project", required=True)
    sp.add_argument("--session", required=True)
    sp.add_argument("--instance", default=os.environ.get("SHTD_INSTANCE_ID", f"local-{os.getpid()}"))

    sp = sub.add_parser("release", help="Release a task")
    sp.add_argument("task_id")
    sp.add_argument("--project", required=True)
    sp.add_argument("--session", required=True)
    sp.add_argument("--instance", default=os.environ.get("SHTD_INSTANCE_ID", f"local-{os.getpid()}"))
    sp.add_argument("--status", default="completed")

    sp = sub.add_parser("spec-claim", help="Claim spec generation rights")
    sp.add_argument("spec_name")
    sp.add_argument("--project", required=True)
    sp.add_argument("--session", required=True)
    sp.add_argument("--instance", default=os.environ.get("SHTD_INSTANCE_ID", f"local-{os.getpid()}"))

    sp = sub.add_parser("spec-release", help="Release spec claim")
    sp.add_argument("spec_name")
    sp.add_argument("--project", required=True)
    sp.add_argument("--instance", default=os.environ.get("SHTD_INSTANCE_ID", f"local-{os.getpid()}"))
    sp.add_argument("--status", default="completed")

    sp = sub.add_parser("heartbeat", help="Refresh heartbeat for all owned claims")
    sp.add_argument("--project", required=True)
    sp.add_argument("--instance", default=os.environ.get("SHTD_INSTANCE_ID", f"local-{os.getpid()}"))

    sp = sub.add_parser("status", help="Show all claims and instances")
    sp.add_argument("--project", required=True)

    sp = sub.add_parser("metrics", help="Show coordination metrics")
    sp.add_argument("--project", required=True)

    a = p.parse_args()
    {
        "claim": lambda: claim_task(a.task_id, a.project, a.session, a.instance),
        "release": lambda: release_task(a.task_id, a.project, a.session, a.instance, a.status),
        "spec-claim": lambda: claim_spec(a.spec_name, a.project, a.session, a.instance),
        "spec-release": lambda: release_spec(a.spec_name, a.project, a.instance, a.status),
        "heartbeat": lambda: heartbeat(a.project, a.instance),
        "status": lambda: status(a.project),
        "metrics": lambda: metrics(a.project),
    }[a.cmd]()
