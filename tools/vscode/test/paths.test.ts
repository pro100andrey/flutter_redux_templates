import './helpers';
import { vscode } from './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import paths = require('../src/paths');

/** A folder tree, returned as its root. */
function tree(files: Record<string, string>): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'frx_paths_'));
  for (const [rel, body] of Object.entries(files)) {
    const file = path.join(root, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, body);
  }
  return root;
}

function open(root: string): void {
  (vscode as any).workspace.workspaceFolders = [{ uri: { fsPath: root } }];
  // The resolved project is cached per window, so a test opening a different
  // one has to say so — the same call the extension makes when the workspace
  // folders change.
  paths.forgetWorkspaceRoot();
}

const ROUTER = 'app/lib/navigation/app_router.dart';

test('our monorepo: a pub workspace laid out the way frx writes', () => {
  const root = tree({
    'pubspec.yaml': 'name: r\nworkspace:\n  - app\n',
    [ROUTER]: 'class AppRouter {}\n',
  });
  open(root);
  assert.strictEqual(paths.findWorkspaceRoot(), root);
});

test('an unrelated pub workspace is not ours', () => {
  // `workspace:` is an ordinary Dart 3.6 feature and says nothing about this
  // template. On that test alone the extension woke up in other people's
  // projects: an empty tree, a watch toggle for a build that is not ours, and a
  // doctor chip parked on "? doctor" because every audit exits 70.
  open(tree({ 'pubspec.yaml': 'name: r\nworkspace:\n  - packages/core\n' }));
  assert.strictEqual(paths.findWorkspaceRoot(), null);
});

test('our layout without a pub workspace is not ours either', () => {
  // The pub-workspace test is the one the *build* needs:
  // `build_runner --workspace` is only valid in a workspace root.
  open(tree({ 'pubspec.yaml': 'name: r\n', [ROUTER]: 'class AppRouter {}\n' }));
  assert.strictEqual(paths.findWorkspaceRoot(), null);
});

test('a plain app with no pubspec workspace key is not ours', () => {
  open(tree({ 'pubspec.yaml': 'name: myapp\n' }));
  assert.strictEqual(paths.findWorkspaceRoot(), null);
});

test('no folders open at all', () => {
  (vscode as any).workspace.workspaceFolders = [];
  paths.forgetWorkspaceRoot();
  assert.strictEqual(paths.findWorkspaceRoot(), null);
});

// --- a template unpacked into somebody else's repository ---------------------
//
// The layout that made this necessary: `bloom/` is a pub workspace whose own
// root has no router, and the app is at `apps/tm_console` — its own pub
// workspace, laid out the way frx writes. Testing only the workspace folders
// answered "not ours", which is not a degraded extension but no extension at
// all, with nothing on screen to say why.

const NESTED = {
  'pubspec.yaml': 'name: outer\nworkspace:\n  - packages/core\n',
  'packages/core/pubspec.yaml': 'name: core\nresolution: workspace\n',
  'apps/tm_console/pubspec.yaml': 'name: app_ws\nworkspace:\n  - app\n',
  [`apps/tm_console/${ROUTER}`]: 'class AppRouter {}\n',
};

test('a project below the workspace folder is found', () => {
  const root = tree(NESTED);
  open(root);
  assert.strictEqual(paths.findWorkspaceRoot(), path.join(root, 'apps/tm_console'));
});

test('the folder itself still wins, and costs no scan', () => {
  const root = tree({
    'pubspec.yaml': 'name: r\nworkspace:\n  - app\n',
    [ROUTER]: 'class AppRouter {}\n',
    // A second project below would be found by a scan; it must not be, because
    // the folder itself already answered.
    [`apps/other/pubspec.yaml`]: 'name: o\nworkspace:\n  - app\n',
    [`apps/other/${ROUTER}`]: 'class AppRouter {}\n',
  });
  open(root);
  assert.deepStrictEqual(paths.findProjectRoots(), [root]);
});

test('a project is not descended into', () => {
  // Its member packages are packages. One of them holding a router would make
  // the app claim to contain itself.
  const root = tree({
    ...NESTED,
    'apps/tm_console/app/pubspec.yaml': 'name: app\nworkspace:\n  - x\n',
    [`apps/tm_console/app/${ROUTER}`]: 'class AppRouter {}\n',
  });
  open(root);
  assert.deepStrictEqual(paths.findProjectRoots(), [path.join(root, 'apps/tm_console')]);
});

