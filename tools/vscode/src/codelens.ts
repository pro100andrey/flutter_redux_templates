// CodeLens for the monorepo's conventional files — actions right where you
// read the code:
//   • `redux/<sub>/models/<sub>_state.dart`  → "⚡ Add action…" above the class
//   • `app/lib/connectors/<x>_page_connector.dart` → "Open page"
//   • `ui/lib/pages/<x>_page.dart`           → "Open connector"
// Pure path/regex derivation — no CLI calls, so lenses are instant.
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

    return [];
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
