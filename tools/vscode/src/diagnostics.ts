// Publishing findings into a vscode.DiagnosticCollection. Both the doctor audit
// (extension.ts) and the build_runner watch (watch.ts) collect findings and need
// the same "group by file, clear, set" dance — this centralizes it.
import * as vscode from 'vscode';

import { pushInto } from './collections';

/** The minimum a finding must carry to be squiggled: where it lives. */
export interface FileAnchored {
  file: string | null;
}

/** Where inside its file a finding points, when the CLI could say. 1-based. */
export interface LineAnchored {
  line?: number;
  column?: number;
}

/**
 * The range a finding is squiggled on.
 *
 * The CLI's positions are 1-based, as the analyzer reports them and as a person
 * reads them; the editor's are 0-based. A finding with a line but no column
 * lands at the start of that line, and one with neither lands at the top of the
 * file — which is where every doctor finding used to land, so a reader had to
 * search the file for the declaration the message named.
 *
 * Zero-width on purpose: the CLI names a point, not an extent, and a squiggle
 * stretched to a guessed end would claim more than was said.
 */
export function rangeFor(finding: LineAnchored): vscode.Range {
  const line = finding.line !== undefined && finding.line > 0 ? finding.line - 1 : 0;
  const column =
    finding.line !== undefined && finding.column !== undefined && finding.column > 0
      ? finding.column - 1
      : 0;
  const at = new vscode.Position(line, column);
  return new vscode.Range(at, at);
}

/**
 * Replace `collection`'s contents with `findings`, grouped by file. For each
 * finding, `toDiagnostic(f)` returns a vscode.Diagnostic — or null to skip it
 * entirely.
 *
 * A finding with no `.file` lands on `fallback` when one is given. Some findings
 * honestly have no file: "an empty artifact folder" is about a directory, and
 * "AppState not found" is about its absence. Dropping them was silent and
 * exactly wrong — the doctor chip counts every finding and its click opens this
 * panel, so a file-less one made the chip say `⚠ 1` over an empty panel. A
 * counted finding has to be a shown finding.
 */
export function publishByFile<T extends FileAnchored>(
  collection: vscode.DiagnosticCollection,
  findings: readonly T[],
  toDiagnostic: (finding: T) => vscode.Diagnostic | null,
  fallback?: string,
): void {
  collection.clear();
  const byFile = new Map<string, vscode.Diagnostic[]>();
  for (const f of findings) {
    const d = toDiagnostic(f);
    const where = f.file ?? fallback;
    if (!d || !where) continue;
    pushInto(byFile, where, d);
  }
  for (const [file, list] of byFile) {
    collection.set(vscode.Uri.file(file), list);
  }
}
