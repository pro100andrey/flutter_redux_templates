// Editor rename (F2) for FRX artifacts.
//
// When the cursor sits on a symbol that belongs to a substate or page — its
// state class, Select<Pascal>, route, connector, or the bare field/folder name
// — F2 renames the WHOLE artifact (files, classes, every wiring reference) via
// `frx rename`, not just that one identifier. For any other symbol the provider
// steps aside so the Dart extension handles the rename normally.
//
// Whether the symbol is an FRX artifact — and the canonical base name to hand
// `frx rename` — is answered by `frx which` (see queries.ts), so the naming
// conventions live in the CLI, not here. The actual rename runs through the
// shared `frx.rename` command, which is also available from the palette, the
// editor context menu, and the tree (the reliable path if this provider ever
// loses the rename race to another extension).
import * as vscode from 'vscode';

import * as config from './config';
import * as cursor from './cursor';
import * as naming from './naming';

export class FrxRenameProvider implements vscode.RenameProvider {
  constructor(private readonly context: vscode.ExtensionContext) {}

  /** Resolve the identifier under `position` to an FRX artifact, or null. */
  private _resolve(document: vscode.TextDocument, position: vscode.Position) {
    return cursor.artifactAt(this.context, document, position);
  }

  async prepareRename(
    document: vscode.TextDocument,
    position: vscode.Position,
  ): Promise<{ range: vscode.Range; placeholder: string }> {
    if (!config.editorRename()) {
      // Disabled → reject so the Dart extension's rename handles this symbol.
      throw new Error('FRX editor rename is disabled.');
    }
    const r = await this._resolve(document, position);
    if (!r) {
      throw new Error('Not an FRX substate or page — use the Dart rename.');
    }
    return { range: r.range, placeholder: document.getText(r.range) };
  }

  async provideRenameEdits(
    document: vscode.TextDocument,
    position: vscode.Position,
    newName: string,
  ): Promise<vscode.WorkspaceEdit | undefined> {
    const r = await this._resolve(document, position);
    if (!r) return undefined; // prepareRename gates this, but stay defensive
    const newBase = naming.stripAffix(newName, r.match.suffix, r.match.prefix);
    // frx rename performs the cross-file change (and codegen) on disk itself;
    // hand the work to the shared command and return an empty edit so VSCode
    // doesn't also try to apply anything.
    //
    // Deliberately not awaited. The confirmation now lives on the plan's own tab
    // and can go unanswered for as long as you keep reading, so awaiting would
    // hold F2's rename operation — and its progress indicator — open for the
    // whole of that. The command owns the rest of the flow; this provider's job
    // ends once it has handed the work over.
    void vscode.commands.executeCommand('frx.rename', {
      name: r.match.name,
      newName: newBase,
      kind: r.match.kind,
    });
    return new vscode.WorkspaceEdit();
  }
}
