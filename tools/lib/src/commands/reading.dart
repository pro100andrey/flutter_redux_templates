/// What the reading commands share that the writing base does not give them.
///
/// `flow` and `graph` read rather than write, so they are not built on
/// `WritingCommand` — and they render a refusal themselves, in their own
/// prefix, rather than letting it reach the runner's `✗`. Five sites spelled
/// the two lines out; the prefix is the thing that must not drift between
/// them.
library;

import '../refusal.dart';
import '../util/console.dart';

/// Reports [refusal] the way a reading command does, and hands back the exit
/// code it returns for one.
///
/// `frx: <message>` on stderr and 70 — the same code the runner uses for the
/// refusals it renders, so a consumer keyed on the code reads both alike.
int refused(FrxRefusal refusal) {
  console.err.writeln('frx: ${refusal.message}');
  return 70;
}
