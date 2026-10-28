# Goal: Docket, a native macOS app

Build Docket in `~/DEV/Docket` as a native SwiftUI macOS app. It shows one ranked "what needs me next" list across people (GitHub reviews and PR feedback through `gh`, Linear tickets through an API key) and agents (Orca workspaces behind a Harness protocol). It starts work in the chosen harness with a configurable prompt for each kind of work, sends native notifications within work hours, and switches between a Nord theme and an n8n theme with a matching logo. It never writes to GitHub or Linear.

- **Shared understanding:** [`facts.md`](facts.md), 49 facts. Verification choices are in `facts.meta.json`.
- **Execution plan:** [`plan.md`](plan.md), 11 ordered steps with checks (approved 2026-10-09).
- **Decision log:** [`grill-notes.md`](grill-notes.md).

## Prerequisites
- Xcode license accepted on 2026-10-09. Tests run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (Swift Testing verified).
- Fonts (owner decision, 2026-10-09): the n8n theme uses n8n Baumer only when it is installed, and falls back to the system font otherwise. Mono capsule labels fall back to the system monospaced font, still in ALL CAPS.

## Done when
- Every fact in `facts.md` holds:
  - facts with `automatedVerification: true` are covered by passing `swift test` cases, or by the `DocketChecks` fallback;
  - the others were checked by hand against real data.
- `scripts/bundle.sh` produces a `Docket.app`. Launched, it shows a populated three-pane inbox from the owner's real GitHub, Linear and Orca data.
- Each plan step was committed in `~/DEV/Docket` as its own conventional commit.
