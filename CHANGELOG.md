# Changelog

## [0.2.0-preview.1] - 2026-09-08

- Add native read-only current/saved/comparison layout preview with proportional monitor geometry and coordinate details.
- Keep other monitor combinations isolated, including their built-in display windows.
- Show last-read timestamps and ambiguity without claiming background visibility or stacking order.
- Coalesce event-driven preview updates; cancel pending work and release window/controller/canvas on close.
- Add projection, matching, cached-preview, AppKit refresh/lifecycle and synthetic rendering checks.
- Centralize bundle version/channel/build display. Build 3; schema 1 retained; no screen recording required.
- Full physical monitor, real AX and long-run performance acceptance remains separate.

## [0.1.0-preview.2] - 2026-09-07

### Added

- Persist deliberate foreground mouse drag/resize adjustments after settling; retain candidates when intent is uncertain.
- Conservative legacy preference migration, locked baseline protection and no-op capture deduplication.
- Manual display mapping/copy UI, layout renaming and cancellation of pending restores.
- 103 core cases / 2,814 assertions and 28 injected Engine integration checks, including a 1,000-event burst.
- Explicit regressions for distinct same-count monitor sets: even the shared built-in screen has separate window layouts in each combination.
- Dedicated Engine coverage script; hardware and real AX coverage remain separate.

### Fixed

- Baseline revisions no longer rearm automatic restoration and fight later user adjustments.
- Reuse window notification registrations and preserve runtime identities across partial scans.
- Cancel queued scans between windows after pause or topology changes; prioritize foreground scans.
- Retry a transient AX write at most once, only when no geometry changed and the pointer is released.
- Check permission and pointer state between writes; remove Engine observers on teardown.

### Status

- Build 2, ad-hoc signed, not notarized. Updating a locally signed binary can require renewed Accessibility permission.
- Stage Manager ON/OFF, physical display cycles, login/wake, real AX writes and long-run performance still require acceptance.

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
