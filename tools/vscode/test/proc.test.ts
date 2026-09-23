// Starting processes: which `dart` a machine has, and how a batch file is run.
//
// Described through `HostEnv`, so a Windows machine can be tested from Linux —
// the platform where bare `dart` was never found is the one CI does not run on.
import { test } from 'node:test';
import * as assert from 'node:assert';
import { EventEmitter } from 'node:events';

import { findDart, launchSpec, spawnAndForget } from '../src/proc';
import type { HostEnv } from '../src/proc';

function windows(files: string[], pathVar: string): HostEnv {
  const have = new Set(files.map((f) => f.toLowerCase()));
  return {
    platform: 'win32',
    pathVar,
    comspec: 'C:\\Windows\\system32\\cmd.exe',
    isFile: (c) => have.has(c.toLowerCase()),
  };
}

test('off Windows, dart is the bare name and PATH decides', () => {
  assert.strictEqual(findDart({ platform: 'linux', isFile: () => false }), 'dart');
  assert.strictEqual(findDart({ platform: 'darwin', isFile: () => false }), 'dart');
});

test('a standalone SDK: dart.exe on PATH, by its absolute path', () => {
  const env = windows(['C:\\tools\\dart-sdk\\bin\\dart.exe'], 'C:\\Windows;C:\\tools\\dart-sdk\\bin');
  assert.strictEqual(findDart(env), 'C:\\tools\\dart-sdk\\bin\\dart.exe');
});

test('a Flutter-only install: the SDK dart.bat would run, not dart.bat itself', () => {
  // flutter\bin holds dart.bat and no dart.exe — bare `dart` was ENOENT here.
  const env = windows(
    ['C:\\src\\flutter\\bin\\dart.bat', 'C:\\src\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe'],
    'C:\\Windows;C:\\src\\flutter\\bin',
  );
  assert.strictEqual(findDart(env), 'C:\\src\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe');
});

test('a Flutter install whose SDK cache is not there yet: the batch file', () => {
  const env = windows(['C:\\src\\flutter\\bin\\dart.bat'], 'C:\\src\\flutter\\bin');
  assert.strictEqual(findDart(env), 'C:\\src\\flutter\\bin\\dart.bat');
});

test('an .exe anywhere on PATH wins over a batch file earlier on it', () => {
  const env = windows(
    ['C:\\flutter\\bin\\dart.bat', 'C:\\dart\\bin\\dart.exe'],
    'C:\\flutter\\bin;C:\\dart\\bin',
  );
  assert.strictEqual(findDart(env), 'C:\\dart\\bin\\dart.exe');
});

test('no dart at all is null, not a bare name that ENOENTs', () => {
  assert.strictEqual(findDart(windows([], 'C:\\Windows')), null);
});

test('an executable is launched as itself, arguments untouched', () => {
  const env = windows([], '');
  assert.deepStrictEqual(launchSpec('C:\\dart\\dart.exe', ['run', 'a b'], env), {
    command: 'C:\\dart\\dart.exe',
    args: ['run', 'a b'],
  });
  // Off Windows a `.bat` suffix means nothing.
  assert.deepStrictEqual(launchSpec('/x/frx.cmd', ['a'], { platform: 'linux', isFile: () => false }), {
    command: '/x/frx.cmd',
    args: ['a'],
  });
});

test('a batch file runs through cmd.exe, every argument quoted and caret-escaped', () => {
  const env = windows([], '');
  const spec = launchSpec('C:\\Program Files\\flutter\\bin\\dart.bat', ['run', 'C:\\my app\\', 'a&b', 'say "hi"'], env);
  assert.strictEqual(spec.command, 'C:\\Windows\\system32\\cmd.exe');
  assert.strictEqual(spec.windowsVerbatimArguments, true);
  assert.deepStrictEqual(spec.args.slice(0, 3), ['/d', '/s', '/c']);
  assert.strictEqual(
    spec.args[3],
    '"' +
      [
        // The command's space is caret-escaped, so cmd.exe does not split it.
        'C:\\Program^ Files\\flutter\\bin\\dart.bat',
        '^^^"run^^^"',
        // The trailing backslash is doubled so it cannot eat the closing quote.
        '^^^"C:\\my^^^ app\\\\^^^"',
        // `&` would otherwise end the command and start another.
        '^^^"a^^^&b^^^"',
        '^^^"say^^^ \\^^^"hi\\^^^"^^^"',
      ].join(' ') +
      '"',
  );
});

test('a configured frx.cmd is launched the same way', () => {
  const spec = launchSpec('C:\\frx\\frx.CMD', ['--version'], windows([], ''));
  assert.strictEqual(spec.command, 'C:\\Windows\\system32\\cmd.exe');
});

test('a helper that cannot be started is a non-event, not an uncaught error', () => {
  const child = new EventEmitter();
  const started = spawnAndForget(() => child as never, 'pkill', ['-INT', '-P', '1']);
  assert.strictEqual(started, child);
  // With no listener this would throw — which, in the extension host, is an
  // uncaught exception raised by a stop the user asked for.
  assert.doesNotThrow(() => child.emit('error', Object.assign(new Error('spawn pkill ENOENT'), { code: 'ENOENT' })));
  assert.strictEqual(spawnAndForget(() => { throw new Error('EMFILE'); }, 'pkill', []), null);
});
