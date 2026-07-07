# Getting Started

A quick guide to running fin-ui and driving it from the keyboard.

## Prerequisites

- macOS 14+ and the Swift toolchain (`swift --version`).
- The patched `fin` CLI on your `PATH` with the `-ui json` mode. Install it:

  ```bash
  make fin          # runs `go install .` in ../fin
  fin -doctor       # confirm providers show [key set]
  ```

- Provider API keys exported in your shell profile (`~/.zshrc` / `~/.zshenv`).
  fin-ui sources your login-shell environment, so keys set there work even when
  launched as an app.

## Run it

```bash
make run       # dev build, opens the popup immediately
```

Or build and install the app so you can launch it like Spotlight:

```bash
make app       # builds fin-ui.app
make link      # symlink it into /Applications (tracks your latest build)
# or: make install  to copy instead of symlink
```

## Bind a global hotkey

fin-ui has no dock icon and closes when it loses focus, so a launch hotkey gives
a true Spotlight feel. Point any launcher at the app:

- **Raycast / Alfred**: add a "Launch app" or script action for `fin-ui.app`, assign a hotkey.
- **macOS Shortcuts**: new shortcut → "Open App" → fin-ui → assign a keyboard shortcut.
- **skhd**: `cmd - space : open -a fin-ui`

## Keyboard shortcuts

fin-ui is fully keyboard driven — no mouse needed for the core flow.

| Key | Action |
|-----|--------|
| type + `⏎` | send your question |
| `esc` | close the popup (deny a pending approval first) |
| `⌘N` | new chat (clears the window) |
| `⌘P` | open the previous-chat picker (↑/↓ navigate, ⏎ open, esc cancel) |
| `⌘,` | open settings (fonts, text size, accent color) |
| `⌘⏎` | approve a tool call |
| `esc` | deny a tool call (when an approval card is showing) |
| `⌘W` / `⌘Q` | close / quit |
| `⌘C` / `⌘V` / `⌘A` | standard editing in the prompt field |

## Typical flow

1. Hit your hotkey → the popup appears, prompt field focused.
2. Type a question, press `⏎`. The answer streams in as highlighted markdown.
3. Ask a follow-up — it continues the same conversation automatically.
4. If fin wants to run a tool that your config marks for confirmation, an approval
   card appears. `⌘⏎` to approve, `esc` to deny.
5. `⌘N` to start fresh, or `esc` to dismiss.

## Approvals

fin-ui honours your fin config's approval policy (`settings.approve` plus per-tool
`approval` in `~/.config/fin/config.toml`). To be asked before tools run, make sure
`settings.approve` is **not** `"all"` — e.g. remove it so the per-tool settings
(`confirm` for `write`/`edit`/`shell`) take effect. With `"all"`, everything runs
without prompting.

## Continuing a previous chat

- New launches start a fresh session (one-off).
- Press *Previous chat* (`⌘P`) to open a picker of your last 50 sessions; navigate with
  ↑/↓ and press ⏎ to load one. Your next message continues that session.
- Follow-ups within an open window always continue the current conversation.
- The window opens centered the first time; move it and it remembers where you left it.

## Troubleshooting

- **No output / errors about API keys** — confirm `fin -doctor` shows `[key set]` and
  that the keys are exported in your login shell (`zsh -lc 'env | grep API_KEY'`).
- **"failed to launch fin"** — ensure `fin` is on your `PATH` (`command -v fin`) or at
  `~/.local/share/go/bin/fin`.
- **Nothing happens on a tool** — check your approval policy above.
