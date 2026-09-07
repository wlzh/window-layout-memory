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

Run `zsh scripts/test-all.sh` and `zsh scripts/coverage.sh`. See docs/TESTING.md for the actual denominator and unexecuted hardware gates.
