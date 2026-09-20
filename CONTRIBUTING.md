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

The full gate also requires MetaTrader 5 with MetaEditor and the standard MQL5
includes, Node.js 22+ with npm, Go 1.22+, the .NET 10 SDK, Rust 1.82+ with Cargo
and Clippy, and JDK 21+ with Maven. Install these toolchains on the machine that
will validate and merge PRs, and put their commands on `PATH`. Prepare dependencies:

```sh
npm ci --prefix examples/typescript --no-audit --no-fund
dotnet restore examples/csharp/SnapshotReader.csproj
cargo fetch --manifest-path examples/rust/Cargo.toml --locked
rustup component add clippy
mvn --batch-mode -f examples/java/pom.xml dependency:go-offline
```

The standard MT5 installation is discovered on Windows and macOS. For another
installation, set `MQL5_METAEDITOR` to its MetaEditor executable and
`MQL5_INCLUDE_DIR` to its standard `MQL5/Include` directory. Wine installations
also need `MQL5_WINE` and `WINEPREFIX`. Set `MQL5_TERMINAL` and
`MQL5_DEFAULT_SYMBOLS` if the terminal executable and public default symbol
definitions are not alongside MetaEditor. See the configuration docstrings in
[the compiler checker](tools/check_mql5_compile.py) and
[the runtime runner](tools/run_mql5_tests.py). Runtime fixtures use fresh portable
terminals without copying account configuration or enabling trading.

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
profile fingerprint, commands, runtime versions, and results. The default `full`
profile requires Python syntax and focused Ruff checks, Python and validation-tool
tests, MQL5 static checks, local documentation links, fresh MetaEditor compilation
of every entry point, every real MQL5 fixture, and all six external language
readers. Each reader is built and unit-tested once, then checked against the shared
fixture and every snapshot emitted by the real MQL5 exporter during that run.
Runtime manifest coverage, report identity, artifact freshness, JSON Schema, and
SHA-256 checksums are verified before consuming any generated export.

Use `python tools/check_all.py --profile fast` for iteration. This runs Python,
MQL5 static, validation-tool, and documentation checks. It does not compile MQL5,
start MT5, or build the six readers, and it cannot publish `local/validation`.

The pre-push hook rejects updates and deletions whose destination is
`refs/heads/main`, including `feature:main` refspecs. It validates every pushed
commit with the `fast` profile in an isolated archive and never publishes statuses. Missing dependencies,
failed commands, and interrupted runs cannot produce a successful report.

Status publication is a separate action after push. It refreshes `origin/main`,
requires that main is an ancestor of the PR head, and checks that local HEAD, the
validated commit, and the remote PR head all match. Every required full-profile
check must pass, using the current commands and tool fingerprint. Old bootstrap,
fast, incomplete, or changed-profile reports are rejected. A full report includes
the Python version, reader tool versions, and exact MetaEditor/terminal binary hashes.
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
