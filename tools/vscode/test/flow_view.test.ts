import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { buildMarkdown } from '../src/flow_view';

/** The extension root — __dirname is out/test once compiled. */
const ROOT = path.join(__dirname, '..', '..');

test('buildMarkdown: fences the diagram as mermaid under a heading', () => {
  const md = buildMarkdown('sequenceDiagram\n  A->>B: hi', 'logIn — use cases');
  assert.match(md, /^# logIn — use cases\n/);
  assert.match(md, /```mermaid\nsequenceDiagram\n {2}A->>B: hi\n```/);
});

test('buildMarkdown: renders a flowchart as readily as a sequence diagram', () => {
  assert.match(buildMarkdown('flowchart LR\n  a --> b', 'Navigation map'), /```mermaid\nflowchart LR/);
});

test('buildMarkdown: a diagram cannot close its own fence', () => {
  // A label carrying a fence would otherwise end the block early and spill the
  // rest of the diagram into the page as prose.
  const nasty = 'flowchart LR\n  a["```"] --> b';
  const md = buildMarkdown(nasty, 'x');
  const open = md.match(/^(`{3,})mermaid$/m);
  assert.ok(open, 'has an opening fence');
  assert.ok(open[1].length > 3, 'the fence outgrew the content');
  // Exactly two fences that long: the opener and the closer.
  const fences = md.match(new RegExp(`^${open[1]}`, 'gm')) ?? [];
  assert.strictEqual(fences.length, 2, 'the block is closed exactly once');
  assert.ok(md.includes(nasty), 'the diagram survives intact');
});

test("nothing is vendored — mermaid is the platform's", () => {
  // This used to assert that `media/` did not exist at all, which was a proxy
  // for the claim and stopped being one the moment the extension needed a
  // marketplace icon. The claim itself is that no *library* is shipped: the
  // preview renders mermaid because VSCode 1.121 renders mermaid, and a vendored
  // copy would be a second renderer to keep in step with the first.
  const media = path.join(ROOT, 'media');
  const strays = fs.existsSync(media)
    ? fs.readdirSync(media).filter((f) => !/\.(png|svg|jpg|gif)$/i.test(f))
    : [];
  assert.deepStrictEqual(strays, [], 'media/ holds artwork only, no code');

  const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
  // 1.121 is the release that merged `mermaid-markdown-features` in; below it
  // the preview shows our diagram as a plain code block, so this floor is
  // load-bearing rather than incidental.
  assert.strictEqual(pkg.engines.vscode, '^1.121.0');
});

test('the view-switching buttons live in the preview toolbar', () => {
  const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
  const titles = pkg.contributes.menus['editor/title'] ?? [];
  for (const command of ['frx.flow', 'frx.routes']) {
    const entry = titles.find(
      (e: { command: string; when?: string }) =>
        e.command === command && e.when?.includes("activeWebviewPanelId == 'markdown.preview'"),
    );
    assert.ok(entry, `${command} is contributed to the preview's toolbar`);
  }
});

test('the scratch document is named for what it holds, not for one of two views', () => {
  // The markdown preview titles its tab from the file name, and this one file
  // holds either view — a name like `frx-flow` put the navigation map under a
  // tab labelled *flow*.
  const src = fs.readFileSync(path.join(ROOT, 'src', 'flow_view.ts'), 'utf8');
  const scratch = src.match(/const SCRATCH = '([^']+)'/)?.[1];
  assert.ok(scratch, 'the scratch name is declared');
  assert.doesNotMatch(scratch, /flow|route|nav/i, `"${scratch}" names one view`);
});

test('the scratch document goes to workspace storage, not the shared one', () => {
  const { scratchDir } = require('../src/flow_view');
  const workspace = { fsPath: '/ws' };
  const global = { fsPath: '/global' };
  // Global storage is one directory for every window: a second monorepo would
  // render into the same file, and the preview watching it live-updates.
  assert.strictEqual(scratchDir({ storageUri: workspace, globalStorageUri: global }), workspace);
  assert.strictEqual(scratchDir({ storageUri: undefined, globalStorageUri: global }), global);
});
