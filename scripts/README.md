# Scripts

Routine setup, container checks and manifest validation run through
`ansible/main.yml`. These scripts remain because they either bootstrap Ansible
itself or implement timed measurements/schema checks more clearly in Python.

| Script | Purpose |
| --- | --- |
| prepare-kubespray.sh | Bootstrap the pinned Kubespray checkout and controller Python environment. |
| setup-validation.sh | Bootstrap the pinned CI Python/Ansible environment and Kubespray checkout. |
| validate-custom-resources.py | Validate custom objects against bundled CRD schemas; called by the Ansible validation role. |
| check-capacity.py | Measure bounded traffic stages and save request/metrics evidence. |
| run-failure-exercise.py | Run a selected timed incident exercise with restoration and evidence collection. |

Run commands from the repository root. For the complete lab comparison:

```sh
source .venv/bin/activate
python scripts/check-capacity.py
```

The default is 10 then 30 requests/second, 120 seconds each. `--duration` and
`--rates` allow smaller smoke checks within those bounds. Results stay under
`.state/capacity/`; a smoke check does not replace the full capacity evidence.

The incident runner accepts `eviction` or `http503`. It intentionally changes the
running app and must be scheduled as an exercise. It records evidence under
`.state/chaos/`, prevents concurrent exercises, restores changes on exit, and uses
an in-pod watchdog for the HTTP fault. Use `--help` to inspect arguments without
making changes. See [the exercise procedure](../docs/failure-exercises.md).
