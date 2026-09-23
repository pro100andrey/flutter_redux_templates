// Which project a command acts on.
//
// Commands used to fall back to the first workspace folder while the tree, the
// audit and the watch scanned every folder — so with `[other, mono]` open the
// tree showed `mono` and every command said "no frx project here".
import './helpers';
import { vscode } from './helpers';
import { test, afterEach } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import paths = require('../src/paths');
import ui = require('../src/ui');

function project(): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'frx_target_'));
  fs.writeFileSync(path.join(root, 'pubspec.yaml'), 'name: r\nworkspace:\n  - app\n');
  const router = path.join(root, 'app', 'lib', 'navigation', 'app_router.dart');
  fs.mkdirSync(path.dirname(router), { recursive: true });
  fs.writeFileSync(router, 'class AppRouter {}\n');
  return root;
}

function plain(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'frx_other_'));
}

function open(...folders: string[]): void {
  vscode.workspace.workspaceFolders = folders.map((f) => ({ uri: { fsPath: f } }));
  paths.forgetWorkspaceRoot();
}

function editing(file: string | undefined): void {
  vscode.window.activeTextEditor = file
    ? { document: { uri: { scheme: 'file', fsPath: file } } }
    : undefined;
}

afterEach(() => editing(undefined));

test('a project that is not the first folder is still the one commands act on', () => {
  const mono = project();
  open(plain(), mono);

  assert.strictEqual(ui.commandProject(undefined), mono);
  assert.strictEqual(ui.commandProject(undefined), paths.findWorkspaceRoot(), 'the same one the tree shows');
});

test('with two projects open, the active editor decides', () => {
  const a = project();
  const b = project();
  open(a, b);
  editing(path.join(b, 'app', 'lib', 'navigation', 'app_router.dart'));

  assert.strictEqual(ui.commandProject(undefined), b);
});

test('with two projects and no editor in either, the window\'s project', () => {
  const a = project();
  const b = project();
  open(a, b);
  editing(path.join(os.tmpdir(), 'scratch.dart'));

  assert.strictEqual(ui.commandProject(undefined), paths.findWorkspaceRoot());
});

test('no project anywhere is null, and resolveTarget says so', async () => {
  open(plain());
  const errors: string[] = [];
  vscode.window.showErrorMessage = async (m: string) => void errors.push(m);

  assert.strictEqual(ui.commandProject(undefined), null);
  assert.strictEqual(await ui.resolveTarget({} as any, undefined), null);
  assert.match(errors[0] ?? '', /no frx project here/);
});
