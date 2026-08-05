import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import { ambiguousKinds } from '../src/commands/artifact';

// `remove` exits 64 both for "your name matched more than one kind" and for any
// ordinary usage error. Only the first should raise a picker, and the difference
// is read out of the message — so these pin what counts as which.

test('the two-kind message the CLI has always emitted still parses', () => {
  assert.deepStrictEqual(
    ambiguousKinds(
      '"Profile" matches both a substate (profile) and a page (ProfileRoute). ' +
        'Disambiguate with --kind substate|page.',
    ),
    ['substate', 'page'],
  );
});

test('the counted message the new kinds emit parses, in the CLI’s order', () => {
  // Order comes from ARTIFACT_KINDS, not from the message: the picker should
  // read the same way whichever kinds collided.
  assert.deepStrictEqual(
    ambiguousKinds(
      '"Home" matches 2 kinds (page, connector). Disambiguate with --kind page|connector.',
    ),
    ['page', 'connector'],
  );
});

test('a usage error that merely mentions a kind raises no picker', () => {
  // The failure this prevents: offering "which of these to delete?" for a
  // message that was not about ambiguity at all.
  assert.deepStrictEqual(
    ambiguousKinds('Expected 1 argument: <name>.'),
    [],
  );
  assert.deepStrictEqual(
    ambiguousKinds('--state is only meaningful with --kind action.'),
    [],
  );
});

test('a single kind is not an ambiguity', () => {
  assert.deepStrictEqual(
    ambiguousKinds('No widget "Nope" — no nope.dart in any ui/lib widget folder.'),
    [],
  );
});

test('the page-connector redirect is not offered as a choice', () => {
  // Names two kinds and says --kind, and is still not a fork: the connector of a
  // page cannot be removed on its own at all. Offering it would put the one
  // answer the CLI just refused into the picker, and the user would pick it.
  const msg =
    '"HomePageConnector" is the connector of page "home", not a standalone ' +
    'connector — removing it alone would leave the route pointing at nothing. ' +
    'Remove the page instead: frx remove home --kind page.';
  assert.deepStrictEqual(ambiguousKinds(msg), []);
});

test('an ambiguity needing --state is not a --kind picker', () => {
  // The extension has no `--state` prompt, so this must fall through to the
  // message rather than opening a picker that cannot resolve it.
  assert.deepStrictEqual(
    ambiguousKinds(
      '"Reset" names an action under 2 substates (tasks, projects). ' +
        'Disambiguate with --state <substate>.',
    ),
    [],
  );
});
