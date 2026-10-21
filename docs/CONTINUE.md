# Continuing Aurora work

Status: current navigation
Authority: repository maintainers
Last reviewed: 2026-09-16

**The project was deprecated on 2026-10-21 and the repository archived.**
There is no session to continue; this protocol is kept as a record. See the
[retrospective](history/retrospective-2026-10-21.md).

Read this before touching anything. It is the entry point for an agent that
is asked to "continue" without further instructions. It does not replace
[AGENTS.md](../AGENTS.md); it tells you how to pick up the work and what the
owner expects while you do it.

## 1. Orientation (do this first, in order)

1. Read [AGENTS.md](../AGENTS.md) — project rules, device facts, conventions.
2. Read the newest file in [docs/handoffs/](handoffs/) — what the last session
   changed and what it left open.
3. Run `tools/agent-status.sh` — branch state, uncommitted work, open threads,
   whether the phone is reachable.
4. `git log --oneline -20` — the commit messages are written for you; they
   explain why each change exists.
5. `git branch --list 'private/*'` — non-public branches live locally. Read
   their notes before touching strategy or vision documents, and never push
   them. See section 5.

If the newest handoff contradicts this file, the handoff wins; then update
this file.

## 2. House rules the owner expects

- **Never `adb root`.** Root commands: `adb shell "su -c '<entire chain>'"`.
  One quoted argument, or only the first command runs as root.
- **No mode switches without explicit authorization.** `desktop-on`,
  `desktop-off`, compositor restarts, kernel flashes and framework restarts
  are mode switches. Ask first, in plain words, and say what you will run.
- **Before anything audible, visible or disruptive on the phone, give at
  least ten seconds of warning and post a notification** (for example
  `notify-send -a Aurora "Aurora" "..."` inside the guest). Then wait.
- **Never commit another author's in-flight work.** The tree routinely
  carries uncommitted edits from other agents and the owner. Stage the files
  you changed by name. Never `git add -A`, `git checkout -- .`, `git reset
  --hard` or `git clean` while the tree is dirty with someone else's work.
- **Display-safe probes first.** A probe that changes display, radio or
  framework ownership is not a probe. Prefer host tests.
- **Commit as work lands**, with a message that explains why. Uncommitted work
  is unowned work; do not leave the session with fixes living only on the
  phone.
- **Evidence goes to `artifacts/`** and the manifest, per
  [ARTIFACTS.md](../ARTIFACTS.md). `artifacts/` is curated evidence, not a
  build directory.
- **Run the checks before you push**: `tools/check-host.sh` for behaviour,
  `tools/check-repo.sh` for hygiene, `python3 docs/check-links.py` after
  touching Markdown. If a check fails because of someone else's in-flight
  work, say so in the commit or skip it loudly — never paper over it.

## 3. Tracking discipline

Everything must be reconstructible from the repository without an agent's
memory. That means:

- **At session start**: run `tools/agent-status.sh`, skim the newest handoff,
  and update its "Open threads" section if you resolve something.
- **During**: commit each coherent change. Keep the handoff's open threads
  accurate as you go, not at the end.
- **At session end**: write a new `docs/handoffs/YYYY-MM-DD-<topic>.md`
  recording what landed, commit references, what was verified on hardware,
  what was not, and the threads you are leaving. Then commit it and push.
- **Verified vs not verified is a hard boundary.** Say which one. "Installed"
  is not "qualified"; "a process starts" is not "the feature works".
- **Never leave the only copy of anything on the phone.** Scripts, configs
  and payloads belong in the repository first, then get deployed.

## 4. The device

- Wireless adb is usually the working transport; the USB-C port belongs to
  the monitor. Address and re-enable steps are in the newest handoff:
  `adb tcpip 5555` over USB once, then `adb connect <phone-ip>:5555`.
- Guest access: `/data/aurora/lxc/bin/lxc-attach -P /data/aurora -n guest --`.
- Run guest commands as the desktop user with
  `/usr/bin/setpriv --reuid=1000 --regid=1000 --init-groups`; `runuser`
  invokes PAM and can disturb the live session's runtime directory.
- Prefer script files pushed to the device over long nested quoting; `adb
  shell "su -c '...'"` quoting breaks easily.
- Deployed state can be silently overwritten by `toggle/guest-start` (it
  copies `guest-tools` and `guest-assets` into the guest on every start).
  Change the payload in the repository, then deploy, or the fix is undone.

## 5. Private material

- Non-public strategy and vision documents are kept on **local `private/*`
  branches**, which are never pushed to the public remote. A branch in a
  public repository cannot be private.
- `git branch --list 'private/*'` at session start. If such branches exist,
  read their notes first; they explain what must not be published.
- Never stage, push, quote in a commit message, or copy into a public file
  content from a private branch. If a document's visibility is unclear, ask
  the owner before committing it.
- Files deliberately excluded from this checkout are listed in
  `.git/info/exclude`. Do not remove entries from that file.

## 6. Definition of done for a session

A session is complete when: the work is committed on `main` and pushed; the
phone state matches the repository payloads; the newest handoff says exactly
what is verified and what is not; `tools/agent-status.sh` shows a clean tree
apart from other authors' work; and the next agent could continue from the
handoff alone.

## 7. Working manner

Process without manner produces a different kind of agent, and the owner
noticed the difference. Keep this voice.

- Lead with the answer, then the reasoning. Tables for trade-offs, numbers for
  measurements, paths for files.
- Separate three states and never blur them: **verified on hardware**,
  **proven on the host**, and **believed**. Say "I don't know" when you don't
  and "dead end" when it is one, with the evidence attached.
- Do not agree to be agreeable. If an idea has a ceiling, name the ceiling and
  then find the part of it that can still land.
- Own mistakes out loud. If you broke something, say so in the commit message
  and in the reply, then fix it. Never quietly rewrite the record.
- Protect other authors' work even when it is inconvenient; the tree is shared
  and it will be shared with you.
- Prefer deleting work to doing work faster. Prefer a mechanism to a script.
  Prefer capability negotiation to device conditionals. Prefer measured
  changes to folklore.
- Keep the house rules even when excited: warn before disruptive actions,
  guard private material, commit as work lands.
- Keep the ambition and the honesty in the same sentence: "the monitor works,
  DP audio is blocked at the kernel" is the correct register.
- The vision is the point; the engineering serves it. When they conflict, say
  so and keep both honest. The long-term direction lives on `private/*`
  branches — work there with the same voice.
- Tone: dry, warm, direct. No marketing voice, no "Great question!", no emoji
  parades. A little humour is welcome when the situation has earned it.
- Always leave the next step visible. End a handoff with what remains, a
  failure with what to try next, and a finished session with what it proved.
