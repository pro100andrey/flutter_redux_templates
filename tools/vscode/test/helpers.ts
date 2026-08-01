// Test harness for the extension's pure/stubbable logic.
//
// The modules `require('vscode')`, which only exists inside VSCode's host. This
// installs a minimal stub via the module loader so the modules load and run
// under plain `node --test`. The stub is mutable: tests set `vscode._quickPick`
// / `vscode._input` to script what the user "picks", and read
// `vscode._lastQuickPick` to assert what a picker offered. Import this file
// FIRST in every test — the loader hook must be in place before any module that
// requires 'vscode' is loaded.
//
// The stub is typed loosely on purpose: it implements the handful of API
// surfaces the code under test actually touches, not the real `vscode` module,
// so claiming that type would be a lie.
import Module = require('module');

/* eslint-disable @typescript-eslint/no-explicit-any */

const noop = () => {};
const disposable = { dispose: noop };

/** What a picker was offered, captured for assertions. */
export interface QuickPickCall {
  items: any[];
  opts: any;
}

export interface VscodeStub {
  /** Scripted result of the next showQuickPick — a value or a chooser fn. */
  _quickPick: any;
  /** Scripted result of the next showInputBox. */
  _input: string | undefined;
  _lastQuickPick: QuickPickCall | null;
  _lastInput: { opts: any } | null;
  /**
   * Drives the next `createQuickPick`. Called once the picker is shown, with
   * the live object: type into `qp.value` (which fires `onDidChangeValue`),
   * set `qp.selectedItems`, then `qp.accept()` or `qp.hide()`.
   */
  _driveQuickPick: ((qp: any) => void) | undefined;
  /** The last `createQuickPick` after the drive ran — assert on `.items`. */
  _lastCreatedQuickPick: any;
  /** Every `executeCommand(id, ...args)` the code under test issued. */
  _commands: { id: string; args: any[] }[];
  /** Every file `workspace.fs.writeFile` wrote, by `fsPath`. */
  _files: Map<string, string>;
  /** The status-bar items created and not yet disposed. */
  _statusBar: any[];
  [key: string]: any;
}

/**
 * The tab model, scriptable.
 *
 * The plan surface stands on it: which tab is active decides whether the ✓/✕
 * toolbar entries are shown, and a tab closing is a No. Both are events in the
 * real API, so the stub has to be able to fire them rather than merely hold a
 * value — a test that could only assert the final state would pass against code
 * that never subscribed.
 */
function makeTabGroups() {
  const tabHandlers: ((e: any) => void)[] = [];
  const groupHandlers: (() => void)[] = [];
  const group: any = { tabs: [] as any[], activeTab: undefined as any, viewColumn: 2 };
  return {
    all: [group],
    activeTabGroup: group,
    onDidChangeTabs: (h: (e: any) => void) => (tabHandlers.push(h), disposable),
    onDidChangeTabGroups: (h: () => void) => (groupHandlers.push(h), disposable),
    close: (tab: any) => {
      group.tabs = group.tabs.filter((t: any) => t !== tab);
      if (group.activeTab === tab) group.activeTab = group.tabs[0];
      for (const h of tabHandlers) h({ opened: [], closed: [tab], changed: [] });
      return Promise.resolve(true);
    },
    /** Test helper: put a tab in the group and make it active. */
    _open(tab: any) {
      group.tabs = [...group.tabs, tab];
      group.activeTab = tab;
      for (const h of tabHandlers) h({ opened: [tab], closed: [], changed: [] });
    },
    /** Test helper: focus a tab that is already open (or nothing). */
    _activate(tab: any) {
      group.activeTab = tab;
      for (const h of tabHandlers) h({ opened: [], closed: [], changed: tab ? [tab] : [] });
    },
    _group: group,
  };
}

