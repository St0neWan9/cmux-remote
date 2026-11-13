# cmux-agent-recovery

Snapshot the coding agents that are open in cmux-tui and relaunch them after a
reboot.

This directory is developer tooling for the machine that runs cmux-tui. It is
not part of the cmux-remote app, Bridge or protocol, and nothing in the build,
CI or `scripts/verify.sh` calls it.

## Why this exists

cmux-tui keeps a durable detached owner, so quitting the TUI or killing the
owner does not stop agents. A reboot does. The owner, the per-terminal host
processes and every agent process end together. cmux restores the workspace
records, but it does not restart terminal processes, and an agent conversation
does not resume by itself.

`cmux-agent-recovery` fills that gap:

- `save` records the currently open agents.
- `restore` starts each local session owner and relaunches the recorded agents
  with their resume flags in the same workspace.

## Requirements

- macOS for the LaunchAgent commands (`launchctl`, `ps`, `getconf`). `save` and
  `restore` themselves only need a Unix shell.
- Python 3.9 or newer. The script has no third-party dependencies.
- `cmux-tui` on `PATH`, or `CMUX_TUI_BIN` pointing at it.
- cmux agent hooks for the providers you care about, so the live agent session
  id is reported. `cmux agent hook install claude codex` installs them. When a
  terminal has no hook record, the tool falls back to a `--resume` value in the
  agent command line.

## Install on a new machine

The repository does not contain LaunchAgent plists. `install` generates them
for the current user, with absolute paths to the installed script, the state
directory and the log file. Do not copy plists from another machine: they point
at the other user's home directory and script path, even when the user name is
the same. Generate them here instead.

1. Install the prerequisites: macOS, Python 3.9 or newer, `cmux-tui` on `PATH`
   (or `CMUX_TUI_BIN`), and the agent hooks for the providers you use:

   ```sh
   cmux agent hook install claude codex
   ```

2. Get this directory onto the machine (clone the repository, or copy
   `tools/cmux-agent-recovery/`).

3. Put the script where launchd can keep calling it:

   ```sh
   install -m 755 tools/cmux-agent-recovery/cmux-agent-recovery ~/.local/bin/
   ```

   `install` records this absolute path in the plists, so run the remaining
   commands through `~/.local/bin/cmux-agent-recovery`, or make sure
   `~/.local/bin` is on `PATH`.

4. Record the current state and check detection. On a machine with no agents
   open this writes an empty snapshot, which is expected:

   ```sh
   cmux-agent-recovery save
   cmux-agent-recovery list
   ```

5. Generate and load both LaunchAgents:

   ```sh
   cmux-agent-recovery install --auto-restore
   ```

6. Verify that launchd loaded them:

   ```sh
   launchctl print gui/$(id -u)/dev.valuz.cmux-agent-recovery.save
   launchctl print gui/$(id -u)/dev.valuz.cmux-agent-recovery.restore
   ```

`install` writes LaunchAgents to `~/Library/LaunchAgents`:

| Agent | Behavior |
| --- | --- |
| `dev.valuz.cmux-agent-recovery.save` | Runs `save --quiet` every 300 seconds. It deliberately does not run at load, so the login restore can read the snapshot from before the reboot. |
| `dev.valuz.cmux-agent-recovery.restore` | Runs `restore --quiet` at login. |

The plist stores the absolute path of the script that ran `install`. Install
from the copy you want launchd to call, normally `~/.local/bin/cmux-agent-recovery`.
Running `install` without `--auto-restore` removes the login job and keeps only
the periodic snapshot. `uninstall` removes both.

### Moving from another machine

The snapshot is only useful together with the agent session data it names.
`claude --resume <id>` and `codex resume <id>` read `~/.claude/projects/` and
`~/.codex/`; if that data did not come across, copy the script and this README,
but skip `~/.local/state/cmux-agent-recovery/snapshot.json` and let the periodic
save build a fresh one. The LaunchAgents themselves are always regenerated,
never copied.

## Commands

```sh
cmux-agent-recovery save                    # record open agents
cmux-agent-recovery save --session cmux     # one session only, repeatable
cmux-agent-recovery save --force            # overwrite even if no session answers

cmux-agent-recovery list                    # show the latest snapshot
cmux-agent-recovery history                 # latest plus archived snapshots
cmux-agent-recovery restore --dry-run       # print commands without running them
cmux-agent-recovery restore                 # relaunch recorded agents
cmux-agent-recovery restore --snapshot previous-boot
cmux-agent-recovery restore --snapshot history/snapshot-20261113T231100Z.json
cmux-agent-recovery restore --session cmux  # one session only

cmux-agent-recovery install --auto-restore  # periodic save + restore at login
cmux-agent-recovery install                 # periodic save only
cmux-agent-recovery uninstall               # remove the LaunchAgents
```

All commands accept `--state-dir` before the subcommand; the default is
`~/.local/state/cmux-agent-recovery`.

## How `save` decides what to record

It looks for local session sockets under the per-user temp directory
(`cmux-tui-<uid>/*.sock`), then for each session:

1. Skips sessions that are not running and sessions whose machine is not the
   local machine, so `cmux ssh` sessions are never restored onto this Mac.
2. Takes every terminal that is running and whose foreground executable is
   `claude` or `codex`.
3. Reads the terminal process (`terminal <id> process show`) for its working
   directory and command line, and walks the screen layout to find the
   terminal's workspace.
