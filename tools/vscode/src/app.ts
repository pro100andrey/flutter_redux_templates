// The context every command handler receives.
//
// Activation owns three long-lived services and the post-change refresh; rather
// than importing activation's mutable module state (which would couple every
// command to the entrypoint), they are bundled here and passed down. `watch` and
// `doctor` are null outside our monorepo, and are declared readonly because
// activation exposes them as getters — a command captured before the monorepo
// branch runs still sees the live instances.
import type * as vscode from 'vscode';

import type { FrxDoctor } from './doctor';
import type { FrxWatch } from './watch';

export interface App {
  context: vscode.ExtensionContext;
  readonly watch: FrxWatch | null;
  readonly doctor: FrxDoctor | null;
  /** Refresh the tree and re-run doctor into the Problems panel. */
  refresh: () => void;
}