export const vscode: VscodeStub = {
  _quickPick: undefined,
  _input: undefined,
  _lastQuickPick: null,
  _lastInput: null,
  _driveQuickPick: undefined,
  _lastCreatedQuickPick: null,
  _commands: [],
  _files: new Map<string, string>(),
  _statusBar: [],

  window: {
    showQuickPick: async (items: any[], opts: any) => {
      vscode._lastQuickPick = { items, opts };
      return typeof vscode._quickPick === 'function' ? vscode._quickPick(items) : vscode._quickPick;
    },
    // Enough of the QuickPick object for a picker that accepts a typed value:
    // `value` is a setter so assigning it fires onDidChangeValue, the way the
    // real one does as the user types.
    createQuickPick: () => {
      const handlers: {
        change: ((v: string) => void)[];
        select: ((items: any[]) => void)[];
        accept: (() => void)[];
        hide: (() => void)[];
      } = { change: [], select: [], accept: [], hide: [] };
      let value = '';
      let selected: any[] = [];
      let items: any[] = [];
      const qp: any = {
        get items() {
          return items;
        },
        // Assigning `items` clears the selection and fires the change event on
        // a later tick — VSCode's actual behaviour, and the reason a guard that
        // is only raised synchronously does not hold. Modelled faithfully
        // because a stub that fires it synchronously makes such a guard look
        // like it works.
        set items(next: any[]) {
          items = next;
          if (selected.length === 0) return;
          selected = [];
          setImmediate(() => {
            for (const h of handlers.select) h([]);
          });
        },
        title: '',
        placeholder: '',
        ignoreFocusOut: false,
        get value() {
          return value;
        },
        set value(v: string) {
          value = v;
          for (const h of handlers.change) h(v);
        },
        // A setter, like `value`: assigning a selection is how the user ticks
        // a box, and the code under test reassigns it to restore picks after
        // rebuilding `items` — which must re-enter the handler exactly as the
        // real API does, or the guard against that recursion goes untested.
        get selectedItems() {
          return selected;
        },
        set selectedItems(items: any[]) {
          selected = items;
          for (const h of handlers.select) h(items);
        },
        onDidChangeValue: (h: (v: string) => void) => (handlers.change.push(h), disposable),
        onDidChangeSelection: (h: (items: any[]) => void) => (handlers.select.push(h), disposable),
        onDidAccept: (h: () => void) => (handlers.accept.push(h), disposable),
        onDidHide: (h: () => void) => (handlers.hide.push(h), disposable),
        accept: () => {
          for (const h of handlers.accept) h();
        },
        hide: () => {
          for (const h of handlers.hide) h();
        },
        dispose: noop,
        show: () => {
          vscode._lastCreatedQuickPick = qp;
          // Deferred: the caller must finish wiring its handlers and return
          // its Promise before anything is "typed".
          setImmediate(() => vscode._driveQuickPick?.(qp));
        },
      };
      return qp;
    },
    showInputBox: async (opts: any) => {
      vscode._lastInput = { opts };
      return vscode._input;
    },
    createOutputChannel: () => ({ appendLine: noop, append: noop, show: noop }),
    // Kept in `_statusBar` only while shown: the chip's whole contract is that
    // it exists exactly as long as an answer is outstanding, so a stub that
    // forgot disposal could not tell "still waiting" from "done".
    createStatusBarItem: () => {
      const item: any = {
        command: '',
        text: '',
        tooltip: '',
        show: () => {
          if (!vscode._statusBar.includes(item)) vscode._statusBar.push(item);
        },
        hide: () => {
          vscode._statusBar = vscode._statusBar.filter((i: any) => i !== item);
        },
        dispose: () => item.hide(),
      };
      return item;
    },
    createTreeView: () => disposable,
    showErrorMessage: async () => undefined,
    showWarningMessage: async () => undefined,
    showInformationMessage: async () => undefined,
    withProgress: (_opts: any, task: () => any) => task(),
    tabGroups: makeTabGroups(),
  },
  workspace: {
    workspaceFolders: [],
    getConfiguration: () => ({ get: (_k: string, d: unknown) => d }),
    createFileSystemWatcher: () => ({ onDidCreate: noop, onDidChange: noop, onDidDelete: noop, dispose: noop }),
    onDidDeleteFiles: () => disposable,
    onDidCreateFiles: () => disposable,
    onDidRenameFiles: () => disposable,
    openTextDocument: async () => ({}),
    fs: {
      createDirectory: async () => undefined,
      writeFile: async (uri: any, bytes: Uint8Array) => {
        vscode._files.set(uri.fsPath ?? uri.path, new TextDecoder().decode(bytes));
      },
      delete: async (uri: any) => {
        vscode._files.delete(uri.fsPath ?? uri.path);
      },
    },
  },
  languages: {
    createDiagnosticCollection: () => ({ clear: noop, set: noop, dispose: noop }),
    registerCodeLensProvider: () => disposable,
    registerRenameProvider: () => disposable,
    registerCodeActionsProvider: () => disposable,
  },
  commands: {
    registerCommand: () => disposable,
    // Recorded rather than swallowed: `setContext` is the only way the toolbar
    // gate is observable, and `vscode.openWith` is the only way the plan tab is.
    executeCommand: async (id: string, ...args: any[]) => {
      vscode._commands.push({ id, args });
      return undefined;
    },
  },
  // `toString()` is modelled faithfully — `file:///` plus a percent-encoded
  // path — because a caller that embeds a URI in text gets "[object Object]"
  // from a stub that omits it, and the assertion then passes or fails for a
  // reason that has nothing to do with the code under test.
  Uri: {
    file: (f: string) => ({
      fsPath: f,
      path: f,
      toString: () => `file://${f.split('/').map(encodeURIComponent).join('/')}`,
    }),
    // Built through `file` rather than as a bare object, so a joined URI carries
    // the same faithful `toString` — two documents in one directory are told
    // apart by comparing them, and "[object Object]" would make every plan tab
    // look like every other one.
    joinPath: (base: any, ...parts: string[]) =>
      vscode.Uri.file([base.fsPath ?? base.path, ...parts].join('/')),
  },
  // Keep their coordinates: a test asserting where a click lands has nothing
  // to look at otherwise.
  Range: class {
    constructor(
      public start?: any,
      public end?: any,
    ) {}
  },
  Position: class {
    constructor(
      public line?: number,
      public character?: number,
    ) {}
  },
  Diagnostic: class {},
  DiagnosticSeverity: { Error: 0, Warning: 1 },
  ThemeColor: class {},
  // Keeps its id, so a test can assert which icon a row chose.
  ThemeIcon: class {
    constructor(public id?: string) {}
  },
  EventEmitter: class {
    event = noop;
    fire() {}
  },
  // Keeps what it was constructed with, so a test can assert the label and the
  // expand state a row was built with (the real TreeItem does the same).
  TreeItem: class {
    constructor(
      public label?: any,
      public collapsibleState?: number,
    ) {}
  },
  TreeItemCollapsibleState: { None: 0, Collapsed: 1, Expanded: 2 },
  StatusBarAlignment: { Left: 1 },
  QuickPickItemKind: { Default: 0, Separator: -1 },
  CodeAction: class {},
  CodeActionKind: { QuickFix: 'quickfix' },
  // Keeps its range and command, like the real one: a lens whose command the
  // stub threw away cannot be asserted on, and a renamed command id firing from a
  // lens is exactly the bug that reached a user.
  CodeLens: class {
    constructor(
      public range: any,
      public command?: any,
    ) {}
  },
  RelativePattern: class {},
  WorkspaceEdit: class {},
  ProgressLocation: { Notification: 15 },
  ViewColumn: { Active: -1, Beside: -2 },
  // Real classes, because the code under test asks `input instanceof
  // TabInputCustom` — that check is what separates a tab bound to a document
  // (which carries a uri, so a plan tab can be identified) from a webview tab
  // (which carries only a viewType, and cannot be).
  TabInputCustom: class {
    constructor(
      public uri?: any,
      public viewType?: string,
    ) {}
  },
  TabInputWebview: class {
    constructor(public viewType?: string) {}
  },
};