4. Uses the newest agent hook record for that terminal as the live session id.
   A bare `--resume` value in the process command line is only a fallback: a
   resumed Claude session can be a copy with a new id, while the hook reports
   the session that is actually being written.
5. Skips terminals with no placement in any workspace, and deduplicates two
   terminals that display the same agent session.

The snapshot contains only metadata: terminal and workspace ids, titles,
working directories, provider names, agent session ids and command lines. It
never contains transcripts, prompts, credentials or terminal output.

If no session answers at all, `save` keeps the previous snapshot instead of
overwriting it with an empty one. A file lock serializes `save` and `restore`,
so a periodic save cannot replace a snapshot in the middle of a restore.

## How `restore` works

`restore` first picks a snapshot: `latest` by default, or
`--snapshot previous-boot|<path>`. It prints the file, capture time and agent
count before doing anything.

For each session in the snapshot:

1. `server status`; on failure `server ensure --session <name> --socket <path>`.
   Both flags are required: the socket selects the endpoint and the name selects
   the durable state subtree. Falling back to `--session` alone handles a temp
   directory that moved. `ensure` is retried with backoff, and if it still does
   not produce a ready owner, `restore` starts the detached `--headless` owner
   itself and waits longer than the CLI's own 10 second deadline: recovery owns
   the start, so it does not depend on the login session already being ready.
   Every failed attempt keeps the CLI's exit code and stderr, and the detached
   owner's pid and exit state, in the restore report; a bare `None` no longer
   hides the cause.
2. Skip entries that are already running. The check uses the live agent roster
   for the session, the resume id in every running terminal's recorded command
   line, and the process table.
3. Resolve the workspace by id, then by name, and create `restored` if neither
   exists.
4. Relaunch with:

   ```sh
   workspace <id> run --on-exit keep -- /bin/sh -lc \
     'cd <cwd> && exec <agent argv with --resume <id>>'
   ```

For Claude, positional arguments (the original prompt) are removed before the
resume flag is normalized, so an old request is not sent again. For Codex, an
existing `codex resume` command is kept (a trailing prompt is dropped), and a
missing session id is added.

## Snapshot history and recovery

Each `save` archives the previous snapshot under `history/` before replacing
`snapshot.json` whenever the agent set or the boot changed. Every snapshot
records `boot_id`, a boot-time identifier, so history can be grouped by reboot.
This is what makes a failed login restore recoverable: the snapshot from before
the reboot survives even if an early save at login records only the first agent
that was opened afterwards.

- `history` lists the current snapshot and every archived one with capture time,
  boot id and agent count.
- `restore --snapshot previous-boot` selects the newest snapshot whose boot id
  differs from the current boot. Before the first save of a boot that is
  `snapshot.json` itself, which is exactly the pre-reboot state the login restore
  should use.
- `restore --snapshot <path>` selects an exact archived file; a relative path is
  also resolved against the state directory.
- When a save's agent count is less than half of the previous snapshot, it warns
  in the LaunchAgent log and still keeps the previous state in history. It does
  not block the save: closing agents before a reboot is legitimate.

History keeps the newest 200 distinct states, pruned oldest first. The save
LaunchAgent no longer runs at load, so it cannot overwrite the pre-reboot
snapshot before the login restore reads it; the first periodic save happens one
interval after login.

## State and permissions

```text
~/.local/state/cmux-agent-recovery/
  snapshot.json      0600   latest save
  history/                  archived distinct snapshots, newest 200
  last-restore.json  0600   what the last restore launched, skipped and failed
  state.lock         0600   serializes save and restore
  launchd.log               LaunchAgent stdout and stderr
```

The directory is mode `0700`. The snapshot holds working directories and agent
session ids; treat it as private to the account.

## Limitations

- A real reboot has not been observed with the current version. An earlier
  version failed to start the owner at login and the next save replaced the only
  snapshot. The current version retries `server ensure`, starts the detached
  owner itself, keeps the previous state in history, and no longer saves at
  load. The cold path has been tested in an isolated session by killing the
  owner and every terminal host, then starting a fresh owner.
- History keeps the newest 200 distinct states. An older state that matters
  should be copied out of `history/` before it is pruned.
- cmux does not restore the screen/pane layout after a reboot. Agents return to
  the same workspace as new terminals; workspaces persist, screens do not.
- Terminals with no placement in a workspace are skipped. They are not visible
  in the TUI, so there is nowhere to put them back.
- Only Claude and Codex are supported. Other providers are skipped.
- The snapshot is at most one interval old. Run `save` immediately before a
  shutdown if an agent was started in the last few minutes.
- `--continue` entries cannot be identified by a session id. They are restored
  once, and two of them in the same working directory may collide.
- Remote sessions (`cmux remote ssh`) are skipped: their work belongs on the
  remote host, not in a local workspace.

## Manual verification performed

- `save` against a live session found every visible Claude agent and skipped
  detached terminals.
- `restore --dry-run` printed one command per agent, with the correct workspace,
  working directory and hook-reported session id.
- `restore` with all agents already running launched nothing and skipped all of
  them.
- In an isolated session, killing the owner and terminal hosts and then running
  `restore` launched the recorded command; a second run skipped it.
- Saving over a fixture snapshot archived the previous state under `history/`,
  `history` listed both with their boot ids, and the previous-boot selector
  resolved the archived copy. Pruning kept the requested number of entries.
