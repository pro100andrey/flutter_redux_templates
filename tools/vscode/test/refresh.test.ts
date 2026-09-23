// The refresh scheduler: one refresh at a time, and requests that arrive while
// one runs folded into a single run after it.
import { test } from 'node:test';
import * as assert from 'node:assert';

import { RefreshScheduler, isGenerated } from '../src/refresh';

/** A refresh whose runs the test finishes by hand. */
function gatedWork() {
  const pending: (() => void)[] = [];
  let started = 0;
  const work = () =>
    new Promise<void>((r) => {
      started++;
      pending.push(r);
    });
  return { work, started: () => started, finish: () => pending.shift()?.() };
}

const tick = (): Promise<void> => new Promise((r) => setImmediate(r));

test('requests while a refresh runs become one more run, not one each', async () => {
  const g = gatedWork();
  const s = new RefreshScheduler(g.work);

  const first = s.now();
  // A scaffold's own refresh, the folder watcher's, and a build cycle's —
  // all while the first is still reading.
  const second = s.now();
  const third = s.now();
  s.now();
  assert.strictEqual(g.started(), 1, 'nothing overlaps the running one');

  g.finish();
  await tick();
  assert.strictEqual(g.started(), 2, 'one rerun covers every request made meanwhile');
  g.finish();
  await Promise.all([first, second, third]);
  assert.strictEqual(g.started(), 2);
});

test('a request after the last run finished starts a fresh one', async () => {
  const g = gatedWork();
  const s = new RefreshScheduler(g.work);
  const one = s.now();
  g.finish();
  await one;
  const two = s.now();
  assert.strictEqual(g.started(), 2);
  g.finish();
  await two;
});

test('a burst of file events is one refresh once it goes quiet', async () => {
  let runs = 0;
  const s = new RefreshScheduler(async () => void runs++, 5);
  for (let i = 0; i < 10; i++) s.soon();
  await new Promise((r) => setTimeout(r, 30));
  assert.strictEqual(runs, 1);
});

test('a refresh that throws does not wedge the scheduler', async () => {
  let runs = 0;
  const s = new RefreshScheduler(async () => {
    runs++;
    throw new Error('frx went away');
  });
  await s.now();
  await s.now();
  assert.strictEqual(runs, 2);
});

test('after dispose nothing runs', async () => {
  let runs = 0;
  const s = new RefreshScheduler(async () => void runs++, 5);
  s.soon();
  s.dispose();
  await s.now();
  await new Promise((r) => setTimeout(r, 20));
  assert.strictEqual(runs, 0);
});

test('build_runner output is recognised by name', () => {
  for (const f of ['a/log_in_state.g.dart', 'a/log_in_state.freezed.dart', 'app/lib/navigation/app_router.gr.dart']) {
    assert.strictEqual(isGenerated(f), true, f);
  }
  for (const f of ['a/log_in_state.dart', 'business/lib/redux/log_in', 'a/g.dart']) {
    assert.strictEqual(isGenerated(f), false, f);
  }
});
