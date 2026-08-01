import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import naming = require('../src/naming');

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
