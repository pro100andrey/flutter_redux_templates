import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import { FrxCodeActionProvider } from '../src/code_actions';

/** A doctor diagnostic as the doctor service publishes it. */
function frxDiagnostic(code?: string) {
  return { source: 'frx', code, message: 'frx doctor: …' } as never;
}

function actionsFor(diagnostics: unknown[]) {
  return new FrxCodeActionProvider().provideCodeActions({} as never, {} as never, {
    diagnostics,
  } as never);
}

test('the selector is not pinned to a language', () => {
  // Regression: registered as `{ language: 'dart' }`, the stale-docs finding —
  // which anchors on docs/flows/*.md — showed up in Problems with no way to act
  // on it, because a markdown document never reached the provider.
  const selector = FrxCodeActionProvider.selector as { language?: string; scheme?: string };
  assert.strictEqual(selector.language, undefined, 'any language doctor anchors on');
  assert.strictEqual(selector.scheme, 'file');
});

test('offers one labelled fix per remedy kind', () => {
  const actions = actionsFor([
    frxDiagnostic('flow-docs'),
    frxDiagnostic('flow-docs'), // same remedy twice → still one action
    frxDiagnostic('build_runner'),
  ]);

  assert.strictEqual(actions.length, 2, 'deduped by remedy');
  for (const a of actions) {
    assert.strictEqual(a.command?.command, 'frx.doctorFix');
  }
});

test('ignores other extensions\' diagnostics, and ours without a remedy', () => {
  const actions = actionsFor([
    { source: 'dart', code: 'flow-docs' }, // someone else's
    frxDiagnostic(undefined), // ours, but report-only
  ]);
  assert.deepStrictEqual(actions, []);
});
