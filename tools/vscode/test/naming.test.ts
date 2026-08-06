import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import naming = require('../src/naming');
import { NAMING_CASES } from '../src/generated/contract';

// `naming.ts` is the one part of the CLI's contract the extension re-implements
// rather than imports: a casing conversion is an algorithm, and there is no
// emitting an algorithm as data. `NAMING_CASES` is the CLI's own answer for the
// inputs the editor is actually handed, so a rule that changes in Dart fails
// here instead of quietly proposing the wrong class name in a picker.
test('camelOf / pascalOf agree with the CLI\'s Casing', () => {
  for (const c of NAMING_CASES) {
    assert.strictEqual(naming.camelOf(c.input), c.camel, `camelOf(${c.input})`);
    assert.strictEqual(naming.pascalOf(c.input), c.pascal, `pascalOf(${c.input})`);
  }
});

test('camelOf: snake → camelCase, stray __ dropped', () => {
  assert.strictEqual(naming.camelOf('my_profile'), 'myProfile');
  assert.strictEqual(naming.camelOf('log_in'), 'logIn');
  assert.strictEqual(naming.camelOf('theme'), 'theme');
  assert.strictEqual(naming.camelOf('a__b'), 'aB');
});

test('pascalOf: snake → PascalCase', () => {
  assert.strictEqual(naming.pascalOf('my_profile'), 'MyProfile');
  assert.strictEqual(naming.pascalOf('log_in'), 'LogIn');
});

test('stripSuffix: only when present', () => {
  assert.strictEqual(naming.stripSuffix('LogInRoute', 'Route'), 'LogIn');
  assert.strictEqual(naming.stripSuffix('Home', 'Route'), 'Home');
});

test('stripAffix: drops suffix and/or prefix, never empty', () => {
  assert.strictEqual(naming.stripAffix('LogInState', 'State', null), 'LogIn');
  assert.strictEqual(naming.stripAffix('SelectLogIn', null, 'Select'), 'LogIn');
  assert.strictEqual(naming.stripAffix('State', 'State', null), 'State');
});
