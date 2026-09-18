// CodeLens for the monorepo's conventional files — actions right where you
// read the code:
//   • `redux/<sub>/models/<sub>_state.dart`  → "⚡ Add action…" above the class
//   • `app/lib/connectors/<x>_page_connector.dart` → "Open page" · "Flow"
//   • `app/lib/connectors/<x>_connector.dart` → "Open widget"
//   • `ui/lib/pages/<x>_page.dart`           → "Open connector"
//   • `ui/lib/**/<x>.dart`                   → "Open connector", when one exists
// Pure path/regex derivation — no CLI calls, so lenses are instant. The one
// read beyond the path is the widget connector's own imports: which widget it
// wraps is stated there and nowhere else, since `add-widget -k field` puts
// `Pin` in `pin_form_field.dart` and `list-widget-dirs` puts it in any folder.
//
// **The layout comes from `LAYOUT`, not from here.** Those three shapes were
// spelled out in four regexes and two `path.join`s, which is the same copy of
// the CLI's contract that `--kind` used to be — and the quietest one: a
// directory renamed in Dart does not break this file, it just stops the lens
// appearing, on a provider nobody thinks to test after moving a folder.
//
// Unconditional. The setting that used to gate them added only the granularity of
// hiding frx's lenses while keeping Dart's — the editor's own global lens setting
// already hides every provider's — and nobody asked for it. That granularity is a
// real capability being dropped, deliberately.
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

import { LAYOUT } from './generated/contract';
import * as naming from './naming';

