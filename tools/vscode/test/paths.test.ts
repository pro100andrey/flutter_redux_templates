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
  assert.strictEqual(paths.findWorkspaceRoot(), null);
});
