// The one API a webview page has to the editor — see
// https://code.visualstudio.com/api/extension-guides/webview#passing-messages-from-a-webview-to-an-extension
//
// Declared here rather than taken from `@types/vscode-webview`: that package
// would be a dependency for one function's shape, and its `getState` returns
// `any` where this page knows what it stored — see `PageState`.

/** The editor's side of the webview, as the page sees it. */
interface WebviewApi {
  /** Send a message to the extension; it arrives on `webview.onDidReceiveMessage`. */
  postMessage(message: import('./picture').PageMessage): void;
  /** What `setState` last stored — kept across a hide and a refresh — or undefined. */
  getState(): import('./picture').PageState | undefined;
  setState(state: import('./picture').PageState): void;
}

/** Provided by the webview host; callable once per page. */
declare function acquireVsCodeApi(): WebviewApi;
