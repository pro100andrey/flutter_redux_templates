# One read model of the monorepo, not twelve

**Status:** done
**Labels:** architecture, defect
**Blocked by:** #01, #03
**Landed in:** `5822186`, `9ebcfc4`

## What to build

`SourceIndex` memoises parses; every reader re-derives meaning.

## Acceptance criteria

- [x] `graph_reader` applies the substate rule — a latent defect, not only
      duplication
- [x] The join/split round-trip through a display string is gone
- [x] `vm_reader` parses through the index
- [x] `selectors.dart` is located one way
- [ ] "The facts above are derived once" in general — four of the named facts;
      two turned out not to be defects, see Notes

## Notes

The round-trip was the sharp one: `ActionInfo.writes` was a `String?` joined
with `', '` and split back apart by `graph_reader` to raise one edge per
substate. A rendering choice was the only channel between two readers of a
structural fact — change the separator and the graph silently loses its write
edges.

**Two named facts were not defects, and the checking is the point:**

- The graph is not blind to anything on `mixin Selectors`. Only spine getters
  are written there; `addSelector` targets extension types and never the mixin.
  Recorded in `SelectorShape.of` so this is not re-raised.
- route→connector is already single-sourced through `PageArtifact`. What repeats
  is a three-line calling sequence with different follow-ups; a helper would
  move complexity rather than concentrate it.
