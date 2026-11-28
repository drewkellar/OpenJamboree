# OpenJamboree: project rules

Static recompilation of Super Mario Party Jamboree for Windows, built on SwitchRecomp by MZ Labs.
Public repo: https://github.com/drewkellar/OpenJamboree (remote name `github`). Port notes: `docs/JAMBOREE_PORT.md`.

These rules apply to every AI coding agent and person working in this repo (Claude Code, Codex/GPT, others).
`CLAUDE.md` only points here, so keep the rules in this one file.

## Git workflow (required)

- **Never push to `main`.** Not directly, not by force, not by merging a PR. The only exception is when the owner
  explicitly says to push or merge to main for that specific change. Approval for one change doesn't carry over.
- Every change goes on a **feature branch**, never on `main`. Reuse the branch that fits: while a development branch
  is active (its PR open or not yet opened), follow-on work for it goes on that same branch, across as many sessions
  and requests as it takes. Don't start a new branch per request.
- Start a new branch only when no open branch fits the work (all merged, or the work is a separate topic). Base it
  on the latest `main`: `git fetch github && git switch -c <type>/<short-name> github/main`
  (types: `fix/`, `feat/`, `docs/`, `chore/`, `perf/`). Before starting, check `git branch` and `gh pr list` for
  one to reuse.
- **Always push finished work.** When a change is done and verified, commit it, push the feature branch to `github`
  and open a pull request against `main` (`gh pr create --base main`) for the owner's manual review. Report the PR link.
  Don't leave finished work only on the local machine.
- GitHub branch protection on `main`: changes only through a pull request, applies to admins too, no force pushes,
  no deletion, review conversations must be resolved. Don't change these settings unless the owner asks. Even an
  owner-approved change to main goes in through its PR (`gh pr merge` only after the owner says to merge).
- A local `pre-push` hook (`.git/hooks/pre-push`) also rejects pushes to `main`. Don't bypass it, and never set
  `ALLOW_MAIN_PUSH=1` unless the owner explicitly approved that push.
- A branch can carry a broad topic (e.g. a round of playtest fixes). New commits on a branch with an open PR update
  that PR; push them and say so. Once a branch's PR is merged, don't reuse it: start a fresh one off `main`.
- Branches stacked on an unmerged branch are allowed when the work depends on it; say so in the PR, and merge in order.
- Commit messages: what changed and why. If your tool or session specifies attribution lines (a co-author trailer
  for commits, a footer for PR descriptions), add them.
- Never push the local branch `old-local-history`: it holds pre-publication history, including game logs.

## Documentation (required, every change)

Docs are updated in the same commit (or at least the same PR) as the change they describe, never "later". Before
every commit, check each of these and update what the change affects:
- `docs/JAMBOREE_PORT.md`:
  - section 1 **Status** table and its "Last updated" date: any area whose state changed;
  - section 2 **Bugs**: each bug fixed or investigated, with its evidence, cause and fix (new number for a new bug);
  - sections 3/4 **Features** and **Diagnostic switches**: every new key, `.ini` option or `SWR_*` variable;
  - section 7 **Playtest log** and **Owner manual checks**: everything seen in play, fixed or not, and the owner's
    verdicts when they come back;
  - section 8 **Next steps**: remove what is done, add what was found; sections 9/10 when coverage changes.
- `CHANGELOG.txt`, OpenJamboree section at the top: one user-facing line per change.
- `README.md` status table and controls, and `README.txt` controls/options, when what a player sees or presses changes.
- `DEVELOPER_GUIDE.md` / `REGRESSION.md` when a workflow, tool or regression check changes.
- This file when a rule changes.

A PR description lists which docs it updated. At the end of each request, report what the docs now say has
changed, so the owner can see they're current.

## What must never be committed (public repo)

`.gitignore` blocks these; still check `git status` and the staged file list before every commit:
- The owner's dump next to the repo (`../exefs`, `../romfs`, `../control`): never copy, commit or upload it.
- Nintendo data: the dump (`exefs/`, `romfs/`, control files), any Switch container/asset format, keys, firmware.
- Anything made from the game: `games/` (built exe/dll, `*_build/` C code, `*_data/` with dump copy and saves),
  shader caches, captures, screenshots, logs, `threads.txt`, `.hints`, `_work/` symbol caches and dumps.
- Secrets: API tokens, credentials, `.env`, keys/certificates.
- Personal data: the owner's email, Windows user name, local absolute paths. Scripts use paths relative to themselves.
- Game code quoted in docs (function names/addresses as facts are fine; generated C or disassembly is not).

## Build and test

- For an owner playtest update, run `_work/playtest-build.ps1` on the source checkout they want to test. It applies a
  successful build when the game is closed and stages it when it is running. Use `-ApplyPending` after exit.
  To build for an isolated test, use `python/python.exe _work/build.py <output>`.
- Run with `_work/run.ps1 -Seconds N -Keys "t:vk,t:vk+vk@ms"`. Add `-ShotList "a,b" -Tag t` for specific F7
  captures. Usually one to three screenshots cover a visual check. Path to a board with a save: see `docs/JAMBOREE_PORT.md`.
- Test runs use background mode (the default in `run.ps1`, `SWR_BACKGROUND=1`): off-screen, never focused, muted,
  the owner's pad and keyboard ignored, so tests don't interrupt someone using the PC. Don't launch the game in the
  foreground (`-Foreground`, or `Recomp.exe` directly) unless the owner says it's fine at that time.
- Record each bug's evidence, cause and fix in `docs/JAMBOREE_PORT.md` in the same PR as the fix.
- When staging multiple replays of one build, share its binary snapshot on the same volume. Give each replay
  its own working saves and logs. Use a fresh shader cache for cold-load comparisons. See the developer guide.
- Before finishing, record the result and retain only the screenshots or trace files needed for review or an open
  bug. Clear the generated artifacts from test replays created for the task once the needed evidence is saved.
  Preview a completed replay with `_work/finish-replay.ps1 -Replay <name>`, then use `-Apply` to remove its captures
  and shader cache. Add `-Binaries` when the replay's executable and DLL copies can be discarded. Keep checkpoints,
  saves and logs. See the developer guide for the capture limits.