test('projectRootFor maps a folder above the project onto it', () => {
  // This is the palette's path: no clicked folder, so it falls back to the
  // workspace folder — which `--root` can only answer "not inside" about,
  // because the CLI walks up and never down.
  const root = tree(NESTED);
  open(root);
  assert.strictEqual(paths.projectRootFor(root), path.join(root, 'apps/tm_console'));
});

test('projectRootFor maps a folder inside the project onto it', () => {
  const root = tree(NESTED);
  open(root);
  assert.strictEqual(
    paths.projectRootFor(path.join(root, 'apps/tm_console/app/lib')),
    path.join(root, 'apps/tm_console'),
  );
});

test('projectRootFor refuses to guess between two projects', () => {
  // A scaffolder writing into the wrong app is not something to guess at.
  const root = tree({
    'pubspec.yaml': 'name: outer\nworkspace:\n  - packages/core\n',
    'apps/one/pubspec.yaml': 'name: a\nworkspace:\n  - app\n',
    [`apps/one/${ROUTER}`]: 'class AppRouter {}\n',
    'apps/two/pubspec.yaml': 'name: b\nworkspace:\n  - app\n',
    [`apps/two/${ROUTER}`]: 'class AppRouter {}\n',
  });
  open(root);
  assert.strictEqual(paths.findProjectRoots().length, 2);
  assert.strictEqual(paths.projectRootFor(root), null);
  // Named explicitly, it resolves.
  assert.strictEqual(
    paths.projectRootFor(path.join(root, 'apps/two')),
    path.join(root, 'apps/two'),
  );
});

test('a project deeper than the scan bound is not found', () => {
  // Stated rather than left to chance: past three levels the scan costs more
  // than the case it serves, and the failure should be a known edge, not a
  // mystery.
  const root = tree({
    'pubspec.yaml': 'name: outer\nworkspace:\n  - x\n',
    'a/b/c/d/pubspec.yaml': 'name: deep\nworkspace:\n  - app\n',
    [`a/b/c/d/${ROUTER}`]: 'class AppRouter {}\n',
  });
  open(root);
  assert.deepStrictEqual(paths.findProjectRoots(), []);
});

// --- one answer per window ---------------------------------------------------
//
// Six call sites ask `findWorkspaceRoot()` independently. It used to resolve
// through `activeTextEditor`, so with two projects open they could disagree at
// the same moment — the watch regenerating one while the Problems panel audited
// another — and the answer changed under you as you moved between tabs.

const TWO = {
  'pubspec.yaml': 'name: outer\nworkspace:\n  - packages/core\n',
  'apps/zulu/pubspec.yaml': 'name: z\nworkspace:\n  - app\n',
  [`apps/zulu/${ROUTER}`]: 'class AppRouter {}\n',
  'apps/alpha/pubspec.yaml': 'name: a\nworkspace:\n  - app\n',
  [`apps/alpha/${ROUTER}`]: 'class AppRouter {}\n',
};

test('the answer does not change when the focused file does', () => {
  const root = tree(TWO);
  open(root);
  const first = paths.findWorkspaceRoot();
  // Focusing a file in the other project must not move the tree, the watch and
  // the audit apart from each other.
  (vscode as any).window = {
    activeTextEditor: { document: { uri: { fsPath: path.join(root, 'apps/zulu/app/lib/x.dart') } } },
  };
  assert.strictEqual(paths.findWorkspaceRoot(), first);
});

test('which project wins is a decision, not readdir order', () => {
  const root = tree(TWO);
  open(root);
  assert.deepStrictEqual(paths.findProjectRoots(), [
    path.join(root, 'apps/alpha'),
    path.join(root, 'apps/zulu'),
  ]);
});

test('changing the workspace folders changes the answer', () => {
  const one = tree({
    'pubspec.yaml': 'name: r\nworkspace:\n  - app\n',
    [ROUTER]: 'class AppRouter {}\n',
  });
  open(one);
  assert.strictEqual(paths.findWorkspaceRoot(), one);

  const two = tree({
    'pubspec.yaml': 'name: r2\nworkspace:\n  - app\n',
    [ROUTER]: 'class AppRouter {}\n',
  });
  open(two); // `open` forgets, the way the folder-change handler does
  assert.strictEqual(paths.findWorkspaceRoot(), two);
});
