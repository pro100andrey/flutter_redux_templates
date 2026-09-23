// The project session: one owner for everything that is about one root, and
// replaced whole when the workspace's project changes.
//
// Before it, the tree, the watch and the code lenses kept the root they were
// built with while the audit, the Map and the Flow view re-resolved — so after
// a change of folders the Problems panel and the tree could be about two
// different apps, and a watch kept building one that was no longer open.
import './helpers';
import { vscode } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import frx = require('../src/frx');
import { ProjectSession, SessionHost } from '../src/session';

class FakeSession {
  disposed = false;
  constructor(readonly root: string) {}
  dispose(): void {
    this.disposed = true;
  }
}

function host(roots: (string | null)[]) {
  const opened: FakeSession[] = [];
  let i = 0;
  const h = new SessionHost(
    (root) => {
      const s = new FakeSession(root);
      opened.push(s);
      return s;
    },
    () => roots[Math.min(i++, roots.length - 1)],
  );
  return { h, opened };
}

test('the same project keeps its session', () => {
  const { h, opened } = host(['/a', '/a']);
  const first = h.sync();
  const second = h.sync();
  assert.strictEqual(first, second);
  assert.strictEqual(opened.length, 1);
});

test('a different project replaces the session whole', () => {
  const { h, opened } = host(['/a', '/b']);
  h.sync();
  const now = h.sync();
  assert.strictEqual(opened[0].disposed, true, 'nothing of the old project outlives it');
  assert.strictEqual(now?.root, '/b');
});

test('no project closes the session, and one arriving later opens it', () => {
  const { h, opened } = host(['/a', null, '/a']);
  h.sync();
  assert.strictEqual(h.sync(), null);
  assert.strictEqual(opened[0].disposed, true);
  assert.strictEqual(h.sync()?.root, '/a');
  assert.strictEqual(opened.length, 2);
});

// --- the real session, over the stub ------------------------------------------

function project(): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'frx_session_'));
  fs.writeFileSync(path.join(root, 'pubspec.yaml'), 'name: r\nworkspace:\n  - app\n');
  return root;
}

/** Captures the folder watchers' change handlers as the session registers them. */
function captureWatchers(): ((uri: any) => void)[] {
  const handlers: ((uri: any) => void)[] = [];
  vscode.workspace.createFileSystemWatcher = () => ({
    onDidCreate: (h: any) => handlers.push(h),
    onDidChange: (h: any) => handlers.push(h),
    onDidDelete: (h: any) => handlers.push(h),
    dispose() {},
  });
  return handlers;
}

function offline(): void {
  (frx as any).resolveFrx = async () => null;
  (frx as any).resolveDartCmd = async () => null;
}

const context = () =>
  ({
    subscriptions: [],
    workspaceState: { get: (_k: string, d: unknown) => d, update: async () => undefined },
  }) as any;

test('build_runner output does not refresh; a source change does, once', async () => {
  offline();
  const handlers = captureWatchers();
  const session = new ProjectSession(context(), project());
  await session.refresh(); // the one at open
  let refreshes = 0;
  session.tree.refresh = async () => void refreshes++;

  const change = handlers[1];
  for (const f of ['state.g.dart', 'state.freezed.dart', 'app_router.gr.dart']) {
    change(vscode.Uri.file(path.join(session.root, 'business/lib/redux/p', f)));
  }
  await new Promise((r) => setTimeout(r, 900));
  assert.strictEqual(refreshes, 0, 'a build cycle writes dozens of these');

  change(vscode.Uri.file(path.join(session.root, 'business/lib/redux/p/state.dart')));
  change(vscode.Uri.file(path.join(session.root, 'business/lib/redux/p/actions.dart')));
  await new Promise((r) => setTimeout(r, 900));
  assert.strictEqual(refreshes, 1);
  session.dispose();
});

test('a closed session leaves nothing on screen', async () => {
  offline();
  captureWatchers();
  vscode._statusBar = [];
  const session = new ProjectSession(context(), project());
  await session.refresh();
  assert.strictEqual(vscode._statusBar.length, 2, 'the watch chip and the doctor chip');

  session.dispose();

  assert.deepStrictEqual(vscode._statusBar, []);
});