const orig = (Module as any)._load;
(Module as any)._load = function (request: string) {
  if (request === 'vscode') return vscode;
  // eslint-disable-next-line prefer-rest-params
  return orig.apply(this, arguments);
};

/** Reset the scriptable stub between tests. */
export function reset(): void {
  vscode._quickPick = undefined;
  vscode._input = undefined;
  vscode._lastQuickPick = null;
  vscode._lastInput = null;
  vscode._driveQuickPick = undefined;
  vscode._lastCreatedQuickPick = null;
  vscode._commands = [];
  vscode._files = new Map<string, string>();
  vscode._statusBar = [];
  vscode.window.tabGroups = makeTabGroups();
}

/** The value the code last pushed into a `setContext` key, or undefined. */
export function contextKey(key: string): unknown {
  const calls = vscode._commands.filter(
    (c) => c.id === 'setContext' && c.args[0] === key,
  );
  return calls.length ? calls[calls.length - 1].args[1] : undefined;
}

/** A tab standing in for the built-in markdown preview bound to [uri]. */
export function previewTab(uri: any, viewType = 'vscode.markdown.preview.editor'): any {
  return {
    label: 'frx-plan.md',
    input: new vscode.TabInputCustom(uri, viewType),
    group: vscode.window.tabGroups._group,
    isActive: true,
  };
}
