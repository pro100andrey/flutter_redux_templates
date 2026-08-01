// Parses `build_runner` output into findings for the Problems panel.
//
// build_runner (2.15+) reports a failing builder as a block:
//
//   E freezed on lib/redux/log_in/models/log_in_state.dart:
//     @Default cannot be used on non-optional parameters
//     package:business/redux/log_in/models/log_in_state.dart:8:30
//       ╷
//     8 │     @Default(1) required int broken,
//       ╵
//
// and ends every build cycle with `Built with …` / `Failed to build …`. This
// module is pure (no vscode import) so it is unit-testable with plain node;
// watch.ts maps the findings onto a DiagnosticCollection.
import * as fs from 'fs';
import * as path from 'path';

export interface BuildFinding {
  file: string | null;
  line: number;
  column: number;
  message: string;
  severity: 'error' | 'warning';
}

export class BuildLogParser {
  private _buffer = '';
  private _findings: BuildFinding[] = [];
  private _current: BuildFinding | null = null;
  private _currentHeaderPath = '';

  /**
   * @param root monorepo root
   * @param packages package dir names under root (for resolving the header's
   *   package-relative path when no `package:` location line follows)
   * @param onCycle called at every `Built with` / `Failed to build` boundary
   *   with that cycle's findings
   */
  constructor(
    private readonly root: string,
    private readonly packages: readonly string[],
    private readonly onCycle: (findings: BuildFinding[]) => void,
  ) {}

  /** Feed a raw output chunk (stdout or stderr). */
  feed(chunk: string | Buffer): void {
    this._buffer += chunk.toString();
    let nl: number;
    while ((nl = this._buffer.indexOf('\n')) >= 0) {
      const line = this._buffer.slice(0, nl).replace(/\r$/, '');
      this._buffer = this._buffer.slice(nl + 1);
      this._line(line);
    }
  }

  private _line(line: string): void {
    // End of a build cycle — success or failure — flush what we collected.
    // Checked first: build_runner indents these lines like everything else.
    if (/^\s*(Built with|Failed to build)/.test(line)) {
      this._push();
      const cycle = this._findings;
      this._findings = [];
      this.onCycle(cycle);
      return;
    }

    // A new failing-builder block: `E <builder> on <path>:` (W for warnings;
    // [SEVERE]/[WARNING] are the pre-2.x spellings).
    const head = line.match(/^(E|W|\[SEVERE\]|\[WARNING\])\s+\S+\s+on\s+(\S+?):?\s*$/);
    if (head) {
      this._push();
      this._current = {
        file: null,
        line: 1,
        column: 1,
        message: '',
        severity: head[1] === 'W' || head[1] === '[WARNING]' ? 'warning' : 'error',
      };
      this._currentHeaderPath = head[2];
      return;
    }

    if (!this._current) return;

    // A builder progress line (`  4s freezed on 36 inputs: …`) ends the block —
    // in this output even progress is indented, so indentation alone can't
    // delimit it.
    if (/^\s*\d+m?s\s/.test(line)) {
      this._push();
      return;
    }
    // Precise location: `package:<pkg>/<path>:<line>:<col>`.
    const loc = line.match(/package:(\w+)\/(\S+?):(\d+):(\d+)/);
    if (loc) {
      this._current.file = path.join(this.root, loc[1], 'lib', loc[2]);
      this._current.line = Number(loc[3]);
      this._current.column = Number(loc[4]);
      return;
    }
    const trimmed = line.trim();
    const isFrame =
      /^[╷╵│]/.test(trimmed) || /^\d+\s*│/.test(trimmed) || /^\^+$/.test(trimmed);
    if (trimmed && !isFrame && !this._current.message) {
      // First prose line after the header is the message; keep it single-line.
      this._current.message = trimmed;
    }
  }

  private _push(): void {
    const f = this._current;
    if (!f) return;
    this._current = null;
    // No `package:` location line — resolve the header's package-relative path
    // (`lib/…`) against the workspace packages instead.
    if (!f.file && this._currentHeaderPath) {
      for (const pkg of this.packages) {
        const candidate = path.join(this.root, pkg, this._currentHeaderPath);
        if (fs.existsSync(candidate)) {
          f.file = candidate;
          break;
        }
      }
    }
    this._currentHeaderPath = '';
    if (!f.message) f.message = 'build_runner reported a failure here.';
    this._findings.push(f);
  }
}
