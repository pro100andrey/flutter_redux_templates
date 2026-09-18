// Quick-fix lightbulbs for `frx doctor` findings in the Problems panel.
//
// Auto-fixable findings (tagged with a `code` by the doctor service — a missing
// generated part, an orphan substate, a stale docs/flows export) get a "Run frx
// doctor --fix" action. `doctor --fix` repairs everything fixable at once, so
// one action suffices; the label reflects the finding it was raised on.
import * as vscode from 'vscode';

import type { FixId } from './generated/contract';

// `Record<FixId, …>` and not `Record<string, …>`: a remedy added to the CLI's
// sealed `Fix` hierarchy now fails to compile here until it has a label, rather
// than reaching the Problems panel as a lightbulb with no text.
const LABELS: Record<FixId, string> = {
  build_runner: 'FRX: generate missing code (doctor --fix)',
  orphan: 'FRX: remove orphan substate (doctor --fix)',
  'flow-docs': 'FRX: regenerate docs/flows (doctor --fix)',
  skills: 'FRX: update .claude/skills for this frx (doctor --fix)',
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

      // Widened to index, because `code` arrives from whatever CLI is on PATH
      // — which may be newer than this build and emit a remedy this map has
      // never heard of. The fallback is what keeps that a generic lightbulb
      // instead of `undefined`. The map's own type stays exhaustive over the
      // remedies this build *does* know, which is where the check is worth
      // having.
      const labels: Record<string, string | undefined> = LABELS;
      const action = new vscode.CodeAction(
        labels[code] ?? 'FRX: run doctor --fix',
        vscode.CodeActionKind.QuickFix,
      );
      action.command = { command: 'frx.doctorFix', title: 'FRX: doctor --fix' };
      action.diagnostics = [d];
      actions.push(action);
    }
    return actions;
  }
}
