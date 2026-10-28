<p align="center">
  <img src="docs/icon.png" width="128" alt="Docket logo">
</p>

<h1 align="center">Docket</h1>

<p align="center">
  <b>One ranked "what needs me next" list across GitHub, Linear, TickTick and your coding agents.</b><br>
  A native macOS app, built with SwiftUI.
</p>

<p align="center">
  <a href="https://github.com/BerniWittmann/docket/actions/workflows/build.yml"><img src="https://github.com/BerniWittmann/docket/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-000?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0A84FF" alt="SwiftUI">
</p>

<p align="center">
  <img src="docs/screenshots/nord-agents-need-me.png" width="860" alt="Docket showing agents that need attention">
</p>

---

Docket gathers everything that is waiting on you and puts it in one place, ranked:

- **🤖 Agents:** Orca workspaces whose agent is blocked, waiting for you, or done with an unread result.
- **👀 Reviews:** review requests and re-requests, read through your local `gh` login.
- **🔀 My PRs:** new feedback, failing CI, merge conflicts and PRs that are ready to merge.
- **🎫 Tickets:** your Linear tickets in Todo, In Progress and In Review.
- **✅ To-dos:** your TickTick tasks, synced both ways.

Press <kbd>↩</kbd> and Docket starts the work in [Orca](https://github.com/stablyai/orca). It checks out the branch, or a `review-<n>-<slug>` worktree for someone else's PR, and hands your agent a prompt. **Docket never writes to GitHub or Linear.** It only acts locally, in Orca or in TickTick.

## Screenshots

| My PRs | Reviews |
|---|---|
| ![My PRs](docs/screenshots/nord-my-prs.png) | ![Reviews](docs/screenshots/nord-reviews.png) |
| **Tickets** | **To-dos from TickTick** |
| ![Tickets](docs/screenshots/nord-tickets.png) | ![To-dos](docs/screenshots/nord-to-dos.png) |

Two themes, **Nord** and **n8n**, switchable from View → Theme:

| Nord | n8n |
|---|---|
| ![Nord theme](docs/screenshots/nord-my-prs.png) | ![n8n theme](docs/screenshots/n8n-my-prs.png) |

<sub>The screenshots show made-up data from `Docket --demo`.</sub>

## Install

<p align="center">
  <a href="https://github.com/BerniWittmann/docket/releases/latest/download/Docket.zip"><img src="https://img.shields.io/github/v/release/BerniWittmann/docket?label=Download%20Docket&style=for-the-badge&logo=apple&color=88C0D0" alt="Download the latest Docket"></a>
</p>

### 1. Prerequisites

| What | Why | How |
|---|---|---|
| **macOS 15** or later | | |
| **GitHub CLI** | Reviews and PRs | `brew install gh`, then `gh auth login` |
| **Orca** *(recommended)* | Agent workspaces, Start work | Install [Orca](https://github.com/stablyai/orca) and add the repos you work in |
| Linear API key *(optional)* | Tickets | Linear → Settings → Security & access → Personal API keys |
| TickTick API token *(optional)* | To-dos and task sync | TickTick web → Settings → Account → API Token |

### 2. Download

```sh
curl -fsSL -o /tmp/Docket.zip https://github.com/BerniWittmann/docket/releases/latest/download/Docket.zip
ditto -x -k /tmp/Docket.zip /Applications/
xattr -dr com.apple.quarantine /Applications/Docket.app
open /Applications/Docket.app
```

Or [download Docket.zip](https://github.com/BerniWittmann/docket/releases/latest/download/Docket.zip) in the browser, unzip it and move **Docket.app** to `/Applications`. Every new feature or fix on `main` that passes the tests is published as a [release](https://github.com/BerniWittmann/docket/releases). To update, run the same commands again.

> [!IMPORTANT]
> Docket is ad-hoc signed, not notarized by Apple, so macOS blocks the first launch of a downloaded copy. The `xattr` line above clears that flag. Without it, you can open the app anyway from System Settings → Privacy & Security → **Open Anyway**.

<details>
<summary><b>Or build it from source</b></summary>

You need **Xcode** too: install it from the App Store, then run `sudo xcodebuild -license accept` and `xcodebuild -runFirstLaunch`.

```sh
git clone https://github.com/BerniWittmann/docket.git
cd docket
scripts/bundle.sh                  # release build, app icon, ad-hoc signature → Docket.app
mv Docket.app /Applications/
open /Applications/Docket.app
```

To update: `git pull && scripts/bundle.sh && rm -rf /Applications/Docket.app && mv Docket.app /Applications/`

</details>

### 3. First launch

The first launch walks you through **GitHub → Linear → TickTick → Orca → notifications**. You can skip any step and connect it later in Settings (<kbd>⌘</kbd><kbd>,</kbd>).

Then open **Settings → Sources** and set the repos and orgs to watch, such as `my-org/*` or `owner/repo`.

> [!NOTE]
> **Keychain prompts after updating.** Each new build has a new ad-hoc signature, so after an update macOS asks again for access to the Linear key and the TickTick token. Choose **Always Allow**. When you build from source, you can avoid this: create a code-signing certificate in Keychain Access (Certificate Assistant → Create a Certificate, type *Code Signing*) and build with `DOCKET_SIGN_IDENTITY="<certificate name>" scripts/bundle.sh`.

### Try it without accounts

```sh
open /Applications/Docket.app --args --demo
```

Demo mode fills Docket with made-up items and doesn't touch GitHub, Linear, TickTick or Orca.

## Using it

| Key | Action |
|---|---|
| <kbd>↑</kbd> <kbd>↓</kbd> | Move through items |
| <kbd>⌘1</kbd> – <kbd>⌘8</kbd> | Agents need me, Reviews, My PRs, Tickets, To-dos, Waiting, Snoozed, Waiting for input |
| <kbd>↩</kbd> | Do the item's work: Review, Re-review, Address feedback, Fix CI, Resolve conflict, Start ticket, Continue ticket |
| <kbd>⌘O</kbd> | Open in the browser |
| <kbd>⌘C</kbd> | Copy the link |
| <kbd>S</kbd> / <kbd>D</kbd> / <kbd>M</kbd> | Snooze, Done (until new activity), Not mine (for good) |
| <kbd>⌘R</kbd> | Refresh now |

**Start work** reuses an existing worktree when there is one: the prompt goes to its idle agent session, a busy agent is only opened, and otherwise a new session starts. The button's tooltip says which. Items without work to start open in Orca, Linear or the browser.

**Worktrees.** Someone else's PR gets a review worktree named `review-<number>-<slug>`, such as `review-39409-handle-inbound-media`. Your own PRs are checked out on their head branch, and tickets on their Linear branch name.

**Re-reviews.** A PR you already reviewed returns to Reviews only when its author re-requests your review. Pushes and replies alone don't bring it back.

**Feedback.** An unresolved thread counts as feedback only when its last comment is newer than your last push or reply.

**Linking PRs to tickets.** Docket follows the branch convention: a branch named `abc-1234-some-slug`, or a title containing `ABC-1234`, belongs to ABC-1234. Your tickets claim those PRs even without a Linear attachment. Other people's PRs show their ticket (title, state, assignee) for context.

**Waiting for input.** Tickets in a waiting-for-input state go to their own group, unless their PR or agent needs you. You set the state's name in Settings → Sources; the default is "Waiting for input".

## TickTick sync

Connect a token and pick a list in Settings → Sources. Docket then keeps one TickTick task, tagged `#docket`, for each item that needs you:

| Item | Task |
|---|---|
| Needs you | Open, due today (all-day) |
| Snoozed | Open, due on the snooze day |
| Waiting, done (<kbd>D</kbd>), merged or closed | Completed |

- **Titles** start with the action, such as *"Address feedback: Set up Microsoft Teams again"*. The `feat(editor):` prefix and `(no-changelog)` are left out. Docket renames its own tasks when the action changes. Tasks you made keep your title.
- **Reopening.** When an item needs you again, its task is reopened.
- **Transitions only.** Docket writes only when an item changes state, so a task you complete or re-date in TickTick stays that way until then.
- **Outages.** Docket writes nothing while GitHub, Linear or TickTick reports an error, so an outage never completes your tasks.
- **Linking your own tasks.** Any open task that names a PR joins that item, and Docket adopts it instead of creating another. A PR can be named as `https://github.com/…/pull/123`, `repo#123` or `owner/repo#123`. A ticket can be named as `ABC-1234` or by its Linear URL.
- **To-dos.** `#docket` tasks that name nothing show up under To-dos. <kbd>D</kbd> completes them and <kbd>S</kbd> moves their due date.

GitHub, Linear and TickTick are polled every 2 minutes, and Orca every 10 seconds. Notifications fire only inside your work hours, once per event.

## Settings

| Tab | What's in it |
|---|---|
| **Sources** | Repos and orgs to watch, the repo for new ticket worktrees, the Linear key, the TickTick token and list, the Orca CLI path |
| **Work** | For each kind of work: the agent (default `claude`), the prompt (`{url}`, `{ticket}`, `{number}` and `{repo}` are filled in), and the automation. *Manual* waits for you; *Prepare* creates the worktree for new items inside work hours, without starting an agent |
| **Notifications** | One toggle per event |
| **Bots** | Review bots count as feedback. Noise bots and unknown bots are ignored |
| **Appearance** | Nord or n8n |
| **General** | Work hours (default Mon–Fri 8:00–18:00), launch at login |

State and settings live in `~/Library/Application Support/Docket/`.

## Where this is going

Docket started as my own daily driver, so today it is tied to my setup: [Orca](https://github.com/stablyai/orca) runs the agents and TickTick holds the to-dos. I'd like to make it more flexible, so it fits your setup too:

- **Other agent harnesses.** Orca sits behind a small `Harness` protocol, so other tools could plug in: plain git worktrees with Claude Code or Codex in a terminal, Conductor, Cursor, or anything else with a CLI.
- **Other to-do apps.** Things, Todoist, Apple Reminders or Linear itself instead of TickTick.
- **Other sources.** GitHub Enterprise, GitLab, Jira, Slack mentions.
- **Your own rules.** Choose what counts as "needs me", and how items are ranked and grouped.

**Got an idea, or a setup you'd like Docket to support?** Please reach out, I'd love to hear it. [Open an issue](https://github.com/BerniWittmann/docket/issues/new) or message me on [GitHub](https://github.com/BerniWittmann). Pull requests are welcome too.

## Development

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test          # rules, ranking, matching and sync, driven by recorded fixtures
scripts/bundle.sh   # builds Docket.app
```

The Command Line Tools alone build the app, but they ship no test framework, so the tests need Xcode.

The project has two parts:

- **`DocketCore`** holds the sources (GitHub, Linear, TickTick, Orca), the rules that turn them into ranked work items, and the sync.
- **`Docket`** is the SwiftUI app.

### Fixtures

`Tests/DocketCoreTests/Fixtures` holds real responses, scrubbed by `scripts/scrub-fixture.py`. Other people's logins become `user-N`, and titles and free text are replaced. To record new ones:

- `github-inbox*.json`: `DOCKET_LIVE=1 DOCKET_RECORD=<file> swift test --filter GitHubSourceTests/live`
- `linear-issues.json`: `Docket.app/Contents/MacOS/Docket --record-linear <file>`, which uses the key the app already has
- `orca-ps*.json`, `orca-repos.json`: `orca worktree ps --json`, `orca repo list --json`

Scenarios the recordings lack, such as a PR that is ready to merge or a merged PR on an open ticket, are derived in the tests from a recorded PR or ticket.

Every push to `main` and every pull request is built and tested on macOS by [GitHub Actions](.github/workflows/build.yml). Each run has the built `Docket.app` attached. Pushes to `main` publish a release with a [semantic version](https://semver.org) worked out from the [Conventional Commits](https://www.conventionalcommits.org) since the last release (`scripts/next-version.sh`): `feat` bumps the minor version, `fix` and `perf` bump the patch version, and `!` or `BREAKING CHANGE` bumps the major version. Other commit types don't create a release.
