#!/usr/bin/env node
// CI gate for the extension manifest: every command package.json contributes
// must be registered somewhere in the source, and every menu entry must
// reference a declared command. Catches the classic drift where a command is
// renamed in one place only. Run from tools/vscode: `node validate-manifest.js`.
import * as fs from 'fs';
import * as path from 'path';

const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));

/**
 * Every TypeScript source under the extension, excluding this file. Scans the
 * `.ts` sources rather than the compiled `out/`: the check is about what is
 * written, and a stale build would otherwise pass (or fail) for the wrong
 * reason.
 */
function collectSources(dir: string): string[] {
  const out: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    // Skip deps, build output, dotfiles, and tests — only real source registers
    // commands, and a command named only in a test must not read as "registered".
    if (['node_modules', 'out', 'test'].includes(entry.name) || entry.name.startsWith('.')) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...collectSources(full));
    else if (entry.name.endsWith('.ts') && entry.name !== 'validate-manifest.ts') out.push(full);
  }
  return out;
}

const source = collectSources('.')
  .map((f) => fs.readFileSync(f, 'utf8'))
  .join('\n');

const declared: string[] = pkg.contributes.commands.map((c: { command: string }) => c.command);

const unregistered = declared.filter(
  (c: string) => !source.includes(`'${c}'`) && !source.includes(`"${c}"`),
);
if (unregistered.length) {
  console.error(`✗ commands declared but never registered: ${unregistered.join(', ')}`);
  process.exit(1);
}

/**
 * Every `frx.*` command id the source *invokes*, with the file that names it.
 *
 * Read from command positions rather than from every `frx.…` string: the sources
 * also carry context keys (`frx.isMonorepo`), a setting (`frx.path`), a view id
 * (`frx.tree`) and two filenames (`frx.dart`, `frx.exe`), none of which is a
 * command. The three positions that are: registering one, executing one, and the
 * `command:` property of a lens, a tree item or a menu action.
 *
 * This is the direction the other checks do not cover. They ask whether a
 * *declared* command is registered and surfaced; nothing asked whether an id the
 * source invokes still exists — and a code lens is reached by neither the
 * manifest nor the registration, so a rename left it naming a command that was
 * gone, and only a user clicking it found out.
 */
function invokedCommands(files: string[]): Map<string, string> {
  const found = new Map<string, string>();
  const re = /(?:registerCommand|executeCommand)\(\s*['"]([\w.]+)['"]|command:\s*['"]([\w.]+)['"]/g;
  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    for (const m of text.matchAll(re)) {
      const id = m[1] ?? m[2];
      // The editor owns its own commands; only ours are ours to declare.
      if (id.startsWith('frx.') && !found.has(id)) found.set(id, file);
    }
  }
  return found;
}

const invoked = invokedCommands(collectSources('.'));
const undeclaredInvocations = [...invoked].filter(([id]) => !declared.includes(id));
if (undeclaredInvocations.length) {
  for (const [id, file] of undeclaredInvocations) {
    console.error(`✗ ${file} invokes '${id}', which the manifest does not declare`);
  }
  process.exit(1);
}

const menuRefs: string[] = Object.values(pkg.contributes.menus ?? {})
  .flat()
  .map((m) => (m as { command: string }).command);
const undeclared = menuRefs.filter((c: string) => !declared.includes(c));
if (undeclared.length) {
  console.error(`✗ menus reference undeclared commands: ${undeclared.join(', ')}`);
  process.exit(1);
}

const keyRefs: string[] = (pkg.contributes.keybindings ?? []).map((k: { command: string }) => k.command);
const unknownKeys = keyRefs.filter((c: string) => !declared.includes(c));
if (unknownKeys.length) {
  console.error(`✗ keybindings reference undeclared commands: ${unknownKeys.join(', ')}`);
  process.exit(1);
}

const viewIds: string[] = Object.values(pkg.contributes.views ?? {})
  .flat()
  .map((v) => (v as { id: string }).id);
const unknownViews = viewIds.filter((id: string) => !source.includes(`'${id}'`) && !source.includes(`"${id}"`));
if (unknownViews.length) {
  console.error(`✗ views contributed but never created in source: ${unknownViews.join(', ')}`);
  process.exit(1);
}

console.log(
  `✓ manifest ok — ${declared.length} commands, ${menuRefs.length} menu refs, ` +
    `${invoked.size} invoked, ${viewIds.length} view(s), v${pkg.version}`,
);
