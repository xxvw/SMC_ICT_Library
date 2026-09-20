# Development and local validation

[Documentation](README.md) · [Contributing](../CONTRIBUTING.md)

All work uses a feature branch and a PR targeting `main`. Keep each commit and PR focused on one purpose, small enough to review and reverse independently. The shared pre-push hook rejects direct pushes to `main`; repository protection also requires a PR, an up-to-date base, and `local/validation`. Use squash merge after reviewing the entire diff and resolving findings. The initial approval-count setting is zero; review is still part of the workflow.

## Prepare the tools

Use Python 3.11.8 or newer and install the development dependencies from the repository root:

```sh
python -m pip install -r requirements-dev.txt
python tools/setup_hooks.py
```

Complete validation requires MetaEditor and an MT5 terminal, plus the toolchains specified in the [Python](../examples/python/README.md), [TypeScript](../examples/typescript/README.md), [C#](../examples/csharp/README.md), [Go](../examples/go/README.md), [Java](../examples/java/README.md), and [Rust](../examples/rust/README.md) sample guides. Install those dependencies locally before running the complete gate. A missing compiler, runtime, package, or interrupted check is a failure, never a skipped success.

The MQL5 tooling supports native Windows and MT5 under Wine, including the macOS MT5 application. It attempts discovery; configure explicit paths for a custom installation:

| Environment variable | Value |
| --- | --- |
| `MQL5_METAEDITOR` | Host filesystem path to `MetaEditor64.exe` |
| `MQL5_INCLUDE_DIR` | MT5's standard `MQL5/Include` directory |
| `MQL5_TERMINAL` | Host filesystem path to `terminal64.exe` |
| `MQL5_DEFAULT_SYMBOLS` | Public default symbol data used by isolated runtime tests, if discovery fails |
| `MQL5_WINE` | Wine executable, for a Wine installation |
| `WINEPREFIX` | Existing MT5 Wine prefix, for a Wine installation |

Use host filesystem paths in environment overrides. Under Wine, use macOS/Linux paths rather than Wine drive paths. Compilation stages sources in a fresh directory and checks the result in that invocation's fresh MetaEditor log. An executable exit code alone cannot establish successful MQL5 compilation. Detector runtime tests execute in an isolated terminal with synthetic test inputs; the runtime tool verifies that the expected test run actually completed.

## Validate and publish a completed unit

Fetch the latest `main`, update the feature branch as necessary, review the diff, and commit the completed unit. Then validate that exact clean commit:

```sh
python tools/check_all.py
```

The complete gate includes Python checks, MQL5 static checks, actual MetaEditor compilation, detector runtime tests, cross-language sample checks, and documentation-link checks. `check_all.py` validates a commit snapshot and records which checks ran. A fast/development profile cannot publish a merge-success status. Static analysis does not replace compilation or runtime execution.

Push the tested commit before starting the next unit, open its PR, and publish its local result:

```sh
git push -u origin HEAD
# Replace 123 with the PR number for this branch.
python tools/publish_validation.py --pr 123
```

Publication checks the report's commit SHA against the pushed PR head and checks the base. It must not copy success to another SHA. If `main` changes, fetch it, update the feature branch, rerun validation, push, and publish a new result. A failed or interrupted check cannot yield a successful `local/validation` status.

Main protection applies to administrators, requires current local validation, and disallows direct pushes, force pushes, and deletion. GitHub runs no hosted or self-hosted validation jobs: the commit status records checks performed on the maintainer's machine. Local status publication depends on the maintainer's authenticated GitHub access; it is not a remotely attested CI service.

## Focused diagnostics

Use focused commands while developing to shorten feedback. Run the full gate again for the final commit before requesting merge:

```sh
python tools/check_python.py
python tools/check_mql5_static.py
python tools/check_mql5_compile.py
python tools/run_mql5_tests.py
```

The compiler and runtime tools accept `--help` for source selection and timeouts. A focused run validates only the selected sources and cannot replace the complete gate.

Add deterministic detector tests for threshold boundaries, confirmation timing, unavailable history, repeated updates, lifecycle progression, calendar transitions, SMT timestamp gaps, and Power of Three transitions when those behaviors change. External readers should preserve the common fixture output and reject invalid/unsupported snapshots. Treat fixture timestamps as broker time.

During the staged introduction of this workflow, a bootstrap profile validates only its explicitly listed checks. Do not claim that an earlier bootstrap report ran later compiler, runtime, language, or documentation checks. The finished repository's merge profile is the complete profile.

Do not commit generated models, compiled binaries, terminal account data, credentials, or validation logs. Keep English documentation authoritative and preserve the translated README links when public behavior changes.
