// Locating the monorepo root and the package a file belongs to — the two
// filesystem walks the extension needs to answer "is this our structure?"
// (gates the watch/tree/diagnostics) and "which package do I run build_runner
// in?". Split out of the CLI adapter because these are workspace/path concerns,
// not frx-invocation ones.
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

import { MARKER_PATH } from './generated/contract';

/**
 * The file `frx` itself keys on to decide where the monorepo begins.
 *
 * Generated from `FrxWorkspace.marker`, not kept identical to it by hand. The
 * two used to answer "is this our structure?" differently, and the extension's
 * answer was the looser one; a copy that has already drifted once is not one to
 * keep by convention.
 */
const MARKER = path.join(...MARKER_PATH.split('/'));

/**
 * How far below a workspace folder a project is looked for.
 *
 * Three covers the layouts a template gets unpacked into — `apps/<name>`,
 * `packages/<name>`, `examples/<name>`, and one more level for a repo that
 * groups those again. Deeper than that and the scan starts costing more than the
 * case it serves.
 */
const MAX_DEPTH = 3;

/**
 * Directories never worth descending into: build output, platform shells, and
 * dependency trees. All are large, none can contain a project of ours — a
 * generated `build/` or an `ios/` folder has no pubspec with `workspace:`.
 */
const SKIP = new Set([
  'build',
  'node_modules',
  'ios',
  'android',
  'macos',
  'windows',
  'linux',
  'web',
]);

/**
 * Whether [dir] is itself a project of ours: both a pub workspace and laid out
 * the way frx writes.
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
export function isProjectRoot(dir: string): boolean {
  try {
    if (!/^workspace:/m.test(fs.readFileSync(path.join(dir, 'pubspec.yaml'), 'utf8'))) {
      return false;
    }
  } catch {
    return false; /* no pubspec in this folder */
  }
  return fs.existsSync(path.join(dir, MARKER));
}

/**
 * Every project of ours reachable from the open workspace folders, outermost
 * first.
 *
 * The folder itself is tested before anything is scanned, so the ordinary case —
 * the project *is* what you opened — costs one `readFile` and one `existsSync`,
 * exactly as it did before this searched at all.
 *
 * Searching below the folder is the point. A template unpacked into somebody
 * else's repository does not land at its root: `bloom/` is a pub workspace whose
 * own root has no router, and the app sits in `apps/tm_console`. Testing only the
 * workspace folders left `frx.isMonorepo` false there, which is not a degraded
 * experience but no extension at all — no tree, no watch, no audit, and every
 * menu entry silently absent, with nothing on screen to say why.
 *
 * A found project is not descended into. Its member packages are packages, not
 * projects, and one of them holding a router would make the app claim to contain
 * itself.
 */
export function findProjectRoots(): string[] {
  const found: string[] = [];
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    scan(folder.uri.fsPath, 0, found);
  }
  // Outermost first, then by name — because something has to be first and
  // `readdirSync` order is the filesystem's, not a decision. The doc above
  // promises "outermost"; without this it promised whatever the directory
  // happened to enumerate, which differs between machines and after a rename.
  return found.sort((a, b) => {
    const depth = a.split(path.sep).length - b.split(path.sep).length;
    return depth !== 0 ? depth : a.localeCompare(b);
  });
}

function scan(dir: string, depth: number, into: string[]): void {
  if (isProjectRoot(dir)) {
    into.push(dir);
    return;
  }
  if (depth >= MAX_DEPTH) return;
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return; /* unreadable — a permission or a race, not our business */
  }
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    // Dotted folders are `.git`, `.dart_tool`, `.symlinks` — never a project,
    // always big.
    if (entry.name.startsWith('.') || SKIP.has(entry.name)) continue;
    scan(path.join(dir, entry.name), depth + 1, into);
  }
}

/**
 * The project this window is working in — what the tree, the watch, the audit
 * and the code lenses are all about. Null when the workspace holds none.
 *
 * **One answer per window, resolved once.** Six call sites ask this
 * independently (`extension.ts`, `tree.ts`, `doctor.ts`, `watch.ts`, `map.ts`,
 * `flow_view.ts`), and it used to resolve through `activeTextEditor` — so with
 * two projects open they could disagree *at the same moment*: the watch
 * regenerating one while the Problems panel audited another and the tree showed
 * a third state, changing under you as you moved between files. A view that
 * answers a different question depending on which tab has focus is worse than
 * one that answers a fixed question, because nothing on screen says which.
 *
 * So it is cached. The cost is that with several projects open, one of them is
 * simply not served — no tree, no audit — and there is no way to switch. That is
 * a missing feature, and a visible one; the alternative was a silent
 * inconsistency. A project picker is the follow-up, and this is the seam it
 * would set.
 */
let _active: string | null | undefined;

export function findWorkspaceRoot(): string | null {
  if (_active !== undefined) return _active;
  return (_active = findProjectRoots()[0] ?? null);
}

/**
 * Forget the cached answer — the workspace folders changed, so the question is
 * genuinely different now.
 */
export function forgetWorkspaceRoot(): void {
  _active = undefined;
}

/**
 * The project [fromPath] belongs to — what a command should pass as `--root`.
 *
 * Walks up first, mirroring `FrxWorkspace.locate` on the CLI side, so a path
 * anywhere inside a project resolves to it. A path *above* one resolves to it
 * too when there is exactly one below, which is the case that made this
 * necessary: the palette passes the workspace folder, and in `bloom/` that is a
 * directory the CLI can only answer "not inside a frx project" about. With
 * several below it stays null rather than picking — a scaffolder writing into
 * the wrong app is not something to guess at.
 */
export function projectRootFor(fromPath: string): string | null {
  let dir = fs.existsSync(fromPath) && fs.statSync(fromPath).isDirectory()
    ? fromPath
    : path.dirname(fromPath);
  while (true) {
    if (isProjectRoot(dir)) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }

  const below = findProjectRoots().filter((root) => contains(fromPath, root));
  return below.length === 1 ? below[0] : null;
}

/** Whether [inner] is [outer] or sits underneath it. */
function contains(outer: string, inner: string): boolean {
  const rel = path.relative(outer, inner);
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
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
