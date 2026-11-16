#!/usr/bin/env python3
"""Run one bounded lab exercise and retain measured evidence outside Git."""

import argparse
import fcntl
import datetime
import json
import os
import pathlib
import signal
import subprocess
import threading
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
K = str(ROOT / ".state/artifacts/kubectl")
SELECTOR = "app.kubernetes.io/instance=app,app.kubernetes.io/component=nginx"


def kubectl(*args, body=None, check=True):
    r = subprocess.run(
        [K, *args],
        input=json.dumps(body) if body is not None else None,
        text=True,
        capture_output=True,
        timeout=25,
    )
    if check and r.returncode:
        raise RuntimeError(r.stderr.strip())
    return r


def obj(*args):
    return json.loads(kubectl(*args, "-o", "json").stdout)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def ready(p):
    return not p["metadata"].get("deletionTimestamp") and any(
        c["type"] == "Ready" and c["status"] == "True"
        for c in p["status"].get("conditions", [])
    )


def pods():
    return obj("-n", "dpg-app", "get", "pods", "-l", SELECTOR)["items"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", choices=["eviction", "http503"])
    args = parser.parse_args()
    os.chdir(ROOT)
    os.environ["KUBECONFIG"] = str(ROOT / ".state/artifacts/admin.conf")
    os.umask(0o077)
    chaos_root = ROOT / ".state/chaos"
    chaos_root.mkdir(parents=True, exist_ok=True)
    lock = (chaos_root / "run.lock").open("a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit("Another failure exercise is already running")
    run_id = (
        datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        + "-"
        + args.scenario
    )
    folder = ROOT / ".state/chaos" / run_id
    folder.mkdir(parents=True)
    events = []

    def event(name, **data):
        row = {"time": now(), "event": name, **data}
        events.append(row)
        (folder / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(json.dumps(row), flush=True)

    phase = "baseline"
    stop = threading.Event()
    samples = []
    modified = []
    backup = "/tmp/dpg-chaos-" + run_id + ".conf"
    forward = None

    def traffic():
        """Record two verified HTTPS probes per second until cleanup signals stop."""
        with (folder / "requests.jsonl").open("w") as out:
            while not stop.is_set():
                start = time.monotonic()
                stamp = now()
                current_phase = phase
                r = subprocess.run(
                    [
                        "curl",
                        "--noproxy",
                        "*",
                        "--interface",
                        "192.168.56.1",
                        "--cacert",
                        ".state/tls/ca.crt",
                        "--resolve",
                        "app.dpg.test:443:192.168.56.10",
                        "--connect-timeout",
                        "2",
                        "--max-time",
                        "3",
                        "--silent",
                        "--output",
                        "/dev/null",
                        "--write-out",
                        "%{http_code} %{time_total}",
                        "https://app.dpg.test/",
                    ],
                    capture_output=True,
                    text=True,
                )
                parts = r.stdout.split()
                row = {
                    "time": stamp,
                    "phase": current_phase,
                    "code": int(parts[0]) if parts else 0,
                    "seconds": float(parts[1]) if len(parts) > 1 else None,
                    "curl_exit": r.returncode,
                }
                samples.append(row)
                out.write(json.dumps(row) + "\n")
                out.flush()
                stop.wait(max(0, 0.5 - (time.monotonic() - start)))

    def prom(path):
        return json.load(
            urllib.request.urlopen("http://127.0.0.1:19096" + path, timeout=5)
        )

    def snapshot(name):
        values = {}
        for q in [
            "dpg:slo_bad_ratio:24h",
            "dpg:slo_budget_remaining:ratio",
            'sum(traefik_service_requests_total{exported_service="dpg-app-app-nginx-http@kubernetes"}) by(code)',
        ]:
            values[q] = prom("/api/v1/query?" + urllib.parse.urlencode({"query": q}))[
                "data"
            ]["result"]
        (folder / (name + ".json")).write_text(
            json.dumps({"time": now(), "queries": values}, indent=2) + "\n"
        )

    seen = {}

    def observe():
        for g in prom("/api/v1/rules")["data"]["groups"]:
            if g["name"] != "dpg.slo":
                continue
            for r in g["rules"]:
                if r["type"] != "alerting":
                    continue
                state = r["state"]
                if seen.get(r["name"]) != state:
                    event("alert_state", alert=r["name"], state=state)
                    seen[r["name"]] = state
        return seen.get("DpgAvailabilityBurnFast") == "firing"

    start_time = now()

    def deliveries():
        text = kubectl(
            "-n",
            "monitoring",
            "logs",
            "deployment/dpg-alert-receiver",
            "--since-time=" + start_time,
        ).stdout
        (folder / "receiver.log").write_text(text)
        return text

    def restore():
        """Undo every recorded config edit, including during exception cleanup."""
        for name in list(modified):
            r = kubectl(
                "-n",
                "dpg-app",
                "exec",
                name,
                "-c",
                "nginx",
                "--",
                "sh",
                "-c",
                f"if test -f {backup}; then cp {backup} /tmp/default.conf && nginx -t && nginx -s reload && rm {backup}; fi",
                check=False,
            )
            if r.returncode:
                event("restore_error", pod=name, error=r.stderr.strip())
            else:
                modified.remove(name)
                event("config_restored", pod=name)

    def interrupted(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    thread = None
    try:
        initial = pods()
        if len(initial) != 2 or not all(ready(p) for p in initial):
            raise RuntimeError("Need exactly two healthy NGINX pods")
        for p in initial:
            if any(s.get("restartCount", 0) for s in p["status"]["containerStatuses"]):
                raise RuntimeError(
                    "NGINX pods already have restarts; inspect before testing"
                )
        if (
            obj("-n", "dpg-app", "get", "pdb", "app-nginx")["status"][
                "disruptionsAllowed"
            ]
            != 1
        ):
            raise RuntimeError("Expected one permitted NGINX disruption")
        with (folder / "forward.log").open("w") as log:
            forward = subprocess.Popen(
                [
                    K,
                    "-n",
                    "monitoring",
                    "port-forward",
                    "service/monitoring-kube-prometheus-prometheus",
                    "19096:9090",
                ],
                stdout=log,
                stderr=log,
            )
        for _ in range(20):
            try:
                prom("/api/v1/rules")
                break
            except OSError:
                time.sleep(0.5)
        snapshot("before")
        observe()
        if any(state != "inactive" for state in seen.values()):
            raise RuntimeError(
                "An application alert is already active; inspect before testing"
            )
        event("baseline_started", scenario=args.scenario)
        thread = threading.Thread(target=traffic, daemon=True)
        thread.start()
        time.sleep(30)
        if any(s["code"] != 200 for s in samples):
            raise RuntimeError("Baseline request failed")
        phase = "fault"
        event("fault_started")
        if args.scenario == "eviction":
            target = initial[0]["metadata"]["name"]
            other = initial[1]["metadata"]["name"]

            def eviction(name, dry=False):
                body = {
                    "apiVersion": "policy/v1",
                    "kind": "Eviction",
                    "metadata": {"name": name, "namespace": "dpg-app"},
                }
                if dry:
                    body["deleteOptions"] = {"dryRun": ["All"]}
                return kubectl(
                    "create",
                    "--raw",
                    f"/api/v1/namespaces/dpg-app/pods/{name}/eviction",
                    "-f",
                    "-",
                    body=body,
                    check=False,
                )

            r = eviction(target)
            if r.returncode:
                raise RuntimeError(r.stderr)
            event("eviction_accepted", pod=target)
            r = eviction(other, True)
            event(
                "second_eviction_dry_run",
                accepted=r.returncode == 0,
                response=(r.stderr or r.stdout).strip(),
            )
            if r.returncode == 0 or "disruption budget" not in r.stderr.lower():
                raise RuntimeError("Expected PDB to reject second eviction")
            previous = set(p["metadata"]["uid"] for p in initial)
            for _ in range(90):
                current = pods()
                if (
                    len(current) == 2
                    and all(ready(p) for p in current)
                    and any(p["metadata"]["uid"] not in previous for p in current)
                ):
                    break
                time.sleep(1)
            else:
                raise RuntimeError("Replacement did not become Ready within 90 seconds")
            event("replacement_ready", pods=[p["metadata"]["name"] for p in current])
            phase = "recovery"
            time.sleep(30)
            observe()
        else:
            for p in initial:
                name = p["metadata"]["name"]
                modified.append(name)
                # The in-pod watchdog restores the original file even if this host process stops.
                script = f"""set -eu
cp /tmp/default.conf {backup}
(sleep 240; if test -f {backup}; then cp {backup} /tmp/default.conf; nginx -t && nginx -s reload; rm -f {backup}; fi) >/tmp/dpg-chaos-watchdog.log 2>&1 </dev/null &
sed '/location = \\/ {{/a\\        return 503;' {backup} > /tmp/default.conf
nginx -t
nginx -s reload
"""
                kubectl(
                    "-n",
                    "dpg-app",
                    "exec",
                    name,
                    "-c",
                    "nginx",
                    "--",
                    "sh",
                    "-c",
                    script,
                )
                event("config_injected", pod=name)
            deadline = time.monotonic() + 210
            delivered = False
            while time.monotonic() < deadline:
                firing = observe()
                if (
                    firing
                    and '"status":"firing","alertname":"DpgAvailabilityBurnFast"'
                    in deliveries()
                ):
                    delivered = True
                    event("burn_notification_received")
                    break
                time.sleep(5)
            phase = "recovery"
            restore()
            event("fault_ended", notification_received=delivered)
            if not delivered:
                raise RuntimeError(
                    "Burn notification not received before the restore deadline"
                )
            deadline = time.monotonic() + 390
            while time.monotonic() < deadline:
                observe()
                text = deliveries()
                if (
                    '"status":"resolved","alertname":"DpgAvailabilityBurnFast"' in text
                    and seen.get("DpgAvailabilityBurnSlow") == "inactive"
                ):
                    event("burn_alerts_recovered")
                    break
                time.sleep(5)
            else:
                raise RuntimeError("Burn alert did not clear within recovery window")
        current = pods()
        if len(current) != 2 or not all(ready(p) for p in current):
            raise RuntimeError("NGINX replicas are not healthy after recovery")
        if len(samples) < 10 or any(s["code"] != 200 for s in samples[-10:]):
            raise RuntimeError("Recent recovery requests are not all successful")
        event("recovery_verified", ready_replicas=len(current), recent_successes=10)
        snapshot("after")
        deliveries()
        event("exercise_complete")
    finally:
        restore()
        stop.set()
        if thread:
            thread.join(timeout=5)
        if forward:
            forward.terminate()
            forward.wait(timeout=10)
        summary = {}
        for segment in ["baseline", "fault", "recovery"]:
            rows = [s for s in samples if s["phase"] == segment]
            n = len(rows)
            summary[segment] = {
                "requests": n,
                "codes": {
                    str(c): sum(s["code"] == c for s in rows)
                    for c in sorted(set(s["code"] for s in rows))
                },
                "availability_bad": sum(
                    s["code"] >= 500 or s["code"] == 0 for s in rows
                ),
                "latency_bad": sum(
                    s["seconds"] is not None and s["seconds"] > 0.3 for s in rows
                ),
                "transport_failures": sum(s["curl_exit"] != 0 for s in rows),
                "max_seconds": max((s["seconds"] or 0 for s in rows), default=0),
            }
        (folder / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print("Evidence: " + str(folder.relative_to(ROOT)), flush=True)
        print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