/** Escapes a LAYOUT literal so it can be embedded in a RegExp source. */
function escaped(literal: string): string {
  return literal.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** A `LAYOUT` directory as a platform path under `root`. */
function dirOf(root: string, slashed: string): string {
  return path.join(root, ...slashed.split('/'));
}

/** The last segment of a `LAYOUT` directory, for matching a path tail. */
function leafOf(slashed: string): string {
  return slashed.slice(slashed.lastIndexOf('/') + 1);
}

/** The Range of the first line `pattern` matches in `text`, or line 0 as a fallback. */
function classRange(document: vscode.TextDocument, text: string, pattern: RegExp): vscode.Range {
  const m = pattern.exec(text);
  const pos = m ? document.positionAt(m.index) : new vscode.Position(0, 0);
  return new vscode.Range(pos, pos);
}

/** `^class <name>` (or `abstract class`), for `classRange`. */
function classPattern(namePattern: string): RegExp {
  return new RegExp(`^(?:abstract\\s+)?class\\s+${namePattern}`, 'm');
}

/** Any state class — the one pattern that does not depend on the file. */
const STATE_CLASS = classPattern('\\w+State');

export class FrxLensProvider implements vscode.CodeLensProvider {
  // The path shapes, compiled once. `provideCodeLenses` runs on every edit of
  // every Dart document, and it used to rebuild these from `LAYOUT` on each
  // call — the same five RegExps and the same joined paths, for a file whose
  // shape was decided when the root was.
  private readonly _state: RegExp;
  private readonly _connector: RegExp;
  private readonly _widgetConnector: RegExp;
  private readonly _page: RegExp;
  private readonly _uiDir: string;
  private readonly _pagesDir: string;
  private readonly _connectorsDir: string;

  /** @param root the monorepo root */
  constructor(private readonly root: string) {
    const sep = path.sep;
    this._state = new RegExp(
      `\\${sep}${leafOf(LAYOUT.redux)}\\${sep}([a-z0-9_]+)\\${sep}models\\${sep}\\1${escaped(LAYOUT.stateSuffix)}$`,
    );
    this._connector = new RegExp(
      `\\${sep}${leafOf(LAYOUT.connectors)}\\${sep}(\\w+)${escaped(LAYOUT.connectorSuffix)}$`,
    );
    this._widgetConnector = new RegExp(
      `\\${sep}${leafOf(LAYOUT.connectors)}\\${sep}(\\w+)${escaped(LAYOUT.widgetConnectorSuffix)}$`,
    );
    this._page = new RegExp(
      `\\${sep}${leafOf(LAYOUT.pages)}\\${sep}(\\w+)${escaped(LAYOUT.pageSuffix)}$`,
    );
    this._uiDir = dirOf(root, LAYOUT.ui) + sep;
    this._pagesDir = dirOf(root, LAYOUT.pages);
    this._connectorsDir = dirOf(root, LAYOUT.connectors);
  }

  provideCodeLenses(document: vscode.TextDocument): vscode.CodeLens[] {
    const file = document.uri.fsPath;
    // The text, read once and only on a branch that needs it: `getText()` is
    // a copy of the whole document, and a page connector used to take three —
    // one per lens, and one more for its imports.
    let text: string | undefined;
    const textOf = () => (text ??= document.getText());

    // Substate state model → Add action… (pre-filled with the substate).
    const state = file.match(this._state);
    if (state) {
      const field = naming.camelOf(state[1]);
      const range = classRange(document, textOf(), STATE_CLASS);
      return [
        new vscode.CodeLens(range, {
          title: '$(zap) Add action…',
          command: 'frx.addAction',
          arguments: [{ frxName: field }],
        }),
        new vscode.CodeLens(range, {
          title: '$(add) Add field…',
          command: 'frx.addField',
          arguments: [{ frxName: field }],
        }),
      ];
    }

    // Page connector → its dumb page, plus a diagram of what it dispatches.
    const connector = file.match(this._connector);
    if (connector) {
      const className = `${naming.pascalOf(connector[1])}PageConnector`;
      const page = path.join(this._pagesDir, `${connector[1]}${LAYOUT.pageSuffix}`);
      const range = classRange(document, textOf(), classPattern(className));
      return [
        ...this._openLens(() => range, page, 'Open page'),
        new vscode.CodeLens(range, {
          title: '$(git-merge) Flow',
          command: 'frx.flow',
          arguments: [{ frxName: connector[1] }],
        }),
      ];
    }
    // Widget connector → the widget it wraps. No Flow: `frx flow` walks a page.
    // Tested after the page connector, whose suffix this one is a tail of.
    const widgetConnector = file.match(this._widgetConnector);
    if (widgetConnector) {
      const widget = this._widgetOf(textOf(), widgetConnector[1]);
      if (!widget) return [];
      const className = `${naming.pascalOf(widgetConnector[1])}Connector`;
      return this._openLens(
        () => classRange(document, textOf(), classPattern(className)),
        widget,
        'Open widget',
      );
    }
    const page = file.match(this._page);
    if (page) {
      const conn = path.join(this._connectorsDir, `${page[1]}${LAYOUT.connectorSuffix}`);
      return this._openLens(
        () => classRange(document, textOf(), classPattern(`${naming.pascalOf(page[1])}Page`)),
        conn,
        'Open connector',
      );
    }
    // Any other file of the ui package → its connector, when one is named for
    // it. The reverse of "Open widget", by path alone: `<stem>_connector.dart`
    // is what `add-connector` writes, so a widget whose class carries a kind
    // suffix (`PinFormField` for `pin`) gets no lens here — the connector's own
    // import is the only place that pairing is stated, and this file is not it.
    if (file.startsWith(this._uiDir) && file.endsWith('.dart')) {
      const stem = path.basename(file, '.dart');
      const conn = path.join(this._connectorsDir, `${stem}${LAYOUT.widgetConnectorSuffix}`);
      return this._openLens(
        () => classRange(document, textOf(), classPattern(naming.pascalOf(stem))),
        conn,
        'Open connector',
      );
    }

    return [];
  }

  /**
   * The ui file a widget connector wraps, read off its imports — or null.
   *
   * The import whose basename is the connector's stem, when there is one:
   * `status_bar_connector.dart` imports `package:ui/console/status_bar.dart`
   * beside a dialog it also uses. Failing that, the only `package:ui/` import,
   * if there is only one — a `-k field` connector imports
   * `pin_form_field.dart` for a stem of `pin`. Two or more and none matching is
   * a guess, and the lens is not shown rather than shown wrong.
   */
  private _widgetOf(text: string, stem: string): string | null {
    const imports = [...text.matchAll(/^import\s+'package:ui\/([^']+\.dart)'/gm)].map((m) => m[1]);
    const named = imports.find((p) => p.endsWith(`/${stem}.dart`) || p === `${stem}.dart`);
    const chosen = named ?? (imports.length === 1 ? imports[0] : undefined);
    if (!chosen) return null;
    return path.join(dirOf(this.root, LAYOUT.ui), ...chosen.split('/'));
  }

  /**
   * A "jump to counterpart" lens, only when the counterpart exists.
   *
   * The range is asked for after the check, not before: most files of the ui
   * package have no connector, and the class search over the document is only
   * worth running for the ones that do.
   */
  private _openLens(rangeOf: () => vscode.Range, target: string, title: string): vscode.CodeLens[] {
    if (!fs.existsSync(target)) return [];
    return [
      new vscode.CodeLens(rangeOf(), {
        title: `$(go-to-file) ${title}`,
        command: 'vscode.open',
        arguments: [vscode.Uri.file(target)],
      }),
    ];
  }
}
