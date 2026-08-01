// The doctor health service: runs `frx doctor --json` and mirrors its findings
// into a DiagnosticCollection (Problems panel + inline squiggles) and an ambient
// status-bar chip (✓ / ⚠ N / ✗ N). A stateful service like FrxWatch — it owns
// its collection + status item and hands them back for subscription. The doctor
// *commands* (run, --fix) live with the other commands; this is just the audit.
import * as vscode from 'vscode';

import * as diag from './diagnostics';
import * as frx from './frx';
import * as paths from './paths';
import * as queries from './queries';
import type { DoctorFinding } from './queries';
import * as ui from './ui';

export class FrxDoctor {
  private readonly _collection: vscode.DiagnosticCollection;
  private readonly _status: vscode.StatusBarItem;
  /** Monotonic token so an out-of-order refresh can't clobber a newer one. */
  private _token = 0;

  /** @param _onChange full refresh (tree + this) to run after a --fix */
  constructor(
    private readonly _context: vscode.ExtensionContext,
    private readonly _onChange: () => void,
  ) {
    this._collection = vscode.languages.createDiagnosticCollection('frx');
    this._status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 99);
    this._status.command = 'workbench.actions.view.problems';
    // Shown from the start, before any audit has run. The chip used to appear
    // only at the end of a *successful* refresh, so every way an audit can bail
    // — no workspace root, no frx on PATH, unparseable output — looked
    // identical to the extension not being active at all.
    this._pending('never run');
    this._status.show();
  }

  /** No audit to show yet, or the last one could not be run. */
  private _pending(why: string): void {
    this._status.text = '$(question) doctor';
    this._status.backgroundColor = undefined;
    this._status.tooltip = `frx doctor: ${why}. Click to open the Problems panel.`;
  }

  /** The disposables to register (diagnostic collection + status item). */
  get disposables(): vscode.Disposable[] {
    return [this._collection, this._status];
  }

  /**
   * Run `frx doctor --json` and mirror its findings into the collection + status
   * chip. Silent — a resolve/parse failure just leaves the previous set in place.
   */
  async refresh(): Promise<void> {
    const root = paths.findWorkspaceRoot();
    if (!root) return;

    // Tag this run at entry; if a newer refresh starts before we finish, drop our
    // result so a slower stale audit can't overwrite a fresher one.
    const token = ++this._token;
    const inv = await frx.resolveFrx(this._context, root);
    if (!inv) {
      this._pending('frx not found — set `frx.path` or install the CLI');
      return;
    }

    const parsed = await queries.doctor(inv, root);
    if (token !== this._token) return;
    if (!parsed) {
      // e.g. project-not-found (exit 70, no JSON). The previous findings stay
      // in the Problems panel; the chip says they are no longer current.
      this._pending('last audit could not be read — see the FRX output');
      return;
    }

    diag.publishByFile(
      this._collection,
      parsed.findings ?? [],
      (f) => {
      const severity =
        f.severity === 'error' ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Warning;
      // A lightbulb needs a text document to hang off, and a finding with no
      // file has none — it is about a directory, or about a file's absence. So
      // a fixable one that lands on the workspace root names its own remedy in
      // the sentence: the alternative is a Problems entry that says a fix
      // exists and offers no way to reach it, which is the failure this whole
      // fallback was added to end, one level down.
      const how = !f.file && f.fix ? ' — run “FRX: Doctor — fix”.' : '';
      const d = new vscode.Diagnostic(
        new vscode.Range(0, 0, 0, 0),
        `frx doctor: ${f.message}${how}`,
        severity,
      );
      d.source = 'frx';
      // Tag auto-fixable findings so the code-action provider can offer a fix.
      if (f.fix) d.code = f.fix;
      return d;
      },
      // Where a finding with no file goes. The workspace root is the honest
      // anchor for one that is about the project rather than about a line.
      root,
    );

    this._renderStatus(parsed.findings ?? []);
  }

  /** Update the status-bar doctor chip from the full findings list. */
  private _renderStatus(findings: DoctorFinding[]): void {
    const errors = findings.filter((f) => f.severity === 'error').length;
    const warnings = findings.length - errors;
    // Named in the tooltip because the lightbulb cannot always carry it: a
    // finding about a directory has no document to raise one on, and the chip
    // is the one surface that is always there.
    const fixable = findings.filter((f) => f.fix).length;
    if (errors > 0) {
      this._status.text = `$(error) ${errors}`;
      this._status.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
    } else if (warnings > 0) {
      this._status.text = `$(warning) ${warnings}`;
      this._status.backgroundColor = undefined;
    } else {
      this._status.text = '$(pass) doctor';
      this._status.backgroundColor = undefined;
    }
    this._status.tooltip =
      findings.length === 0
        ? 'frx doctor: no issues. Click to open the Problems panel.'
        : `frx doctor: ${errors} error(s), ${warnings} warning(s)` +
          (fixable > 0 ? `, ${fixable} auto-fixable (“FRX: Doctor — fix”)` : '') +
          '. Click to open the Problems panel.';
    this._status.show();
  }

  /** Run `frx doctor` and reveal its findings in the FRX output channel. */
  async run(): Promise<void> {
    const target = await ui.resolveTarget(this._context, undefined);
    if (!target) return;
    const { inv, targetDir } = target;

    const res = await frx.runWithProgress('FRX: doctor…', inv, ['doctor', '--root', targetDir], targetDir);
    frx.output().show(true); // findings streamed here; exit 1 just means "issues found"
    if (res.code > 1) ui.fail(res);
    this.refresh(); // mirror the same findings into the Problems panel
  }

  /** Run `frx doctor --fix` (from a Problems-panel quick-fix), then re-audit. */
  async fix(): Promise<void> {
    const target = await ui.resolveTarget(this._context, undefined);
    if (!target) return;
    const { inv, targetDir } = target;

    const res = await frx.runWithProgress(
      'FRX: doctor --fix…',
      inv,
      ['doctor', '--fix', '--root', targetDir],
      targetDir,
    );
    if (res.code > 1) {
      ui.fail(res);
      return;
    }
    vscode.window.showInformationMessage('FRX: doctor --fix applied.');
    this._onChange(); // re-audit: cleared findings drop out of the Problems panel
  }
}
