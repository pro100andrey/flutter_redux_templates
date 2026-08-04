// The shared scaffolding engine. Every "create & wire" command (substate, page,
// action, tabs, the single-file scaffolders) repeats the same pipeline — run frx,
// offer an overwrite retry on exit 70, surface failures, refresh — and then
// generates the code the new files depend on. This module owns both steps so each
// command is just "gather args → run → post".
//
// **Creation shows no plan.** The risk grading is a rule: destructive operations
// always show one, creative ones never do. Creation is the most frequent
// operation and a step added there is paid every time, while the thing a plan
// guards against is undone by one `frx remove`. Rename and removal keep theirs,
// unconditionally — see commands/artifact.ts.
//
// The extension's mutable state (the watch controller, the after-change
// refresh) is injected per call rather than imported, keeping the engine
// decoupled from activation.
import * as path from 'path';
import * as vscode from 'vscode';

import * as config from './config';
import * as frx from './frx';
import type { Invocation, RunResult } from './frx';
import * as ui from './ui';
import type { FrxWatch } from './watch';
import { EXIT } from './generated/contract';

export interface ScaffoldOptions {
  inv: Invocation;
  args: string[];
  cwd: string;
  afterChange: () => void;
  title: string;
  /**
   * Prompt + progress title for the exit-70 retry. Omitted by commands that
   * cannot collide: `add-nav` only edits files that must already exist, and is
   * idempotent — it reports "already has" and stops.
   */
  overwritePrompt?: string;
  overwriteTitle?: string;
}

/**
 * Run frx to create & wire an artifact, with the shared overwrite / failure
 * handling. On success runs `afterChange` and returns the RunResult so
 * the caller can do its post-step (open files, build_runner, message). Returns
 * null when the user declined the overwrite or the run failed (a message was
 * already shown).
 */
export async function runScaffold(opts: ScaffoldOptions): Promise<RunResult | null> {
  const { inv, args, cwd, afterChange } = opts;
  let res = await frx.runWithProgress(opts.title, inv, args, cwd);
  if (res.code === EXIT.failure && opts.overwritePrompt !== undefined) {
    if (!(await ui.confirmOverwrite(opts.overwritePrompt))) return null;
    res = await frx.runWithProgress(
      opts.overwriteTitle ?? opts.title,
      inv,
      [...args, '--force'],
      cwd,
    );
  }
  if (res.code !== 0) {
    ui.fail(res);
    return null;
  }
  afterChange();
  return res;
}

export interface BuildRunnerOptions {
  inv: Invocation;
  packageRoot: string | null;
  kind: string;
  name: string;
  watch: FrxWatch | null;
  afterChange: () => void;
}

/**
 * Generate the code the new files depend on (freezed part, auto_route class).
 * When `build_runner watch` is running it regenerates on its own, so we skip
 * the prompt entirely. Otherwise honour the `frx.runBuildRunner` mode.
 */
export async function maybeRunBuildRunner({
  inv,
  packageRoot,
  kind,
  name,
  watch,
  afterChange,
}: BuildRunnerOptions): Promise<void> {
  if (watch?.running) {
    vscode.window.showInformationMessage(`FRX: created ${kind} "${name}". Watch will regenerate the code.`);
    return;
  }

  const mode = config.runBuildRunner();
  if (mode === 'never') {
    vscode.window.showInformationMessage(`FRX: created ${kind} "${name}".`);
    return;
  }
  if (mode === 'ask') {
    const pick = await vscode.window.showInformationMessage(
      `FRX: created ${kind} "${name}". Run build_runner now?`,
      'Run build_runner',
    );
    if (pick !== 'Run build_runner') return;
  }

  if (!packageRoot) {
    vscode.window.showWarningMessage('FRX: could not locate the package to run build_runner in. Run it manually.');
    return;
  }

  // Resolve `dart` the same way we resolve `frx` — don't assume it's on PATH
  // (the Dock-launched-VSCode case). If it isn't reachable, say so.
  const dartCmd = await frx.resolveDart(inv);
  if (!dartCmd) {
    vscode.window.showWarningMessage(
      'FRX: `dart` is not on PATH, so build_runner can\'t run here. ' +
        'Run `dart run build_runner build` manually, or open a terminal where dart is available.',
    );
    return;
  }

  const res = await frx.runWithProgress(
    `FRX: build_runner in ${path.basename(packageRoot)}…`,
    { cmd: dartCmd, baseArgs: [], label: dartCmd },
    ['run', 'build_runner', 'build'],
    packageRoot,
  );
  if (res.code !== 0) return ui.fail(res);
  vscode.window.showInformationMessage(`FRX: "${name}" ready (code generated).`);
  afterChange(); // codegen cleared the "missing part" findings
}
