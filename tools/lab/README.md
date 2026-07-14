# Local aihaus lab

The generated lab lives at ignored `.aihaus-lab/consumer`. It is a persistent
nested Git repository with two local baseline tags. Only this controller,
fixture, and the acceptance tests are committed by the outer repository.

```text
node tools/aihaus-lab.mjs init
node tools/aihaus-lab.mjs status
node tools/aihaus-lab.mjs reset
node tools/aihaus-lab.mjs verify
```

`init --force` and `reset` are destructive only after realpath containment and
nested-repository identity checks pass. The fixture contains no credentials,
deploy configuration, or external-service dependency.
