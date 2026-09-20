# Repository working rules

- Preserve the existing MQL5 initialization, update, cleanup, and getter APIs.
- Keep each change to one purpose and a reviewable, independently reversible scope.
- Work on a feature branch. Commit one completed unit, validate that commit locally,
  then push it before starting the next unit. Never push directly to `main`.
- Open a PR targeting `main`, review its complete diff, resolve review findings,
  and use squash merge only after required local validation succeeds.
- Use `python tools/check_all.py` for commit validation and install the shared hooks
  with `python tools/setup_hooks.py`. Missing tools or interrupted checks are failures.
- Do not introduce GitHub hosted workflows. Publish `local/validation` with
  `python tools/publish_validation.py --pr NUMBER` only after the tested commit is pushed.
- Fetch the latest `main`, update the branch, and rerun checks if the base changes.
  Do not copy a success status or validation report to another commit.
- Keep a status report explicit about which checks ran. Static MQL5 checks are not
  a replacement for MetaEditor compilation or detector runtime tests.
- Keep English documentation authoritative and update translated README links.
- Never commit generated models, credentials, terminal data, or validation logs.
