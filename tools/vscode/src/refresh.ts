// The one place a refresh of the tree and the audit is started from.
//
// Four things asked for one independently — every command after it wrote, the
// folder watchers 800 ms after the same write landed on disk, `build_runner`'s
// output arriving file by file, and the doctor commands — and each started a
// `frx graph` and a `frx doctor` of its own whether or not the last pair had
// finished. A scaffold was two refreshes; a watch build cycle was one more; and
// nothing ever stopped an earlier one, so they overlapped and piled up.
//
// So a refresh is **single-flight**: asked for while one runs, it is not
// started again but marked due, and runs once more when the current one ends —
// however many times it was asked meanwhile, because one run after the last
// request sees everything those requests were about.

/** Runs [work] one at a time, coalescing requests that arrive while it runs. */
export class RefreshScheduler {
  private _running: Promise<void> | null = null;
  private _again = false;
  private _timer: NodeJS.Timeout | undefined;
  private _disposed = false;

  /**
   * @param _work the refresh itself; its failures are its own to report
   * @param _delayMs how long [soon] waits for a burst of events to end
   */
  constructor(
    private readonly _work: () => Promise<unknown>,
    private readonly _delayMs = 800,
  ) {}

  /**
   * Refresh now — or, when one is running, once more as soon as it ends.
   * Settles when the refresh that covers this request has.
   */
  now(): Promise<void> {
    clearTimeout(this._timer); // a pending [soon] is covered by this run
    if (this._disposed) return Promise.resolve();
    if (this._running) {
      this._again = true;
      return this._running;
    }
    const run = (async () => {
      do {
        this._again = false;
        try {
          await this._work();
        } catch {
          /* reported by the work itself; the next request tries again */
        }
      } while (this._again && !this._disposed);
    })();
    this._running = run.finally(() => (this._running = null));
    return this._running;
  }

  /** Refresh once a burst of file events has gone quiet for the delay. */
  soon(): void {
    if (this._disposed) return;
    clearTimeout(this._timer);
    this._timer = setTimeout(() => void this.now(), this._delayMs);
  }

  dispose(): void {
    this._disposed = true;
    clearTimeout(this._timer);
  }
}

/**
 * Whether [file] is `build_runner` output.
 *
 * A change to one says nothing the change to its source did not already say,
 * and a build cycle writes dozens: each one re-read the graph and re-ran the
 * audit. What codegen *does* change — a "missing part" finding cleared — is
 * picked up once per cycle instead, from the watch's own "Built with" line.
 */
export function isGenerated(file: string): boolean {
  return /\.(g|freezed|gr)\.dart$/.test(file);
}
