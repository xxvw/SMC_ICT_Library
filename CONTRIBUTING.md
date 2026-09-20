# Contributing

Use a feature branch and a pull request for every change to `main`. Keep each PR to
one purpose that can be reviewed, tested, and reverted independently. After each
completed unit: commit, validate locally, and push before starting another unit.
Review the final diff and resolve comments before squash merging. Maintainer
self-review is permitted; external approval is not initially mandatory.

## Local setup

Python 3.11.8 or newer, Git, and GitHub CLI (`gh`) are required. Install development
dependencies separately from optional MT5 and model-training dependencies:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python tools/setup_hooks.py
```

Activate the environment or use its Python executable for the commands below.
The hook uses `.venv/bin/python`, then `python3`; set `SMC_PYTHON` to an absolute
Python executable when using another environment (including Windows).

## Validate and publish a small PR

```sh
git fetch origin
git switch -c fix/one-purpose origin/main
# Make and review one change, then commit it.
git add path/to/changed-file
git commit -m "Describe one change"
python tools/check_all.py
git push -u origin HEAD
gh pr create --base main
python tools/publish_validation.py --pr NUMBER
```

The validator requires a clean working tree and exports the exact commit to a
temporary directory. `.validation/report.json` records its SHA, `origin/main` SHA,
profile, commands, and results. The bootstrap profile currently runs Python syntax,
focused Ruff checks, Python tests, MQL5 static checks, and validation-tool tests.
It does **not** claim MetaEditor compilation, detector runtime tests, or external
language sample execution. These become required as their tooling is introduced.

The pre-push hook rejects updates and deletions whose destination is
`refs/heads/main`, including `feature:main` refspecs. It validates every pushed
commit using an isolated archive and never publishes statuses. Missing dependencies,
failed commands, and interrupted runs cannot produce a successful report.

Status publication is a separate action after push. It refreshes `origin/main`,
requires that main is an ancestor of the PR head, and checks that local HEAD, the
validated commit, and the remote PR head all match. Every required check must pass.
If main advances, update the branch and run validation again. Reports are local
maintainer attestations; GitHub credentials and the local environment must be trusted.

## Repository settings

Maintainers configure `main` protection to require a PR, the `local/validation`
status, an up-to-date branch, and resolution of review conversations. Apply these
rules to administrators; disallow direct pushes, force pushes, and branch deletion.
Set the required approving review count to zero during initial operation. Enable
squash merging and disable merge commits and rebase merging. These server settings
complement the local hook; installing a hook alone does not enforce remote policy.

No GitHub hosted runner is required. Validation must run locally; never register a
success for skipped tools or copy a status from a different commit.

## Compatibility and documentation

Preserve existing public APIs and CSV field names. Add focused tests for changed
behavior and document new concept definitions and configuration. Keep the English
README and available translations linked. Do not include secrets, generated models,
compiled terminal files, or broker history in commits.
