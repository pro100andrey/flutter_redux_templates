// What FRX artifact the cursor is sitting on.
//
// One implementation, two callers: the F2 rename provider (which needs the range
// to replace) and the editor context menu's Rename entry (which needs only the
// match). Before this, the context-menu entry discarded the cursor entirely and
// showed the same generic picker the palette shows — right-clicking a state
// class offered you every substate and page in the project.
//
// The question "is this symbol an FRX artifact, and what is its canonical base
// name" is answered by `frx which` (see queries.ts), so the naming conventions
// stay in the CLI. This file only decides which word to ask about.
import * as vscode from 'vscode';

import * as frx from './frx';
import * as paths from './paths';
import * as queries from './queries';
import type { WhichMatch } from './queries';

/** The artifact under `position`, with the range its symbol occupies. */
export interface CursorArtifact {
  range: vscode.Range;
  match: WhichMatch;
}

/**
 * Resolve the identifier under `position` in `document` to an FRX artifact, or
 * null when it is not one (or when frx / the workspace cannot be resolved).
 */
export async function artifactAt(
  context: vscode.ExtensionContext,
  document: vscode.TextDocument,
  position: vscode.Position,
): Promise<CursorArtifact | null> {
  const range = document.getWordRangeAtPosition(position, /[A-Za-z_][A-Za-z0-9_]*/);
  if (!range) return null;
  const root = paths.findWorkspaceRoot();
  if (!root) return null;
  const inv = await frx.resolveFrx(context, root);
  if (!inv) return null;
  const match = await queries.which(inv, document.getText(range), root);
  return match ? { range, match } : null;
}

/**
 * The artifact under the cursor of the active Dart editor, or null.
 *
 * Null rather than an error when there is no Dart editor or the symbol is not
 * ours: the caller falls back to the artifact picker. It cannot chain to another
 * extension's rename — a menu item is a command, not a link in a chain — and
 * hiding the entry conditionally is not on offer either, because a `when` clause
 * is evaluated synchronously and this needs a CLI call.
 */
export async function artifactAtActiveCursor(
  context: vscode.ExtensionContext,
): Promise<WhichMatch | null> {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== 'dart') return null;
  const found = await artifactAt(context, editor.document, editor.selection.active);
  return found?.match ?? null;
}
