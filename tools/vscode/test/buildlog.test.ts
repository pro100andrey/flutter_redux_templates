import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as path from 'node:path';
import { BuildLogParser } from '../src/buildlog';

test('parses a failing builder block with a package: location', () => {
  const findings: any[] = [];
  const p = new BuildLogParser('/repo', ['business'], (f: any[]) => findings.push(...f));
  p.feed('E freezed on lib/redux/log_in/models/log_in_state.dart:\n');
  p.feed('  @Default cannot be used on non-optional parameters\n');
  p.feed('  package:business/redux/log_in/models/log_in_state.dart:8:30\n');
  p.feed('Failed to build\n');

  assert.strictEqual(findings.length, 1);
  const f = findings[0];
  assert.strictEqual(f.severity, 'error');
  assert.strictEqual(f.line, 8);
  assert.strictEqual(f.column, 30);
  assert.match(f.message, /@Default cannot be used/);
  assert.strictEqual(f.file, path.join('/repo', 'business', 'lib', 'redux/log_in/models/log_in_state.dart'));
});

test('W header is a warning', () => {
  const findings: any[] = [];
  const p = new BuildLogParser('/repo', ['business'], (f: any[]) => findings.push(...f));
  p.feed('W some_builder on lib/x.dart:\n  heads up\nBuilt with build_runner\n');
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].severity, 'warning');
});

test('a clean cycle emits no findings', () => {
  const cycles: any[] = [];
  const p = new BuildLogParser('/repo', ['business'], (f: any[]) => cycles.push(f));
  p.feed('[INFO] Generating build script...\nBuilt with build_runner\n');
  assert.deepStrictEqual(cycles, [[]]);
});
