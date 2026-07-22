# aihaus maintainer router

Read `AGENTS.md`, then `pkg/.aihaus/MAP.md` and
`pkg/.aihaus/contracts/harness.md`. Load one room and the minimum project
context needed for the task.

The public product is a downloadable, repository-local package. Do not add a
site, hosted service, global agent mutation, or hosted state.

Validate package changes with:

```text
node tools/run-contract-tests.mjs
```

Generated dogfood state belongs only under ignored `.aihaus-lab/`.
