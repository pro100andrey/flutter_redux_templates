// The watch toggle's state machine.
//
// State is `enabled` (persisted in workspaceState) × `running` (a live child),
// and the two disagree in exactly one place: a watch that died under us. That
// state is the reason the toggle exists to be clicked — the crash notification,
// the amber status chip and the overlay row all call that click "restart" — and
// it was the one the toggle got wrong, because it branched on `enabled`.
//
// Testable at all only through the spawn seam: every transition here is decided
// by whether a process is alive.
import './helpers';
import { vscode } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import { EventEmitter } from 'node:events';

import { FrxWatch, SpawnFn } from '../src/watch';

/** A child process that never runs anything but can be made to exit. */
class FakeChild extends EventEmitter {
  readonly stdout = new EventEmitter();
  readonly stderr = new EventEmitter();
  killed = false;
  kill(): boolean {
    this.killed = true;
    return true;
  }
}

interface Harness {
  watch: FrxWatch;
  /** The child of the most recent successful start. */
  child(): FakeChild;
  /** How many times a process was spawned. */
  spawns(): number;
  /** The persisted `enabled` flag, read the way the extension host would. */
  persisted(): boolean;
}

function harness(): Harness {
  const children: FakeChild[] = [];
  const store = new Map<string, unknown>();
  const context = {
    subscriptions: [] as { dispose(): void }[],
    workspaceState: {
      get: (k: string, d: boolean) => (store.has(k) ? store.get(k) : d),
      update: async (k: string, v: unknown) => void store.set(k, v),
    },
  };
  const spawn: SpawnFn = () => {
    const child = new FakeChild();
    children.push(child);
    return child as never;
  };
  // `__dirname` only has to be a readable directory — it holds no pubspec, so
  // the build-log parser starts with no packages, which this test never feeds.
  const watch = new FrxWatch(
    context as never,
    __dirname,
    async () => '/usr/bin/dart',
    spawn,
  );
  return {
    watch,
    child: () => children[children.length - 1],
    spawns: () => children.length,
    persisted: () => store.get('frx.watchEnabled') === true,
  };
}

/** The watch dies on its own — the transition into `enabled but stopped`. */
function die(h: Harness): void {
  h.child().emit('exit', 1);
}

test('off → running: the toggle starts one process and persists ON', async () => {
  const h = harness();
  assert.strictEqual(h.watch.running, false);
  assert.strictEqual(h.watch.enabled, false);

  await h.watch.toggle();

  assert.strictEqual(h.watch.running, true);
  assert.strictEqual(h.watch.enabled, true);
  assert.strictEqual(h.persisted(), true);
  assert.strictEqual(h.spawns(), 1);
});

test('running → off: the toggle kills the process and persists OFF', async () => {
  const h = harness();
  await h.watch.toggle();
  const child = h.child();

  await h.watch.toggle();

  assert.strictEqual(child.killed, true);
  assert.strictEqual(h.watch.running, false);
  assert.strictEqual(h.watch.enabled, false);
  assert.strictEqual(h.persisted(), false);
});

test('a watch that dies under us lands in enabled-but-stopped', async () => {
  const h = harness();
  await h.watch.toggle();

  die(h);

  assert.strictEqual(h.watch.running, false, 'the process is gone');
  assert.strictEqual(h.watch.enabled, true, 'but the user never turned it off');
});

test('enabled but stopped → running: the toggle restarts, it does not switch off', async () => {
  // The defect this pins: branching on `enabled` made this click persist OFF,
  // so the click three separate messages describe as "restart" turned the watch
  // off instead, and restarting took two.
  const h = harness();
  await h.watch.toggle();
  die(h);

  await h.watch.toggle();

  assert.strictEqual(h.watch.running, true, 'the toggle must restart the watch');
  assert.strictEqual(h.watch.enabled, true);
  assert.strictEqual(h.persisted(), true, 'and must not persist OFF');
  assert.strictEqual(h.spawns(), 2, 'a second process was started');
});

test('a stop we asked for raises no "stopped unexpectedly" warning', async () => {
  // `_kill()` nulls the child before terminating, so the exit it causes is not
  // the current one. Without that, every deliberate stop would nag.
  const warnings: string[] = [];
  const original = vscode.window.showWarningMessage;
  vscode.window.showWarningMessage = async (m: string) => void warnings.push(m);
  try {
    const h = harness();
    await h.watch.toggle();
    const child = h.child();
    await h.watch.toggle();
    child.emit('exit', 0); // the SIGTERM arriving

    assert.deepStrictEqual(warnings, []);
    assert.strictEqual(h.watch.running, false);
  } finally {
    vscode.window.showWarningMessage = original;
  }
});
