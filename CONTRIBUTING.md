# Contributing

This project is a development preview. Requirements and technical design are confirmed; discuss scope changes before implementation.

## Quality bar

- Add deterministic tests for behavior changes and regression cases.
- Separate automated results from macOS permission and physical-display tests.
- Do not claim compatibility without naming the tested OS, architecture and app.
- Keep version metadata, changelog, user instructions and release notes consistent.
- Use synthetic fixtures; never publish a real user's layout or diagnostic dump.
- Do not add private macOS APIs or security-setting workarounds without explicit design review.
- Submit focused pull requests with verification results and remaining limitations.

Run `ruby scripts/check-docs.rb`, `zsh scripts/test-all.sh`, `zsh scripts/coverage.sh` and `zsh scripts/coverage-engine.sh`. See [testing](docs/TESTING.md) for the actual denominator and unexecuted hardware gates.

## Documentation and releases

Use [current status](docs/STATUS.md) to distinguish a published tag, the installed app and unreleased main changes. Keep historical evidence version-scoped; do not rewrite an old test count as the current count or mark a past permission failure as current. Add behavior changes to Unreleased until a new release is built. Documentation-only changes do not require a new app version or installation.

Before distributing new code, advance the build and release channel together in the version files, plist and AppVersion fallback; update README, current status, CHANGELOG and release notes. Never replace an existing release archive with different bytes under the same version. Test and collect changes before installing to reduce ad-hoc permission churn.

`scripts/package-release.sh` currently writes `dist/release/SHA256.txt`; published releases may use a version-qualified checksum filename documented in their release notes. Rename/copy that checksum for release upload as needed, verify its archive entry and download the published asset for verification. This script rebuilds and signs the dist bundle; it does not install or publish it. Do not rerun it merely to edit release notes.
