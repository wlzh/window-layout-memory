# Contributing

This project is in technical design review. Requirements are confirmed; discuss scope changes before implementation.

## Quality bar

- Add deterministic tests for behavior changes and regression cases.
- Separate automated results from macOS permission and physical-display tests.
- Do not claim compatibility without naming the tested OS, architecture and app.
- Keep version metadata, changelog, user instructions and release notes consistent.
- Use synthetic fixtures; never publish a real user's layout or diagnostic dump.
- Do not add private macOS APIs or security-setting workarounds without explicit design review.
- Submit focused pull requests with verification results and remaining limitations.

Build and test commands will be documented after implementation. None exist yet.
