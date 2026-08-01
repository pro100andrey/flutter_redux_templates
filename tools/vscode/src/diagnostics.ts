// Publishing findings into a vscode.DiagnosticCollection. Both the doctor audit
// (extension.ts) and the build_runner watch (watch.ts) collect findings and need
// the same "group by file, clear, set" dance — this centralizes it.
import * as vscode from 'vscode';

/** The minimum a finding must carry to be squiggled: where it lives. */
export interface FileAnchored {
  file: string | null;
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
    const list = byFile.get(where);
    if (list) list.push(d);
    else byFile.set(where, [d]);
  }
  for (const [file, list] of byFile) {
    collection.set(vscode.Uri.file(file), list);
  }
}
