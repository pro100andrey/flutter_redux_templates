import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { FrxLensProvider } from '../src/codelens';

/// The lenses on the monorepo's conventional files.
///
/// A lens is the one entry point neither the manifest nor the command
/// registration mentions, so a renamed command left it firing an id that was
/// gone — `command 'frx.tree.addAction' not found`, on click, with nothing
/// upstream to notice. So what is pinned here is not the wording of a title but
/// the property that broke: **every command a lens fires is declared**.

/** The extension root — __dirname is out/test once compiled. */
const ROOT = path.join(__dirname, '..', '..');

/** Command ids the manifest declares. */
const DECLARED: string[] = JSON.parse(
  fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'),
).contributes.commands.map((c: { command: string }) => c.command);

/** A document at `file` holding `text`. */
function doc(file: string, text: string): any {
  return {
    uri: { fsPath: file },
    getText: () => text,
    positionAt: () => new (require('vscode').Position)(0, 0),
  };
}

/**
 * A repo on disk holding `files`, for the jump lenses — they are shown only
 * when the counterpart exists, so a path that is not there is no test of them.
 */
function repoWith(files: Record<string, string>): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'frx_lens_'));
  for (const [rel, body] of Object.entries(files)) {
    const file = path.join(root, ...rel.split('/'));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, body);
  }
  return root;
}

const STATE_FILE = '/repo/business/lib/redux/log_in/models/log_in_state.dart';
const STATE_SRC = '@freezed\nclass LogInState with _$LogInState {}\n';

test('the state-file lenses fire commands that exist', () => {
  // The regression this file exists for: `frx.tree.addAction` was renamed to
  // `frx.addAction` and the lens kept the old id.
  const lenses = new FrxLensProvider('/repo').provideCodeLenses(doc(STATE_FILE, STATE_SRC));
  assert.strictEqual(lenses.length, 2);
  for (const lens of lenses) {
    const id = lens.command!.command;
    assert.ok(
      DECLARED.includes(id),
      `the lens "${lens.command!.title}" fires '${id}', which package.json does not declare`,
    );
  }
});

test('the state-file lenses pre-fill the substate they sit on', () => {
  const lenses = new FrxLensProvider('/repo').provideCodeLenses(doc(STATE_FILE, STATE_SRC));
  assert.deepStrictEqual(
    lenses.map((l) => [l.command!.command, (l.command!.arguments as any)[0]]),
    [
      ['frx.addAction', { frxName: 'logIn' }],
      ['frx.addField', { frxName: 'logIn' }],
    ],
    'the snake folder name becomes the camel field the commands take',
  );
});

test('a connector fires the flow diagram, and it exists too', () => {
  const lenses = new FrxLensProvider('/repo').provideCodeLenses(
    doc('/repo/app/lib/connectors/log_in_page_connector.dart', 'class LogInPageConnector {}'),
  );
  // The counterpart page is absent here, so only the Flow lens comes back.
  const ours = lenses.filter((l) => l.command!.command.startsWith('frx.'));
  assert.deepStrictEqual(
    ours.map((l) => l.command!.command),
    ['frx.flow'],
  );
  for (const lens of ours) assert.ok(DECLARED.includes(lens.command!.command));
});

test('a widget connector opens the widget its import names', () => {
  // Which widget a connector wraps is stated in its imports and nowhere else:
  // the widget may live in any folder of the ui package, and its file may carry
  // a kind suffix the connector's stem does not.
  const src = [
    "import 'package:ui/console/actor_dialog.dart';",
    "import 'package:ui/console/status_bar.dart';",
    'class StatusBarConnector {}',
  ].join('\n');
  const root = repoWith({
    'ui/lib/console/actor_dialog.dart': '',
    'ui/lib/console/status_bar.dart': '',
    'app/lib/connectors/status_bar_connector.dart': src,
  });
  const lenses = new FrxLensProvider(root).provideCodeLenses(
    doc(path.join(root, 'app', 'lib', 'connectors', 'status_bar_connector.dart'), src),
  );
  assert.deepStrictEqual(
    lenses.map((l) => [l.command!.title, (l.command!.arguments as any)[0].fsPath]),
    [['$(go-to-file) Open widget', path.join(root, 'ui', 'lib', 'console', 'status_bar.dart')]],
    'the import whose basename is the stem, not the dialog beside it',
  );
});

test('a widget file opens the connector named for it', () => {
  const root = repoWith({
    'ui/lib/console/status_bar.dart': 'class StatusBar {}',
    'app/lib/connectors/status_bar_connector.dart': '',
  });
  const lenses = new FrxLensProvider(root).provideCodeLenses(
    doc(path.join(root, 'ui', 'lib', 'console', 'status_bar.dart'), 'class StatusBar {}'),
  );
  assert.deepStrictEqual(
    lenses.map((l) => [l.command!.title, (l.command!.arguments as any)[0].fsPath]),
    [['$(go-to-file) Open connector', path.join(root, 'app', 'lib', 'connectors', 'status_bar_connector.dart')]],
    'in any folder of the ui package, not only widgets/',
  );
});

test('a widget connector with one ui import opens that, whatever it is called', () => {
  // `add-widget -k field` writes `pin_form_field.dart` for a stem of `pin`.
  const src = "import 'package:ui/inputs/pin_form_field.dart';\nclass PinConnector {}";
  const root = repoWith({ 'ui/lib/inputs/pin_form_field.dart': '' });
  const lenses = new FrxLensProvider(root).provideCodeLenses(
    doc(path.join(root, 'app', 'lib', 'connectors', 'pin_connector.dart'), src),
  );
  assert.deepStrictEqual(
    lenses.map((l) => (l.command!.arguments as any)[0].fsPath),
    [path.join(root, 'ui', 'lib', 'inputs', 'pin_form_field.dart')],
  );
});

test('a widget connector whose widget cannot be told is shown no lens', () => {
  // Two ui imports, neither named for the stem: a guess, and a wrong jump is
  // worse than none.
  const src = [
    "import 'package:ui/console/a.dart';",
    "import 'package:ui/console/b.dart';",
    'class ThingConnector {}',
  ].join('\n');
  assert.deepStrictEqual(
    new FrxLensProvider('/repo').provideCodeLenses(doc('/repo/app/lib/connectors/thing_connector.dart', src)),
    [],
  );
});

test('a page connector is not mistaken for a widget connector', () => {
  // `_page_connector.dart` ends in `_connector.dart` too; the page rule must win.
  const src = "import 'package:ui/pages/log_in_page.dart';\nclass LogInPageConnector {}";
  const lenses = new FrxLensProvider('/repo').provideCodeLenses(
    doc('/repo/app/lib/connectors/log_in_page_connector.dart', src),
  );
  assert.ok(!lenses.some((l) => l.command!.title.includes('Open widget')));
});

test('a file of no interest gets no lenses', () => {
  assert.deepStrictEqual(
    new FrxLensProvider('/repo').provideCodeLenses(doc('/repo/ui/lib/widgets/button.dart', '')),
    [],
  );
});
