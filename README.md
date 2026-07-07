# fin-ui

A Spotlight-style macOS popup for the [`fin`](https://github.com/meain/fin) CLI agent:
open it, ask a question, watch a syntax-highlighted markdown answer stream in, approve
tool calls inline, and continue the conversation.

New here? See [GETTING_STARTED.md](GETTING_STARTED.md).

## How it works

`fin` exposes a machine-readable frontend via `fin -ui json` (added in the fin repo):
it emits newline-delimited JSON events on stdout and reads tool-approval decisions from
stdin. `fin-ui` spawns that process, decodes the event stream, and renders it.

```
fin-ui  ──spawn──▶  fin -ui json "<prompt>"
   ▲                        │ stdout (JSONL events)
   │  approvals (stdin)     ▼
   └────────────────  {"t":"text"|"tool_start"|"tool_done"|"approval"|...}
```

Event stream (one JSON object per line):

| type | meaning |
|------|---------|
| `text` | streamed assistant markdown delta |
| `end` | end of a text block |
| `tool_start` / `tool_output` / `tool_done` | tool lifecycle |
| `approval` | tool needs approval → reply `{"approve":true|false}` on stdin |
| `session` / `info` / `retry` / `error` | status |

`fin-ui` also synthesises a `stderr` event from the process's stderr so provider/retry
errors surface in the transcript. Previous chats are read straight from fin's session
JSONL files (`~/.local/share/fin/sessions`) — no extra fin process.

## Build & run

```bash
make run       # dev: build and open the popup
make app       # release: produces fin-ui.app
make install   # copy fin-ui.app into /Applications
make link      # symlink fin-ui.app into /Applications (tracks this build)
make fin       # install the patched fin CLI from ../fin
make help      # list all targets
```

Requires the patched `fin` on your `PATH` (`go install .` in the fin repo). fin-ui
resolves `fin` via a login shell, falling back to `~/.local/share/go/bin/fin` etc.

## Global hotkey (Spotlight feel)

The app is `LSUIElement` (no dock icon) and closes when it loses focus, so binding a
hotkey to launch it gives a true Spotlight experience. Bind `open -a fin-ui` (or the
`.app`) to a shortcut using **Raycast**, **Alfred**, **skhd**, or macOS **Shortcuts**.

## Behaviour

- **One-off by default**: each launch starts a fresh `fin` session.
- **Previous chat** (⌘P): opens a picker of your last 50 sessions (↑/↓ navigate, ⏎ open,
  Esc cancel) from any state, including mid-conversation. The chosen session loads into the
  transcript and follow-ups continue that specific session (`-s <id>`).
- **New chat** (⌘N) resets the window.
- **Approvals**: fin-ui honours your fin config's approval settings (`settings.approve`
  plus per-tool `approval`). Whenever fin asks for confirmation, an inline card appears —
  ⌘⏎ approves, Esc denies. (With `settings.approve = "all"`, everything auto-runs.)
- Code blocks are syntax-highlighted with a copy button.
- **Window position**: opens centered on first run; drag it and the position is
  remembered (persisted in `UserDefaults`) for next launch.

## Keyboard shortcuts

Fully keyboard driven — no mouse needed for the core flow.

| Key | Action |
|-----|--------|
| type + `⏎` | send |
| `esc` | close (deny a pending approval first) |
| `⌘⏎` | approve a tool call |
| `⌘N` | new chat |
| `⌘P` | open previous-chat picker (↑/↓ navigate, ⏎ open, esc cancel) |
| `⌘W` / `⌘Q` | close / quit |
| `⌘C` / `⌘V` / `⌘A` | standard editing in the prompt field |

## Layout

```
Sources/fin-ui/
  main.swift            NSApplication + borderless panel, menu, centering & position memory
  SpotlightView.swift   prompt bar, transcript, footer, auto-scroll, Esc handling
  ChatViewModel.swift   state, event handling, session chaining, load-previous
  FinRunner.swift       spawns fin, streams JSONL, writes approvals, exports last session
  Models.swift          wire events + view models + export structs
  MarkdownParser.swift  block-level markdown → elements
  MarkdownView.swift    renders blocks (+ CodeBlockView)
  SyntaxHighlighter.swift  light-theme tokeniser
  ToolCallView.swift    tool row
  ApprovalView.swift    approval card
```

The `fin -ui json` mode lives in the fin repo at `internal/jsonui/jsonui.go`, wired up in
`internal/cli/cli.go`.

## Contributing

See [AGENTS.md](AGENTS.md) for architecture, build/test workflow, and the non-obvious
gotchas (GUI environment, ScrollView sizing, auto-scroll, approvals).
