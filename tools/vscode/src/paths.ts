// Locating the monorepo root and the package a file belongs to — the two
// filesystem walks the extension needs to answer "is this our structure?"
// (gates the watch/tree/diagnostics) and "which package do I run build_runner
// in?". Split out of the CLI adapter because these are workspace/path concerns,
// not frx-invocation ones.
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

/**
 * The file `frx` itself keys on to decide where the monorepo begins.
 *
 * Kept identical to `FrxWorkspace._marker` on the CLI side on purpose: the two
 * used to answer "is this our structure?" differently, and the extension's
 * answer was the looser one.
 */
const MARKER = path.join('app', 'lib', 'navigation', 'app_router.dart');

/**
 * The monorepo root: a workspace folder that is both a pub workspace and laid
 * out the way frx writes. Doubles as the "is this our structure?" test (gates
 * the watch, the tree and the doctor chip) and the cwd for
 * `build_runner --workspace`. Returns null if none.
 *
 * **Both tests, and the second is why.** `workspace:` in a pubspec means "this
 * is a pub workspace" — an ordinary Dart 3.6 feature that any monorepo may use
 * and that says nothing about this template. On that alone the extension woke up
 * in unrelated projects: a tree with nothing in it, a watch toggle for a build
 * that is not ours, and a doctor chip parked on `? doctor` forever, because
 * every audit exits 70 with no JSON to read. The marker is what `frx` keys on,
 * so both sides now agree about what they are looking at.
 *
 * The pub-workspace test stays because it is the one the *build* needs:
 * `build_runner --workspace` is only valid in a workspace root.
 */
export function findWorkspaceRoot(): string | null {
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    const root = folder.uri.fsPath;
    try {
      if (!/^workspace:/m.test(fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8'))) {
        continue;
      }
    } catch {
      continue; /* no pubspec in this folder */
    }
    if (fs.existsSync(path.join(root, MARKER))) return root;
  }
  return null;
}

/** Nearest ancestor of `fromPath` containing a pubspec.yaml (the package root). */
export function findPackageRoot(fromPath: string): string | null {
  let dir = fs.existsSync(fromPath) && fs.statSync(fromPath).isDirectory() ? fromPath : path.dirname(fromPath);
  while (true) {
    if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}
