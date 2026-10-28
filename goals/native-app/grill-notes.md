# Grill decisions

1. Main surface: a regular window app with a Dock icon, list or kanban like the n8n dashboard, and an optional menu bar count. (Not a popover-first app.)
   - A menu bar popover is a later addition, not v1.
2. Layout: a three-pane Mac layout (sidebar groups with counts → item list → detail). Kanban is not in v1.
3. Agents: a generic Harness protocol (list workspaces with agent states, find the workspace for a PR or ticket, start work, open a workspace). v1 ships only the Orca adapter (`orca worktree ps --json`, `orca worktree create`). A Claude Code hooks adapter comes later.
4. GitHub "needs me" (repos configurable, default n8n-io/*, through `gh api graphql`, every 2 min plus a manual refresh):
   - Review requested and not reviewed → Reviews.
   - Re-review (author pushed or replied after my review) → Reviews.
   - My PR with feedback: a human requested changes, a human commented after my last activity, or unresolved threads. Re-requested reviewers count as waiting. → My PRs.
     - Bots come in two configurable lists. **Review bots** (for example cubic-dev-ai and aikido-pr-checks) count for status: their findings put the PR in "needs me". **Noise bots** (for example cla-bot, codecov and github-actions) are ignored completely.
   - My PR with failing CI or a merge conflict → My PRs.
   - My PR approved and mergeable ("ready to merge") → My PRs.
   - My PR waiting for review → Waiting.
   - Not in v1: backports as their own concept, @mentions.
5. Linear (API key in the Keychain):
   - My assigned tickets in Todo, In Progress or In Review → Tickets. Todo ranks last. Backlog, Done and Canceled are hidden.
   - A ticket and its PRs form one item, linked through Linear's GitHub attachments. The item sits in the group of its most urgent part.
   - A ticket without a PR: "Continue X" when In Progress, "Start X" when Todo.
   - A ticket whose PR merged while it is still open: "Close X", with a "Move to Done" action that asks for confirmation.
6. Start work (↩ or a button):
   - Reuse the Orca worktree linked to the PR, ticket or branch. Otherwise create one: my PR on its branch, someone else's PR as a review worktree, a ticket on a new branch named after it.
   - Then start the agent with the prompt for this kind of work. **Every prompt is editable in Settings** (owner, 2026-10-09). Prompts are configurable per kind, and the agent defaults to claude:
     - Review → `/pr-review {url}`
     - Feedback, CI or conflict → `/pr-review-feedback {url}`
     - **Start ticket (Todo) → `/fix-ticket {ticket}`**
     - Continue ticket (In Progress): open the existing worktree. If none exists, start one with an editable default prompt: "Continue {ticket}: check the branch and the ticket, then propose the next step".
   - Automatic behaviour per kind: Manual (default) or Prepare (worktree only, no agent). No Auto-start in v1. Docket never posts to GitHub or Linear on its own.
   - Work hours (default Mon–Fri 9:00–18:00) gate notifications and Prepare.
7. Notifications (only in work hours, each a toggle):
   - Default on: an agent is blocked, waiting or awaiting a decision; an agent is done and its result is unread; a new review request; human feedback on my PR.
   - Default off: CI failed; ready to merge.
   - Activity from review bots changes status only and never notifies.
   - Clicking opens the item. Agent notifications have an "Open in Orca" action.
   - Each event notifies once. Snoozed items stay silent. Banners show even while Docket is frontmost.
8. Item actions:
   - Open in browser (⌘O).
   - Snooze (S): 1 h, tomorrow 9:00, next week, or a picked date. The item returns early on new activity.
   - Done (D): hidden until new activity.
   - Not mine (M): hidden for good.
   - Move ticket to Done: on "Close X" items only, with a confirmation, through Linear.
   - Copy link (⌘C).
   - All state and settings are local, in Application Support. No server.
   - Not in v1: TickTick and Telegram. n8n Docket can keep running for the phone.
9. Setup and tech:
   - First-run onboarding: GitHub (`gh auth status`, show the login command if needed; Docket never stores a GitHub token), Linear (paste the key, validate with "Connected as …", store in the Keychain), Orca (find the CLI automatically or set the path), notification permission. Every step can be skipped, and the app works with whatever is connected.
   - SwiftUI, macOS 15+, Swift 6. Swift Package Manager plus a script that bundles an ad-hoc signed Docket.app. Launch at login is a toggle.
   - Tests: the ranking and matching rules run under `swift test` with recorded JSON fixtures. The UI and integrations are checked by hand against real data.
