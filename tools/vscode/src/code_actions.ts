// Quick-fix lightbulbs for `frx doctor` findings in the Problems panel.
//
// Auto-fixable findings (tagged with a `code` by the doctor service — a missing
// generated part, an orphan substate, a stale docs/flows export) get a "Run frx
// doctor --fix" action. `doctor --fix` repairs everything fixable at once, so
// one action suffices; the label reflects the finding it was raised on.
import * as vscode from 'vscode';

const LABELS: Record<string, string> = {
  build_runner: 'FRX: generate missing code (doctor --fix)',
  orphan: 'FRX: remove orphan substate (doctor --fix)',
  'flow-docs': 'FRX: regenerate docs/flows (doctor --fix)',
};

export class FrxCodeActionProvider implements vscode.CodeActionProvider {
  static readonly metadata: vscode.CodeActionProviderMetadata = {
    providedCodeActionKinds: [vscode.CodeActionKind.QuickFix],
  };

  /**
   * Every file doctor can anchor a finding on — deliberately not pinned to a
   * language. A stale `docs/flows/*.md` finding lands on a markdown document,
   * and a provider registered for `language: 'dart'` would never offer its fix
   * there: the diagnostic shows up in Problems with no way to act on it. The
   * provider filters on `source === 'frx'` anyway, so widening costs nothing.
   */
  static readonly selector: vscode.DocumentSelector = { scheme: 'file' };

  provideCodeActions(
    _document: vscode.TextDocument,
    _range: vscode.Range | vscode.Selection,
    context: vscode.CodeActionContext,
  ): vscode.CodeAction[] {
    const actions: vscode.CodeAction[] = [];
    const seen = new Set<string>();
    for (const d of context.diagnostics) {
      if (d.source !== 'frx' || !d.code) continue;
      const code = String(d.code);
      if (seen.has(code)) continue; // one action per remedy kind
      seen.add(code);

      const action = new vscode.CodeAction(
        LABELS[code] ?? 'FRX: run doctor --fix',
        vscode.CodeActionKind.QuickFix,
      );
      action.command = { command: 'frx.doctorFix', title: 'FRX: doctor --fix' };
      action.diagnostics = [d];
      actions.push(action);
    }
    return actions;
  }
}
