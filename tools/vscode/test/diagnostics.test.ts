import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import diag = require('../src/diagnostics');

/** A collection that records what was set on it, keyed by fsPath. */
function collection() {
  const byFile = new Map<string, unknown[]>();
  return {
    byFile,
    clear: () => byFile.clear(),
    set: (uri: { fsPath: string }, list: unknown[]) => byFile.set(uri.fsPath, list),
    dispose: () => {},
  };
}

test('a finding with a file lands on that file', () => {
  const c = collection();
  diag.publishByFile(
    c as never,
    [{ file: '/repo/a.dart' }],
    () => ({}) as never,
    '/repo',
  );
  assert.deepStrictEqual([...c.byFile.keys()], ['/repo/a.dart']);
});

test('a finding with no file lands on the fallback, not the floor', () => {
  // The doctor chip counts every finding and its click opens the Problems
  // panel. Dropping a file-less one made the chip say "⚠ 1" over an empty
  // panel — "an empty artifact folder" is about a directory, and "AppState not
  // found" is about its absence, so neither has a file and both are real.
  const c = collection();
  diag.publishByFile(
    c as never,
    [{ file: null }, { file: '/repo/a.dart' }],
    () => ({}) as never,
    '/repo',
  );
  assert.deepStrictEqual([...c.byFile.keys()].sort(), ['/repo', '/repo/a.dart']);
});

test('with no fallback, a file-less finding is still dropped', () => {
  // The build_runner watch passes none: its findings carry a line and column,
  // and one without a file has neither to build a range from.
  const c = collection();
  diag.publishByFile(c as never, [{ file: null }], () => ({}) as never);
  assert.strictEqual(c.byFile.size, 0);
});

test('a finding the mapper rejects is dropped wherever it would have gone', () => {
  const c = collection();
  diag.publishByFile(c as never, [{ file: null }, { file: '/repo/a.dart' }], () => null, '/repo');
  assert.strictEqual(c.byFile.size, 0);
});

// --- the doctor's mapping, which is where the remedy is named -----------------

test('a file-less fixable finding names the command that fixes it', () => {
  // A lightbulb needs a text document to hang off, and a finding about a
  // directory has none. Saying a fix exists and offering no way to reach it is
  // the failure the workspace-root fallback was added to end — one level down.
  const shown: string[] = [];
  const c = {
    clear: () => {},
    set: (_u: unknown, list: { message: string }[]) => shown.push(...list.map((d) => d.message)),
    dispose: () => {},
  };
  diag.publishByFile(
    c as never,
    [
      { file: null, fix: 'orphan', message: 'an empty artifact folder' },
      { file: null, fix: null as string | null, message: 'AppState not found' },
      { file: '/repo/a.dart' as string | null, fix: 'orphan', message: 'an orphan substate' },
    ],
    (f) =>
      ({
        message: `frx doctor: ${f.message}${!f.file && f.fix ? ' — run “FRX: Doctor — fix”.' : ''}`,
      }) as never,
    '/repo',
  );
  assert.deepStrictEqual(shown, [
    'frx doctor: an empty artifact folder — run “FRX: Doctor — fix”.',
    'frx doctor: AppState not found',
    'frx doctor: an orphan substate',
  ]);
});

// --- where a finding is squiggled ---------------------------------------------

test('a finding with a line and column lands on them, 0-based', () => {
  // The CLI reports 1-based positions, as the analyzer does and as a person
  // reads them; the editor counts from 0. Off by one here puts every squiggle
  // on the line *after* the declaration.
  const r = diag.rangeFor({ line: 5, column: 3 }) as any;
  assert.strictEqual(r.start.line, 4);
  assert.strictEqual(r.start.character, 2);
  assert.strictEqual(r.end.line, 4, 'zero-width: the CLI names a point, not an extent');
  assert.strictEqual(r.end.character, 2);
});

test('a finding with a line and no column lands at the start of that line', () => {
  const r = diag.rangeFor({ line: 5 }) as any;
  assert.strictEqual(r.start.line, 4);
  assert.strictEqual(r.start.character, 0);
});

test('a finding with no position lands at the top of the file', () => {
  // Where every doctor finding used to land. Still the honest anchor for one
  // about a file as a whole — a missing part, a stale export.
  const r = diag.rangeFor({}) as any;
  assert.strictEqual(r.start.line, 0);
  assert.strictEqual(r.start.character, 0);
});

test('a column without a line is not a position', () => {
  // Half an anchor: the CLI never emits it, but a consumer that trusted it
  // would squiggle column 7 of line 1, which names nothing.
  const r = diag.rangeFor({ column: 7 }) as any;
  assert.strictEqual(r.start.line, 0);
  assert.strictEqual(r.start.character, 0);
});
