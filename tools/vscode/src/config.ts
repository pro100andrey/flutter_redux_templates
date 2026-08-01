// Typed accessors for the extension's `frx.*` settings. One place that knows
// each setting's key and default, so command code reads `config.runBuildRunner()`
// instead of re-spelling `getConfiguration('frx').get('runBuildRunner', 'ask')`
// (where a drifting default would go unnoticed).
//
// There are three, and each describes a real difference. `path` is the only way
// to intervene when CLI resolution guesses wrong; `runBuildRunner` has three
// values and its wrong value costs time on every generation; `editorRename` is
// the only setting whose two branches are caused from *outside* this repository,
// since F2 may be claimed by another extension on one machine and not another.
//
// Three others were removed because they described forks nobody took, and their
// behaviour froze at the value people already used: the created file always
// opens, no plan is shown before creating, lenses always render.
import * as vscode from 'vscode';

/** When to run build_runner after a scaffolder writes codegen input. */
export type BuildRunnerMode = 'always' | 'ask' | 'never';

function frxConfig(): vscode.WorkspaceConfiguration {
  return vscode.workspace.getConfiguration('frx');
}

/** Explicit path to the `frx` executable, trimmed ('' = auto-resolve). */
export const binPath = (): string => frxConfig().get('path', '').trim();

/** Whether to run build_runner after scaffolding. */
export const runBuildRunner = (): BuildRunnerMode =>
  frxConfig().get<BuildRunnerMode>('runBuildRunner', 'ask');

/** Let F2 rename the whole artifact via `frx rename`. */
export const editorRename = (): boolean => frxConfig().get('editorRename', true);
