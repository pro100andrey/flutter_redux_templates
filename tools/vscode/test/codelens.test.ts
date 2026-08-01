import './helpers';
import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { FrxLensProvider } from '../src/codelens';

/* eslint-disable @typescript-eslint/no-explicit-any */

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

test('a file of no interest gets no lenses', () => {
  assert.deepStrictEqual(
    new FrxLensProvider('/repo').provideCodeLenses(doc('/repo/ui/lib/widgets/button.dart', '')),
    [],
  );
});
