# Triage labels

The vocabulary the engineering skills use. On a local-markdown tracker a label
is a line in the ticket's front block, not a tracker object — but the strings are
the same ones `gh label create` would need, so moving to GitHub Issues is a
copy rather than a translation.

## Status

Exactly one per ticket, on the ticket's `Status:` line.

| Status | Meaning |
|---|---|
| `open` | Not started. Blockers may or may not be clear. |
| `in-progress` | Someone is on it. |
| `done` | Merged. The ticket names the commit(s). |
| `dropped` | Deliberately not done. The ticket says why — this is the one that must never be deleted, because the reasoning is what stops it being re-raised. |

## Labels

Zero or more per ticket.

| Label | Meaning |
|---|---|
| `ready-for-agent` | Scoped tightly enough for an unattended agent: the acceptance criteria are checkable without asking anyone. |
| `needs-decision` | Blocked on a judgement the author has to make, not on other work. |
| `defect` | Something is wrong now, as opposed to something that could be better. |
| `architecture` | Changes a seam or a module's interface rather than behaviour. |

`ready-for-agent` and `needs-decision` are mutually exclusive by construction.

## GitHub's defaults

The repository carries GitHub's stock labels (`bug`, `enhancement`,
`documentation`, …). They are not part of this vocabulary and nothing here maps
onto them; if these tickets move to GitHub Issues, `defect` is the one that
overlaps `bug`, and picking one spelling matters more than which.
