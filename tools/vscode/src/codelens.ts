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

/** The Range of the first `class <name>` line, or line 0 as a fallback. */
function classRange(document: vscode.TextDocument, namePattern: string): vscode.Range {
  const re = new RegExp(`^(?:abstract\\s+)?class\\s+${namePattern}`, 'm');
  const m = re.exec(document.getText());
  const pos = m ? document.positionAt(m.index) : new vscode.Position(0, 0);
  return new vscode.Range(pos, pos);
}

export class FrxLensProvider implements vscode.CodeLensProvider {
  /** @param root the monorepo root */
  constructor(private readonly root: string) {}

  provideCodeLenses(document: vscode.TextDocument): vscode.CodeLens[] {
    const file = document.uri.fsPath;
    const sep = path.sep;

    // Substate state model → Add action… (pre-filled with the substate).
    const state = file.match(
      new RegExp(
        `\\${sep}${leafOf(LAYOUT.redux)}\\${sep}([a-z0-9_]+)\\${sep}models\\${sep}\\1${escaped(LAYOUT.stateSuffix)}$`,
      ),
    );
    if (state) {
      const field = naming.camelOf(state[1]);
      const range = classRange(document, '\\w+State');
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
    const connector = file.match(
      new RegExp(
        `\\${sep}${leafOf(LAYOUT.connectors)}\\${sep}(\\w+)${escaped(LAYOUT.connectorSuffix)}$`,
      ),
    );
    if (connector) {
      const className = `${naming.pascalOf(connector[1])}PageConnector`;
      const page = path.join(
        dirOf(this.root, LAYOUT.pages),
        `${connector[1]}${LAYOUT.pageSuffix}`,
      );
      return [
        ...this._openLens(document, className, page, 'Open page'),
        new vscode.CodeLens(classRange(document, className), {
          title: '$(git-merge) Flow',
          command: 'frx.flow',
          arguments: [{ frxName: connector[1] }],
        }),
      ];
    }
    // Widget connector → the widget it wraps. No Flow: `frx flow` walks a page.
    // Tested after the page connector, whose suffix this one is a tail of.
    const widgetConnector = file.match(
      new RegExp(
        `\\${sep}${leafOf(LAYOUT.connectors)}\\${sep}(\\w+)${escaped(LAYOUT.widgetConnectorSuffix)}$`,
      ),
    );
    if (widgetConnector) {
      const widget = this._widgetOf(document, widgetConnector[1]);
      if (!widget) return [];
      const className = `${naming.pascalOf(widgetConnector[1])}Connector`;
      return this._openLens(document, className, widget, 'Open widget');
    }
    const page = file.match(
      new RegExp(
        `\\${sep}${leafOf(LAYOUT.pages)}\\${sep}(\\w+)${escaped(LAYOUT.pageSuffix)}$`,
      ),
    );
    if (page) {
      const conn = path.join(
        dirOf(this.root, LAYOUT.connectors),
        `${page[1]}${LAYOUT.connectorSuffix}`,
      );
      return this._openLens(document, `${naming.pascalOf(page[1])}Page`, conn, 'Open connector');
    }
    // Any other file of the ui package → its connector, when one is named for
    // it. The reverse of "Open widget", by path alone: `<stem>_connector.dart`
    // is what `add-connector` writes, so a widget whose class carries a kind
    // suffix (`PinFormField` for `pin`) gets no lens here — the connector's own
    // import is the only place that pairing is stated, and this file is not it.
    const uiDir = dirOf(this.root, LAYOUT.ui) + sep;
    if (file.startsWith(uiDir) && file.endsWith('.dart')) {
      const stem = path.basename(file, '.dart');
      const conn = path.join(
        dirOf(this.root, LAYOUT.connectors),
        `${stem}${LAYOUT.widgetConnectorSuffix}`,
      );
      return this._openLens(document, naming.pascalOf(stem), conn, 'Open connector');
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
  private _widgetOf(document: vscode.TextDocument, stem: string): string | null {
    const imports = [...document.getText().matchAll(/^import\s+'package:ui\/([^']+\.dart)'/gm)]
      .map((m) => m[1]);
    const named = imports.find((p) => p.endsWith(`/${stem}.dart`) || p === `${stem}.dart`);
    const chosen = named ?? (imports.length === 1 ? imports[0] : undefined);
    if (!chosen) return null;
    return path.join(dirOf(this.root, LAYOUT.ui), ...chosen.split('/'));
  }

  /** A "jump to counterpart" lens, only when the counterpart exists. */
  private _openLens(
    document: vscode.TextDocument,
    className: string,
    target: string,
    title: string,
  ): vscode.CodeLens[] {
    if (!fs.existsSync(target)) return [];
    return [
      new vscode.CodeLens(classRange(document, className), {
        title: `$(go-to-file) ${title}`,
        command: 'vscode.open',
        arguments: [vscode.Uri.file(target)],
      }),
    ];
  }
}
