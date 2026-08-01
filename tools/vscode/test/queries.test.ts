import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as path from 'node:path';
import frx = require('../src/frx');
import queries = require('../src/queries');

/** Make the next frx.run resolve to `result` (queries reads frx.run at call time). */
function stubRun(result: { code: number; stdout: string; stderr: string }): void {
  // See ui.test.ts: the stub must land on the real module export.
  (frx as any).run = async () => result;
}

test('listSubstates: array on success', async () => {
  stubRun({ code: 0, stdout: JSON.stringify({ substates: [{ field: 'a', type: 'A', file: '/a' }] }), stderr: '' });
  assert.deepStrictEqual(await queries.listSubstates({} as any, '/r'), [{ field: 'a', type: 'A', file: '/a' }]);
});

test('listSubstates: [] on read-fine-but-empty', async () => {
  stubRun({ code: 0, stdout: JSON.stringify({ substates: [] }), stderr: '' });
  assert.deepStrictEqual(await queries.listSubstates({} as any, '/r'), []);
});

test('listSubstates: null on non-zero exit (unavailable)', async () => {
  stubRun({ code: 70, stdout: '', stderr: 'no project' });
  assert.strictEqual(await queries.listSubstates({} as any, '/r'), null);
});

test('listSubstates: null on malformed JSON (missing key) — not []', async () => {
  stubRun({ code: 0, stdout: '{}', stderr: '' });
  assert.strictEqual(await queries.listSubstates({} as any, '/r'), null);
});

test('graph: nodes and orphans on success', async () => {
  stubRun({
    code: 0,
    stdout: JSON.stringify({
      nodes: [{ id: 'substate:a', kind: 'substate', name: 'a' }],
      orphans: [{ node: 'action:a.X', why: 'no dispatcher found' }],
    }),
    stderr: '',
  });
  const g = await queries.graph({} as any, '/r');
  assert.strictEqual(g!.nodes.length, 1);
  assert.strictEqual(g!.orphans[0].node, 'action:a.X');
});

test('graph: every section is an array, not undefined', async () => {
  // Four consumers read four sections; a missing one must read as "none", not
  // crash the tree or the structural picture on `.filter` of undefined.
  stubRun({ code: 0, stdout: JSON.stringify({ nodes: [] }), stderr: '' });
  const g = await queries.graph({} as any, '/r');
  assert.deepStrictEqual(g, { nodes: [], edges: [], unresolved: [], orphans: [] });
});

test('graph: null on malformed JSON (missing nodes) — not an empty graph', async () => {
  stubRun({ code: 0, stdout: '{}', stderr: '' });
  assert.strictEqual(await queries.graph({} as any, '/r'), null);
});

test('doctor: parses on exit 1 (issues found)', async () => {
  stubRun({ code: 1, stdout: JSON.stringify({ findings: [{ message: 'x' }] }), stderr: '' });
  const d = await queries.doctor({} as any, '/r');
  assert.strictEqual(d!.findings.length, 1);
});

test('doctor: null on exit 70 (no JSON)', async () => {
  stubRun({ code: 70, stdout: 'not json', stderr: '' });
  assert.strictEqual(await queries.doctor({} as any, '/r'), null);
});

test('which: null on non-zero exit', async () => {
  stubRun({ code: 1, stdout: '', stderr: '' });
  assert.strictEqual(await queries.which({} as any, 'X', '/r'), null);
});

test('which: null when kind missing', async () => {
  stubRun({ code: 0, stdout: JSON.stringify({ kind: null }), stderr: '' });
  assert.strictEqual(await queries.which({} as any, 'X', '/r'), null);
});

test('which: match when kind present', async () => {
  stubRun({ code: 0, stdout: JSON.stringify({ kind: 'substate', name: 'logIn', suffix: 'State', prefix: null }), stderr: '' });
  const m = await queries.which({} as any, 'LogInState', '/r');
  assert.ok(m, 'a match was returned');
  assert.strictEqual(m.kind, 'substate');
  assert.strictEqual(m.name, 'logIn');
});

test('createdFile: resolves a create/overwrite plan line by suffix', () => {
  const stdout = 'create business/lib/redux/log_in/models/log_in_state.dart\ncreate other.dart';
  assert.strictEqual(
    queries.createdFile(stdout, '/repo', '_state.dart'),
    path.resolve('/repo', 'business/lib/redux/log_in/models/log_in_state.dart'),
  );
  assert.strictEqual(queries.createdFile('nothing here', '/repo', '_state.dart'), null);
});

test('routeMap: the trimmed flowchart on success', async () => {
  stubRun({ code: 0, stdout: 'flowchart LR\n  a --> b\n\n', stderr: '' });
  assert.strictEqual(await queries.routeMap({} as any, '/r'), 'flowchart LR\n  a --> b');
});

test('routeMap: null on failure, so the caller can surface frx\'s own message', async () => {
  stubRun({ code: 70, stdout: '', stderr: 'no AppRouter' });
  assert.strictEqual(await queries.routeMap({} as any, '/r'), null);
});

test('routeMap: asks the CLI for the whole app, not one page', async () => {
  let seen: string[] | undefined;
  (frx as any).run = async (_inv: unknown, args: string[]) => ((seen = args), { code: 0, stdout: 'flowchart LR', stderr: '' });
  await queries.routeMap({} as any, '/r');
  assert.deepStrictEqual(seen, ['flow', '--routes', '--root', '/r']);
});
