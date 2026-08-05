# Issue tracker

**Medium: local markdown.** Tickets live in `agents/tickets/`, one file each,
committed with the code.

Written from observable facts rather than from the `/skills-setup` interview,
which is user-invocation-only. Two answers below are inferred and are the ones
to correct first if they are wrong.

## Where tickets live

`agents/tickets/<nn>-<slug>.md`. The number is the order they were opened, not a
priority. Each file carries its own **Status** and **Blocked by** — those two
fields *are* the tracker, so a ticket whose blockers are all `done` is on the
frontier and can be picked up.

## Why not GitHub Issues

The repository is `pro100andrey/flutter_redux_templates`, it is **public**, it
has issues enabled, and `gh` is authenticated — so GitHub is available and is
probably where these belong once someone other than the author is reading them.

They are here instead because publishing to a public tracker is an outward-facing
act that the author had not confirmed at the time, and a set of tickets is not
something to put in front of strangers on an inference. **Inferred — change this
if GitHub Issues is what you want.**

To move them:

```sh
# from the repo root, once per ticket
gh issue create --title "<title>" --body-file agents/tickets/<file>.md \
  --label ready-for-agent
```

Then rewrite this file to name GitHub as the medium, and replace each ticket's
**Blocked by** list with GitHub's native blocking relationship, so the frontier
lives in the tracker rather than in prose.

## PRs as a request surface

**No.** There are no PRs to triage on a local-markdown tracker. **Inferred** —
the repository does take pull requests (there are merged ones in its history),
so if triage should read them, this is the line to change.
