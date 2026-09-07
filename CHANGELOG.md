# Changelog

## [0.1.0-preview.1] - 2026-09-07

### Added

- Project scope, MIT license and versioned requirements proposal.
- Functional acceptance matrix covering monitor combinations, Stage Manager,
  learning protections, persistence, recovery, identity matching and privacy.
- P0 performance budgets for idle CPU, memory, wakeups, event storms and soak tests.
- Explicit Stage Manager OFF / ON / runtime-switching requirements; 42 acceptance scenarios.
- Approved native event-driven technical design and interaction specification.
- Native menu-bar preview, AX event adapter, per-topology profiles, candidate capture, restore verification, history and backup.
- 71 passing core cases / 1,634 assertions; measured LayoutCore line coverage 98.41% (not whole-app coverage).
- Build, install, package, coverage and resource measurement scripts; macOS CI.

### Status

- Requirements and design approved; runnable development preview implemented.
- Full functional, Stage Manager, monitor-switching, login and performance acceptance incomplete.
- Candidate observations require explicit save; not fully automatic persistent learning.
