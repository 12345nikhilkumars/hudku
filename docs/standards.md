# Standards

House rules for this codebase, learned the hard way.

## Text

- Never write em-dashes (U+2014) anywhere: code, comments, docs, commit messages. Use hyphens
  or restructure the sentence.

## Comments

- Comments state why, not what. A comment carries a constraint, a surprise, or a workaround;
  if it only narrates the line, delete it.
- Keep doc comments short. They are labels, not essays.

## Code

- Zero third-party dependencies. If the platform can do it, use the platform.
- Pure logic lives in Model/Service layers with no UI imports, so the harnesses can compile it
  standalone.
- Formatting: `./Scripts/format.sh`. Linting: `./Scripts/lint.sh`.

## Tests

- Every harness lives in `Tests/`, is registered in `Scripts/run-tests.sh` with the exact
  sources it needs, and must stay green before any release.
- Performance work is measured, not felt: the in-app `HUDKU_PERF` battery plus external
  probes; record before and after numbers in [PERFORMANCE.md](../PERFORMANCE.md).

## Releases and history

- The version lives in `project.yml` (`MARKETING_VERSION`). Releases are cut by tag; the
  pipeline is in [building.md](building.md).
- Nothing is committed or pushed until the owner says so, and each go-ahead covers one batch
  only.
