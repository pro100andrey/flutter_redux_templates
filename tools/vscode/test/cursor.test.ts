import './helpers';
import { vscode } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import frx = require('../src/frx');
import paths = require('../src/paths');
import queries = require('../src/queries');
import cursor = require('../src/cursor');

/* eslint-disable @typescript-eslint/no-explicit-any */

/// What artifact the cursor is on — the one resolution F2 and the editor
/// context-menu entry share.
///
/// Worth its own file because the entry it fixes had a specific failure: it threw
/// the cursor away and showed the palette's generic picker, so right-clicking a
/// state class offered you every substate and page in the project.

/** A document whose single word is `word`, at any position. */
function documentWith(word: string, languageId = 'dart'): any {
  return {
    languageId,
    getWordRangeAtPosition: () => (word ? { start: 0, end: word.length } : undefined),
    getText: () => word,
  };
}

/** Puts `doc` in the active editor and makes frx resolvable at /repo. */
function open(doc: any): void {
  (vscode.window as any).activeTextEditor = { document: doc, selection: { active: {} } };
  (paths as any).findWorkspaceRoot = () => '/repo';
  (frx as any).resolveFrx = async () => ({ label: 'frx' });
}

test('artifactAtActiveCursor: an frx symbol resolves to its artifact', async () => {
  open(documentWith('LogInState'));
  (queries as any).which = async (_inv: unknown, token: string) => {
    assert.strictEqual(token, 'LogInState', 'the word under the cursor is what is asked about');
    return { kind: 'substate', name: 'log_in', suffix: 'State', prefix: null };
  };
  const match = await cursor.artifactAtActiveCursor({} as any);
  assert.strictEqual(match?.name, 'log_in');
  assert.strictEqual(match?.kind, 'substate');
});

test('artifactAtActiveCursor: a symbol frx does not own is null, not a guess', async () => {
  // Null is what makes the caller fall back to the picker.
  open(documentWith('SomeRandomWidget'));
  (queries as any).which = async () => null;
  assert.strictEqual(await cursor.artifactAtActiveCursor({} as any), null);
});

test('artifactAtActiveCursor: no editor at all is null', async () => {
  (vscode.window as any).activeTextEditor = undefined;
  (queries as any).which = async () => {
    throw new Error('must not ask the CLI with no editor open');
  };
  assert.strictEqual(await cursor.artifactAtActiveCursor({} as any), null);
});

test('artifactAtActiveCursor: a non-Dart editor is null', async () => {
  // The conventions are Dart symbols; a markdown word that happens to match one
  // is not a rename target.
  open(documentWith('LogInState', 'markdown'));
  (queries as any).which = async () => {
    throw new Error('must not ask the CLI about a non-Dart file');
  };
  assert.strictEqual(await cursor.artifactAtActiveCursor({} as any), null);
});

test('artifactAtActiveCursor: the cursor on no word at all is null', async () => {
  open(documentWith(''));
  (queries as any).which = async () => {
    throw new Error('must not ask the CLI about an empty range');
  };
  assert.strictEqual(await cursor.artifactAtActiveCursor({} as any), null);
});

test('artifactAtActiveCursor: an unresolvable workspace is null', async () => {
  open(documentWith('LogInState'));
  (paths as any).findWorkspaceRoot = () => undefined;
  (queries as any).which = async () => {
    throw new Error('must not ask the CLI without a root');
  };
  assert.strictEqual(await cursor.artifactAtActiveCursor({} as any), null);
});
