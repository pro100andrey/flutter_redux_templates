// Once a day, ask the installed `frx` whether a newer release exists.
//
// The CLI already answers this: `frx upgrade --check --json` reports
// `{status: "available" | "current", from, to}` and exits 1 when there is
// something to install, a contract written so a command could be gated on it.
// The editor is the one surface a user has open every day and never types
// `frx upgrade --check` into, so this is where the answer was going unheard.
//
// Quiet by construction. Only an installed binary is asked — the `dart run`
// fallback has nothing installed to upgrade — at most once per interval, and
// nothing here ever surfaces a failure: a machine that is offline, a release
// endpoint that is down and a binary too old to know `--check` all look the same
// from here, and none of them is the user's problem to hear about.
import * as os from 'os';
import * as vscode from 'vscode';

import * as frx from './frx';
import type { Invocation } from './frx';

/** How often the question is worth asking. */
export const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;

/** Where the last check's time is kept, across windows and sessions. */
export const LAST_CHECK_KEY = 'frx.upgradeCheck.lastMs';

/**
 * Whether a check is due, given when the last one ran.
 *
 * Never checked, or checked a full interval ago, means due. A last-check time
 * in the future — a clock that was set back — is treated as never: waiting out
 * an interval measured from a time that has not happened yet could mean waiting
 * for days.
 */
export function isDue(
  lastCheckedMs: number | undefined,
  nowMs: number,
  intervalMs: number = CHECK_INTERVAL_MS,
): boolean {
  if (lastCheckedMs === undefined || !Number.isFinite(lastCheckedMs)) return true;
  if (lastCheckedMs > nowMs) return true;
  return nowMs - lastCheckedMs >= intervalMs;
}

/** What `frx upgrade --check --json` prints. */
export interface UpgradeCheck {
  status: string;
  from?: string;
  to?: string;
}

/** The parsed check, or null for anything that is not one. */
export function parseCheck(stdout: string): UpgradeCheck | null {
  try {
    const parsed = JSON.parse(stdout);
    return parsed && typeof parsed.status === 'string' ? (parsed as UpgradeCheck) : null;
  } catch {
    return null;
  }
}

/**
 * Ask, if due, and offer the upgrade when there is one.
 *
 * The time is recorded before the ask rather than after a success, so a
 * failing check is retried tomorrow and not on every window — an offline
 * morning would otherwise mean a spawn per activation until the network came
 * back, for a question whose answer can wait.
 */
export async function maybeCheckForUpgrade(
  context: vscode.ExtensionContext,
  inv: Invocation,
  nowMs: number = Date.now(),
): Promise<void> {
  try {
    if (inv.cmd === 'dart') return;
    if (!isDue(context.globalState.get<number>(LAST_CHECK_KEY), nowMs)) return;
    await context.globalState.update(LAST_CHECK_KEY, nowMs);

    const res = await frx.run(inv, ['upgrade', '--check', '--json'], os.homedir(), { quiet: true });
    const check = parseCheck(res.stdout);
    if (!check || check.status !== 'available') return;

    const pick = await vscode.window.showInformationMessage(
      `FRX: frx ${check.to ?? ''} is available` + (check.from ? ` (installed: ${check.from}).` : '.'),
      'Upgrade',
      'Not now',
    );
    if (pick === 'Upgrade') await frx.upgradeFrx(inv);
  } catch {
    // An upgrade check is never worth an error.
  }
}
