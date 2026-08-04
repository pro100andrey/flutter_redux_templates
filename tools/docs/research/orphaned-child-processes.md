# Stopping a child process from outliving its parent

Research notes for the orphaned `build_runner watch` problem. Every claim carries its
source inline. Where only a secondary source exists it is labelled as such. Where a
claim could not be verified, it says so.

**Dated:** 2026-08-04.
**Versions this was checked against:** Dart SDK 3.12.2 (stable, 2026-06-09) — the SDK on
this machine and the one `api.dart.dev` currently documents; `build_runner` 2.16.0
(published 2026-07-31, latest at time of writing); Linux man-pages 6.18 (2026-02-08);
Node.js docs v26.6.0; macOS (Darwin 25.5.0).

**Measurements marked "verified here"** were run on this machine (macOS arm64, Dart
3.12.2) during this research. They are reproducible; the scripts are trivial and are
described inline rather than committed.

---

## Part 1 — OS mechanisms

### The shape of the problem

POSIX does not promise that an orphan is reparented to pid 1. It says the parent process
id of the children of an exiting process "shall be set to the process ID of an
implementation-defined system process. That is, these processes shall be inherited by a
special system process"
([POSIX `_Exit()`](https://pubs.opengroup.org/onlinepubs/9699919799/functions/_Exit.html)).
Linux makes that latitude concrete with subreapers (below). This is the root of the
"orphan == ppid 1" mistake.

### Linux: `prctl(PR_SET_PDEATHSIG)`

**Platform:** Linux only, since kernel 2.1.57
([PR_SET_PDEATHSIG(2const)](https://man7.org/linux/man-pages/man2/PR_SET_PDEATHSIG.2const.html),
man-pages 6.18).

**Guarantees:** "Set the parent-death signal of the calling process to *sig*." When the
parent dies, the kernel delivers *sig* to the child. No cooperation from the parent is
needed and it survives the parent being `SIGKILL`ed, because the kernel does the sending.

**Does NOT guarantee, and the traps:**

- **The child sets it on itself.** The parent cannot set it on the child. This is the
  single most important property for our case: it must be called *after* `fork()` and
  *before* `execve()`, or by the child program's own code. A parent that only has
  `Process.start` cannot install it.
- **The race.** "If the parent thread and all ancestor subreapers have already terminated
  by the time of the `PR_SET_PDEATHSIG` operation, then no parent-death signal is sent to
  the caller." The standard mitigation is to re-check the parent (compare `getppid()` to
  the value captured before the call) immediately after `prctl` and exit if it changed.
- **"Parent" means the *thread* that created the process**, not the process: "the signal
  will be sent when that thread terminates (via, for example, `pthread_exit(3)`), rather
  than after all of the threads in the parent process terminate." For a multithreaded
  parent — and the Dart VM is multithreaded — this fires when the *specific spawning
  thread* exits, which may be earlier than process exit.
- **It is cleared** for the child of a `fork(2)`; when executing a set-user-ID or
  set-group-ID binary or one with associated capabilities; and on changes to the effective
  uid/gid or filesystem uid/gid.
- It is a *signal*, so a child that catches or blocks it is unaffected. Using `SIGKILL` as
  *sig* removes that escape ([signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html):
  "The signals SIGKILL and SIGSTOP cannot be caught, blocked, or ignored").

### Linux: `PR_SET_CHILD_SUBREAPER`, and why "ppid == 1" is false

[PR_SET_CHILD_SUBREAPER(2const)](https://man7.org/linux/man-pages/man2/PR_SET_CHILD_SUBREAPER.2const.html)
(Linux 3.4): "A subreaper fulfills the role of `init(1)` for its descendant processes.
When a process becomes orphaned (i.e., its immediate parent terminates), then that process
will be reparented to the nearest still living ancestor subreaper." The attribute "is not
inherited by children created by `fork(2)` and `clone(2)`".

**`systemd --user` is such a subreaper — verified from source.** `systemd`'s manager
startup calls `make_reaper_process(true)`
([src/core/main.c](https://github.com/systemd/systemd/blob/main/src/core/main.c), around
line 2812), and `make_reaper_process` returns early only when `getpid_cached() == 1`,
otherwise calling `prctl_safe(PR_SET_CHILD_SUBREAPER, b, 0, 0, 0)`
([src/basic/process-util.c](https://github.com/systemd/systemd/blob/main/src/basic/process-util.c),
line 1999). A `systemd --user` instance runs as `user@UID.service` with a pid that is not
1, so it takes the subreaper branch. Under it, an orphan's ppid becomes the user
manager's pid — **not 1**.

**Is "compare the session id of the process against its parent's" sound?** This is what
`tools/lib/src/engine/build_step.dart` (`_isOrphan`) does. Assessment:

*The reasoning is correct on Linux.* systemd calls `setsid()` for every service it starts
unless `same_pgrp` is set — "if (!context->same_pgrp && setsid() < 0)"
([src/core/exec-invoke.c](https://github.com/systemd/systemd/blob/main/src/core/exec-invoke.c),
around line 5306). So `systemd --user` is in its own session, distinct from the terminal
session the watch inherited. Session membership does not change on reparenting, so after
the launcher dies the watch keeps the old session id while its new parent has a different
one. The test correctly detects the orphan without asking what it was reparented *to*.

*But it does nothing on macOS.* Verified here: `ps -o sess=` on macOS prints `0` for every
visible process, including the shell and pid 1. The reason is in Apple's `ps` source — the
`sess` keyword is declared as
`{"sess", "SESS", NULL, 0, evar, NULL, 6, EOFF(e_sess), KPTR, "lx"}`
([apple-oss-distributions/adv_cmds, `ps/keyword.c`](https://github.com/apple-oss-distributions/adv_cmds/blob/main/ps/keyword.c)),
i.e. it prints the *kernel session pointer* (`KPTR`, format `%lx`), which is redacted to
zero for an unprivileged caller. Linux's `ps` is different: procps-ng documents `sess` as
"session ID or, equivalently, the process ID of the session leader. (alias `session`,
`sid`)" ([ps(1)](https://man7.org/linux/man-pages/man1/ps.1.html), procps-ng, 2025-04-23),
and macOS `ps` has no `sid` keyword at all (verified here: `ps: sid: keyword not found`).
So on macOS the comparison is always `"0" != "0"` → false, and the detector falls through
to its `ppid <= 1` and "parent absent from the table" fallbacks. Those happen to be
*correct* on macOS — verified here that `SIGKILL`ing a parent reparents its child to ppid
1 — because macOS has no subreaper mechanism. The check is sound on both platforms, but on
macOS it is the fallback doing the work, not the session comparison.

*Two ways the session test can still be wrong:*

- **False positive (worse).** A watch deliberately placed in its own session by a live
  parent reads as an orphan. Dart's `ProcessStartMode.detached` calls `setsid()`
  (see Part 2), as does Node's `spawn(…, {detached: true})` — "the child process will be
  made the leader of a new process group and session"
  ([Node.js child_process docs, v26.6.0](https://nodejs.org/api/child_process.html)). If
  either call site ever detaches the watch, `frx` would classify a live watch as dead and
  build over it.
- **False negative.** A subreaper living *inside the same session* as the watch (a
  supervisor or shell in the terminal session that called `PR_SET_CHILD_SUBREAPER`) would
  adopt the orphan without changing the session, and the test reads "live".

*Unverified:* whether a session id can be recycled onto an unrelated process while the
session still has members. I did not find a definitive statement in the man-pages or POSIX
text I read, and did not test it.

### macOS: no PDEATHSIG; `kqueue` + `EVFILT_PROC`/`NOTE_EXIT`

**There is no `prctl` on macOS.** Verified here: `man -w 2 prctl` returns "No manual entry
for prctl", while `man -w 2 setsid` resolves to the Xcode SDK man pages — so the man path
is present and the entry genuinely does not exist. I found no Apple-documented equivalent.

The macOS substitute is `kqueue`
([kqueue(2), macOS 12 man page](https://keith.github.io/xcode-man-pages/kqueue.2.html) —
note this is a mirror of Apple's shipped man pages, not an Apple-hosted URL; Apple's own
online copy is in the deprecated documentation archive):

- `EVFILT_PROC` "takes the process ID to monitor as the identifier".
- `NOTE_EXIT` — "The process has exited." Also `NOTE_FORK`, `NOTE_EXEC`, `NOTE_SIGNAL`,
  and `NOTE_EXITSTATUS` ("Valid only on child processes").
- **It can watch a process you did not spawn:** "If a process can normally see another
  process, it can attach an event to it." Only `NOTE_EXITSTATUS`/`NOTE_REAP` are restricted
  to children.
- "The queue is not inherited by a child created with `fork(2)`."

**What it does NOT give you:** it is a *notification*, not an enforcement. Something must
be alive and running code to receive the event and act. It inverts the responsibility —
the child watches the parent — which means it is only usable if you control the child's
code. It also has the same registration race as PDEATHSIG: if the target has already
exited when you register, there is nothing to watch. The man page text I read does not
document the errno for that case; I did not verify it experimentally.

### Windows: Job Objects — the one OS that solves it

[Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
(Microsoft Learn, doc updated 2025-07-14):

> if the job has the JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE flag specified, closing the last
> job object handle terminates all associated processes and then destroys the job object
> itself.

and, from
[JOBOBJECT_BASIC_LIMIT_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_limit_information),
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` is `0x00002000` and "requires use of a
`JOBOBJECT_EXTENDED_LIMIT_INFORMATION` structure".

**Why this is the strong solution:** handles are closed by the kernel when a process dies,
*however* it dies. A parent that is `TerminateProcess`d without running a line of cleanup
code still drops its job handle, and the kernel then kills the whole job. No cooperation
from the child, no race window after assignment, no polling. It is the only mechanism here
that is both enforced by the kernel and installable by the parent.

**Caveats:**

- "After a process is associated with a job, the association cannot be broken."
- Children inherit job membership by default, but a process can escape if the job sets
  `JOB_OBJECT_LIMIT_BREAKAWAY_OK` (with `CREATE_BREAKAWAY_FROM_JOB`) or
  `JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK`. Set neither and the whole tree is captured — at
  the cost that a child calling `AssignProcessToJobObject` itself will fail.
- Nested jobs require Windows 8 / Server 2012. Before that "a process can be associated
  with only one job", so a child already in someone else's job (a CI agent's, a terminal's)
  cannot be added to yours.
- There is a race between `CreateProcess` and `AssignProcessToJobObject` unless the process
  is created suspended; the Learn page does not discuss it, and I did not verify how the
  common wrappers handle it.

### The portable pipe/EOF idiom

Parent creates a pipe, keeps the write end, passes the read end to the child; the child
reads and exits when the read returns EOF. The kernel guarantee is in
[pipe(7)](https://man7.org/linux/man-pages/man7/pipe.7.html): "If all file descriptors
referring to the write end of a pipe have been closed, then an attempt to `read(2)` from
the pipe will see end-of-file (`read(2)` will return 0)." The parent's fds are closed by
the kernel on death regardless of cause, so this survives `SIGKILL` of the parent.

**It requires the child's cooperation, unconditionally.** The child must be written to read
that fd and exit on EOF. This is a protocol between two programs you control, not something
you can impose on an arbitrary binary. `build_runner` does not implement it (Part 3).

### Process groups, sessions, and what Ctrl-C actually does

- **Ctrl-C is not sent to your child by your process.** The terminal driver does it: the
  INTR character "Generates a SIGINT signal which is sent to all processes in the
  foreground process group for which the terminal is the controlling terminal"
  ([POSIX XBD §11.1.9](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap11.html)).
  Same for SIGQUIT (QUIT) and SIGTSTP (SUSP).
- **This is why the terminal case works "by accident".** Verified here with Dart 3.12.2: a
  child started with `ProcessStartMode.inheritStdio` keeps the parent's process group id
  (parent pid 8206 in pgid 8203; child pid 8256 also in pgid 8203). The tty therefore
  delivers SIGINT to the parent *and* the child independently. `frx watch` installs no
  signal handlers and forwards nothing — and does not need to, in a terminal. Take the
  terminal away (an IDE-spawned process, a background job, a different process group) and
  the mechanism that was doing the work is gone.
- **SIGHUP.** On modem disconnect / terminal close, "the SIGHUP signal shall be sent to the
  controlling process for which the terminal is the controlling terminal" (POSIX
  §11.1.10) — the *controlling process*, i.e. the session leader, typically the shell, not
  the whole tree. Separately, when a controlling process terminates, "the SIGHUP signal
  shall be sent to each process in the foreground process group of the controlling
  terminal" ([POSIX `_Exit()`](https://pubs.opengroup.org/onlinepubs/9699919799/functions/_Exit.html)).
  Background jobs get nothing from the kernel; whether they are hung up is a shell policy.
  SIGHUP's default disposition is terminate ([signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html)).
- Signalling a whole group is `kill(-pgid, sig)`; see Part 2 for whether Dart can do it.

### Summary table

| Mechanism | Platform | Installed by | Survives parent SIGKILL | Needs child cooperation |
|---|---|---|---|---|
| `PR_SET_PDEATHSIG` | Linux ≥ 2.1.57 | the **child**, on itself | yes | yes (must call it) |
| `kqueue` `NOTE_EXIT` | macOS/BSD | the watcher | yes (event still fires) | yes (child must watch + act) |
| Job object + `KILL_ON_JOB_CLOSE` | Windows (nested: ≥ Win8) | the **parent** | **yes** | **no** |
| Pipe/EOF | any POSIX + Windows | parent creates, child reads | yes | yes |
| Process group + `kill(-pgid)` | POSIX | parent (or tty) | **no** — needs a live killer | no |
| Poll parent pid (`kill(pid,0)`) | any | the child or a helper | yes | yes (must poll) |
| Idle timeout / self-expiry | any | the child | yes | yes |

---

## Part 2 — What is reachable from Dart

Sources for this part are the Dart SDK itself: `sdk/lib/io/process.dart` and
`runtime/bin/process_*.cc` on `dart-lang/sdk` `main`, plus measurements on Dart 3.12.2.

### `ProcessSignal` — what can be watched

From the `watch()` doc comment in
[sdk/lib/io/process.dart](https://github.com/dart-lang/sdk/blob/main/sdk/lib/io/process.dart):

> The following [ProcessSignal]s can be listened to:
> * [ProcessSignal.sighup].
> * [ProcessSignal.sigint]. Signal sent by e.g. CTRL-C.
> * [ProcessSignal.sigterm]. Not available on Windows.
> * [ProcessSignal.sigusr1]. Not available on Windows.
> * [ProcessSignal.sigusr2]. Not available on Windows.
> * [ProcessSignal.sigwinch]. Not available on Windows.
>
> Other signals are disallowed, as they may be used by the VM.

So: **SIGHUP and SIGINT everywhere; SIGTERM only off Windows.** SIGKILL is not watchable —
by Dart's rule and, more fundamentally, by the kernel's
([signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html)).

### `ProcessStartMode` and detaching

Values and docs, verbatim from the same file:

- `normal` — "Normal child process." Docs on `start`: "a child process will be started with
  `stdin`, `stdout` and `stderr` connected to its parent. The parent process will not exit
  so long as the child is running, unless [exit] is called by the parent."
- `inheritStdio` — "Stdio handles are inherited by the child process." (What `frx watch`
  uses.)
- `detached` — "Detached child process with no open communication channel." And: "A
  detached process has no connection to its parent, and can keep running on its own when
  the parent dies. The only information available from a detached process is its `pid`."
- `detachedWithStdio` — "Detached child process with stdin, stdout and stderr still open
  for communication with the child."

**What "detached" does at the syscall level — verified from the VM source.** Both
[`runtime/bin/process_linux.cc`](https://github.com/dart-lang/sdk/blob/main/runtime/bin/process_linux.cc)
(line ~599) and
[`runtime/bin/process_macos.cc`](https://github.com/dart-lang/sdk/blob/main/runtime/bin/process_macos.cc)
implement `ExecDetachedProcess` as a **double fork with `setsid()`** in the intermediate
("Fork once more to start a new session … `setsid()`"). Neither file contains `prctl`,
`PR_SET_PDEATHSIG`, or `setpgid` — I grepped for all of them. `process_fuchsia.cc` supports
only `kNormal`.

**Consequence, verified here (this is a real trap):** for a detached child, the pid Dart
reports is **not** the process group id. Measured on Dart 3.12.2 / macOS:

```
Dart-reported pid=10046   actual pgid=10045   (equal? false)
```

The group leader is the intermediate process, which `_Exit(0)`s immediately, so the group
id names a dead pid. `Process.killPid(-det.pid, …)` therefore fails (`false`, i.e. `kill`
returned ESRCH) while `Process.killPid(-pgid, …)` succeeds. There is **no Dart API that
returns the pgid** — I had to shell out to `ps -o pgid= -p <pid>` to get it.

**There is no other way to create a process group or detach from Dart.** `Process.start`'s
full parameter list is `workingDirectory`, `environment`, `includeParentEnvironment`,
`runInShell`, `mode` — no pre-exec hook, no `setpgid`, no fd-passing. This is decisive:
**Dart cannot run `prctl(PR_SET_PDEATHSIG)` in the child between `fork` and `exec`,** which
is the only place it could be installed on a child you do not own the code of.

### `Process.killPid` — undocumented process-group support

Doc: "Where possible, sends the [signal] to the process with id [pid]. This includes Linux
and OS X. The default signal is [ProcessSignal.sigterm]… On platforms without signal
support, including Windows, the call just terminates the process with id [pid] in a
platform specific way, and the [signal] parameter is ignored."

The native path does **no validation**: `Process_KillPid` reads the intptr and calls
`Process::Kill(pid, signal)`
([runtime/bin/process.cc](https://github.com/dart-lang/sdk/blob/main/runtime/bin/process.cc),
line 253), and on POSIX `Process::Kill` is literally
`return (TEMP_FAILURE_RETRY(kill(id, signal)) != -1);`
([process_linux.cc](https://github.com/dart-lang/sdk/blob/main/runtime/bin/process_linux.cc),
line 985). So a **negative pid reaches `kill(2)` and signals a process group**.

**Verified here** on Dart 3.12.2 / macOS: a detached `sh -c 'sleep 90 & sleep 90'` produced
a three-member group; `Process.killPid(-pgid, ProcessSignal.sigterm)` returned `true` and
all three members died. This works, but it is an undocumented consequence of the
pass-through, not a supported API — and it does not help you *learn* the pgid.

On Windows, `Process::Kill` ignores the signal entirely and calls
`TerminateProcess(process_handle, -1)`
([process_win.cc](https://github.com/dart-lang/sdk/blob/main/runtime/bin/process_win.cc),
line 1149), looking the handle up in its own process list first and falling back to
`OpenProcess`. There is no tree kill.

### Does Dart expose the parent pid?

**No.** `dart:io` has exactly one pid accessor: `int get pid => _ProcessUtils._pid(null);`
— "Returns the PID of the current process" (process.dart line 109). There is no `ppid`
anywhere in `dart:io`; I grepped the file for "parent" and every hit is prose about the
parent *process* in doc comments. Getting a ppid from Dart means shelling out to
`ps -o ppid= -p <pid>` (which is what `tools/lib/src/engine/build_step.dart` does) or FFI.

### FFI reachability and cost

`dart:ffi` can call any of these in the *calling* process. The cost differs sharply per
mechanism:

- **`prctl` (Linux):** reachable —
  `DynamicLibrary.process().lookupFunction<...>('prctl')` — but **useless for the parent
  case**, because PDEATHSIG must be set by the child and Dart has no pre-exec hook. It
  *is* usable in the reverse direction: a Dart process can set PDEATHSIG **on itself** so
  that it dies with *its* parent. That is the one shape where FFI genuinely solves
  something here, and it is Linux-only.
- **`kqueue` (macOS):** reachable — `kqueue()`/`kevent()` are in libSystem. But `kevent()`
  blocks, so it needs a helper isolate or a timeout loop, and it again only helps in the
  "child watches parent" direction. Moderate cost.
- **Job objects (Windows):** reachable, and the only one worth the effort for the *parent*
  direction. The [`win32` package](https://pub.dev/packages/win32) v6.3.0 already exposes
  [`CreateJobObject`](https://pub.dev/documentation/win32/latest/win32/CreateJobObject.html)
  (`Win32Result<HANDLE> CreateJobObject(Pointer<SECURITY_ATTRIBUTES>?, PCWSTR?)`) and
  [`AssignProcessToJobObject`](https://pub.dev/documentation/win32/latest/win32/AssignProcessToJobObject.html)
  (`Win32Result<bool> AssignProcessToJobObject(HANDLE hJob, HANDLE hProcess)`). The gap:
  `AssignProcessToJobObject` needs a process **HANDLE** and `dart:io` gives you only a pid,
  so you would additionally `OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, …)` via
  FFI. I did **not** verify `SetInformationJobObject` is exposed, and I did not build or
  test this — treat the Windows-from-Dart path as plausible but unproven.

**No published Dart package does any of this.** pub.dev searches for `prctl`, for
`job object process kill tree`, and for `process parent watchdog supervisor` returned
nothing relevant (the only `prctl` hit is `playerctl`, a media-control plugin). If such a
package exists it is not discoverable by those terms.

### What a pure-Dart supervisor can and cannot do

**Can:**
- Watch SIGINT, SIGTERM (non-Windows) and SIGHUP and kill the child before exiting.
- Kill a process group with `Process.killPid(-pgid)` — if it can obtain the pgid by
  shelling out.
- Poll whether another pid is alive — **but only by shelling out**. The standard probe is
  `kill(pid, 0)`, and `ProcessSignal` has a private constructor (`ProcessSignal._`) with no
  signal-0 constant among its 30 values (process.dart line 588 ff.), so `Process.killPid`
  cannot express it. `kill -0` or `ps -p` in a subprocess is the only route.
- Detect and report orphans after the fact — what `frx doctor` already does.

**Cannot:**
- **Run any code when it is `SIGKILL`ed.** This is not a Dart limitation, it is the kernel:
  "The signals SIGKILL and SIGSTOP cannot be caught, blocked, or ignored"
  ([signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html)). A supervisor that
  exists only in the parent covers `Ctrl-C`, `kill`, and clean shutdown. It covers nothing
  when the parent is `kill -9`'d, OOM-killed, or when the machine loses power. **Every
  design that puts the cleanup logic in the parent has this hole, and it cannot be closed
  from the parent side.** Closing it requires either the kernel doing the killing (job
  object, PDEATHSIG) or the child noticing (poll, pipe EOF, kqueue, idle timeout).
- Install PDEATHSIG on a child.
- Learn its own parent's pid, or a child's process group, without a subprocess.

---

## Part 3 — `build_runner` specifically

### `build_runner stop`: an advisory file lock plus a `.requested` marker

Verified against `dart-lang/build` `master` at commit `75433a4` (2026-08-04). The
mechanism is **not** a signal, socket, or pid file.

`StopCommand` is a no-op — its whole body returns success
([`build_runner/lib/src/commands/stop_command.dart`](https://github.com/dart-lang/build/blob/master/build_runner/lib/src/commands/stop_command.dart)),
with the comment: "The lock is taken on startup in `build_runner.dart`, any other running
`build_runner` was already notified and has closed."

The work is in
[`build_runner/lib/src/bootstrap/build_process_lock.dart`](https://github.com/dart-lang/build/blob/master/build_runner/lib/src/bootstrap/build_process_lock.dart).
Every command except `daemon` calls `takeLock()` at startup. Sequence:

1. `tryLock()` on the lock file fails because the watch holds an OS advisory lock
   (`RandomAccessFile.lockSync`).
2. The failure path writes `File('$path.requested').writeAsStringSync('', flush: true)`.
   The source comment: *"Write even if the file already exists to trigger a file watch
   event in the process that has the lock."*
3. The running watch has registered `setLockRequestCallback`
   ([`commands/watch/watcher.dart`](https://github.com/dart-lang/build/blob/master/build_runner/lib/src/commands/watch/watcher.dart)),
   which runs a `package:watcher` `Watcher` over the lock directory and fires on any path
   ending in `.requested`. It finishes the in-flight build, prints **"Exiting as requested
   by another build_runner process."**, and exits.
4. `stop` retries the lock every 100 ms, acquires it, deletes the `.requested` markers, and
   returns 0.

**Lock file names** (same file): `build_runner.lock` and `build_runner.workspace.lock`, at
`<packagePath>/.dart_tool/build/lock/` and `<workspacePath>/.dart_tool/build/lock/`
respectively. Note **"workspace" in the filename does not come from `--workspace`** —
`workspacePath` is read from `.dart_tool/pub/workspace_ref.json`
([`build_plan/build_paths.dart`](https://github.com/dart-lang/build/blob/master/build_runner/lib/src/build_plan/build_paths.dart)).
The `--workspace` flag selects *granularity*: with it, an exclusive lock on the workspace
file only; without it, a shared lock on the workspace file plus an exclusive lock on the
package file. This repo has a `workspace:` key in its root `pubspec.yaml` and `frx watch`
passes `--workspace` by default (`tools/lib/src/commands/watch_command.dart`), which is why
only `build_runner.workspace.lock` appears here.

**Scoping is per-project by construction.** Both paths are rooted at the package/workspace
directory found by walking up from the cwd; there is no global registry and no `/tmp`
state. This matches the observation that `stop --workspace` did not touch another project's
watch.

**Stale locks need no handling and get none.** The lock is an OS advisory lock, which the
kernel releases when the holder dies however it dies. File *existence* is never tested —
only lockability — so a leftover zero-byte `build_runner.workspace.lock` (there is one in
this repo right now) is inert. `dart-lang/build`'s own integration test kills a lock holder
and asserts the next one acquires immediately
([`test/integration_tests/build_process_lock_test.dart`](https://github.com/dart-lang/build/blob/master/build_runner/test/integration_tests/build_process_lock_test.dart)).
The only state that can go stale is the `.requested` marker, mitigated by clearing it after
every successful `takeLock()`.

**This explains the observed behaviour cleanly:** `stop` works on a watch whose parent is
long dead because it never asks who the parent is. It talks to the *process holding the
lock*, via the filesystem.

### Signals and parent-death inside `build_runner watch`

**`watch` installs exactly one handler: SIGINT, on all platforms**
([`commands/watch_command.dart`](https://github.com/dart-lang/build/blob/master/build_runner/lib/src/commands/watch_command.dart)):
`terminateEventStream ??= ProcessSignal.sigint.watch();` — first Ctrl-C drains gracefully,
second calls `exit(2)`.

**It does not watch SIGTERM or SIGHUP.** So `kill <pid>` terminates it outright with no
graceful drain, and terminal-close SIGHUP is likewise unhandled (default disposition:
terminate). The only SIGTERM handling in the package is in `test_command.dart`, and only to
print a message while a spawned test process finishes.

**It does not exit on stdin EOF.** stdin is read once, by the child build script, to
receive a serialized state blob up to a `` sentinel; the subscription is deliberately
never closed, citing [dart-lang/sdk#61571](https://github.com/dart-lang/sdk/issues/61571)
("the stdin subscription can't be closed, that would cause a crash on Windows"). So the
pipe/EOF idiom is not implemented.

### build_runner already ships a poll-the-parent reaper — but it protects the wrong link

This is the most directly applicable finding in this document.
[`build_runner/lib/src/bootstrap/processes.dart`](https://github.com/dart-lang/build/blob/master/build_runner/lib/src/bootstrap/processes.dart)
spawns a shell alongside every child process it starts. Verbatim, lines 176–204:

```dart
/// Starts a script that waits until [parentPid] exits then kills [childPid].
static Future<Process?> _startReaper({
  required int parentPid,
  required int childPid,
}) async {
  try {
    if (Platform.isWindows) {
      return await Process.start('powershell', [
        ...Powershell.baseArgs,
        '-Command',
        'Wait-Process -Id $parentPid; Stop-Process -Id $childPid -Force',
      ]);
    } else {
      // The default shell on MacOS is zsh, but it also has an old version of
      // bash that is sufficient for this script.
      return await Process.start('bash', [
        '-c',
        'while kill -0 $parentPid; do sleep 1; done; kill -9 $childPid',
      ], mode: ProcessStartMode.detachedWithStdio);
    }
  } on ProcessException catch (_) {
    // Give up if `powershell` or `bash` is missing from PATH.
    return null;
  }
}
```

Called as `_startReaper(parentPid: pid, childPid: result.pid)` where `pid` is `dart:io`'s
**own** process id (line 167), with `result.exitCode.then((_) => reaper.kill())` to reap the
reaper if the child exits first.

**Read this carefully: the "parent" it guards is `build_runner` itself.** It ensures the
inner build-script process dies if the outer `dart run build_runner` process is killed. It
does **not** watch `build_runner`'s own parent. So when `frx watch` is `SIGKILL`ed, the
outer `build_runner` survives — nothing is watching for that — and its reaper faithfully
keeps the inner process alive alongside it. This is exactly the observed behaviour.

Observations on the pattern itself, worth carrying into any adaptation:
- It is **pure Dart + a shell one-liner**, no FFI, and it covers the parent-`SIGKILL` case,
  because the reaper is a separate process that survives.
- 1-second polling granularity; one extra `bash` + `sleep` process per guarded child.
- **PID reuse is unhandled.** If `parentPid` is recycled, `kill -0` keeps succeeding and the
  reaper never fires; if `childPid` is recycled, it kills an innocent process. On a
  long-lived watch this is a real if unlikely hazard.
- Inconsistency: the POSIX branch passes `ProcessStartMode.detachedWithStdio`, the Windows
  branch does not pass a mode at all (so `normal`).

### Issue tracker

Searched `dart-lang/build` via the GitHub API — every issue since 2026-04-01 plus keyword
searches for lock / zombie / orphaned / stale lock / hung / "watch does not exit" /
"build_runner stop" / "another build_runner". The locking feature is only ~3 months old
(2.14.0, 2026-04-22), so the tracker is thin. Relevant issues:

| Issue | Title | State | Notes |
|---|---|---|---|
| [#4987](https://github.com/dart-lang/build/issues/4987) | Agents keep killing watch mode for the sake of running build | **open** (2026-06-18) | Exactly our scenario, filed by rrousselGit. Maintainer davidmorgan confirms the design: "The `2.14.0` release added locking: when you run `build` it will 'request' the lock from `watch`, causing the `watch` to close…" and "There is also a new `dart run build_runner stop` that just grabs the lock, causing `watch` to exit." A `--no-request-lock` flag is floated. Unresolved. |
| [#4986](https://github.com/dart-lang/build/issues/4986) | Race condition in watch mode when changing the source of a builder | closed 2026-07-07 | Second rapid change ignored, cache wrongly fresh. Tangential. |
| [#3770](https://github.com/dart-lang/build/issues/3770) | `build_runner test` does not exit after test process exits | closed 2024-11-12 | Tangential. |
| [#5052](https://github.com/dart-lang/build/issues/5052) | [build_daemon] daemon exits silently with code 0 (MissingPortFile) | **open** (2026-08-01) | Different subsystem; `daemon` has its own locking and is exempt from the `stop` lock. |

**No issue at all was found about orphaned / zombie `watch` processes.** That appears to be
genuinely unreported upstream.

### Version dating — the premise needs a correction

The `--delete-conflicting-outputs` removal was **not** in 2.15.1. Verified by diffing the
`removedOptions` const across published archives (2.13.1 / 2.14.0 / 2.14.1 / 2.15.0 /
2.15.1 / 2.15.2 / 2.15.3 / 2.16.0): the const does not exist in 2.14.1 or earlier and
first appears in **2.15.0, published 2026-04-30**, already containing the
delete-files option, unchanged through 2.16.0. 2.15.1 (2026-07-08) changed nothing here.

There are two distinct dates behind the confusion
([CHANGELOG](https://github.com/dart-lang/build/blob/master/build_runner/CHANGELOG.md),
[pub.dev versions](https://pub.dev/packages/build_runner/versions)):

- **2.7.0 (2025-08-15)** — the flag became a silent no-op: "Remove interactive prompts for
  whether to delete files. / Ignore `-d` flag: always delete files as if `-d` was passed."
  Source from 2.7.0 to 2.14.1 carries `// No longer does anything, but accept so old usage
  does not fail.`
- **2.15.0 (2026-04-30)** — it started *warning*: "Removed options can still be passed, they
  will be ignored with a warning."

The warning text comes from `build_runner.dart`: `'These options have been removed and were
ignored: '`. The full removed list is `delete-conflicting-outputs`, `fail-on-severe`,
`log-performance`, `low-resources-mode`, `track-performance`. Note the 2.15.0 changelog
names only the last three; `--delete-conflicting-outputs` and `--fail-on-severe` were added
to `removedOptions` without a dedicated changelog line.

**Version timeline for dating:** 2.14.0 → 2026-04-22, 2.14.1 → 2026-04-24, 2.15.0 →
2026-04-30, 2.15.1 → 2026-07-08, 2.15.2 → 2026-07-13, 2.15.3 → 2026-07-27, **2.16.0 →
2026-07-31 (latest)**. Separately worth knowing: 2.16.0 changed default output behaviour —
hand-modified generated files are now always overwritten, with `--keep-modified-outputs`
restoring the old behaviour.

### Lock-contention message text

There is no "another build_runner is running" string. The two real strings:

| Text | Printed by |
|---|---|
| `Waiting for already-running build_runner.` | the **blocked** process, once, before its retry loop (`build_process_lock.dart`) |
| `Exiting as requested by another build_runner process.` | the **yielding watch**, as it shuts down (`commands/watch/watcher.dart`) |

(`daemon_command.dart` separately prints `Daemon is already running.` — different subsystem.)

### What Dart-Code (the VS Code Dart/Flutter extension) does

Read at `master` commit
[`160f4eca`](https://github.com/Dart-Code/Dart-Code/commit/160f4eca2da47e7b69ec5ed1fb5e5dec1606e296)
(2026-08-03), `package.json` version `3.142.0-dev`.

**Spawning: no detach, no process group.** Everything funnels through `safeSpawn` in
[`src/shared/processes.ts`](https://github.com/Dart-Code/Dart-Code/blob/master/src/shared/processes.ts).
Verified verbatim — the entire option set is `cwd` and `env`:

```ts
return child_process.spawn(binPath, args, { cwd: workingDirectory, env: customEnv }) satisfies SpawnedProcess;
```

The only variant is Windows `.bat` files, which get `shell: true`, and the comment there is
explicitly about kill reliability: *"Try to limit when we use this, because terminating a
shell might not terminate the spawned process, so not using shell-execute may improve
reliability of terminating processes."* No `detached`, so **no new process group is ever
created**.

**Killing: direct child only.** `StdIOService.dispose()`
([`src/shared/services/stdio_service.ts`](https://github.com/Dart-Code/Dart-Code/blob/master/src/shared/services/stdio_service.ts))
loops a hand-curated `additionalPidsToTerminate` list calling `process.kill(pid)`, then
`this.process.kill()` — plain SIGTERM to the direct child. That PID list is populated from
daemon messages (e.g. `flutter_daemon.ts` pushes `e.pid` from an app-start event): an
explicit, best-effort substitute for a real tree kill. Verified negatives across `src/`:
no `tree-kill`, no `taskkill` in product code, no negative-PID process-group kill, no job
objects.

**`deactivate()`** (`src/extension/extension.ts`) disposes the analyzer and shuts the
Flutter daemon down inside `Promise.allSettled`, racing a `daemon.shutdown` request against
process exit so VS Code's own exit does not hang
([issue #6015](https://github.com/Dart-Code/Dart-Code/issues/6015)). Orderly — and it only
runs on a graceful shutdown.

**The crash case: verified negative.** Greps for `ppid`, watchdog patterns, and
parent-death detection return zero hits. The word "orphan" appears once in the whole
codebase and refers to orphaned DevTools *views*. The maintainer states the position in
[#5155](https://github.com/Dart-Code/Dart-Code/issues/5155): after auditing the sync
disposal path, on the remaining reports — *"I wonder if maybe the extension host crashed or
became unresponsive"*. The crash case is acknowledged, with no mitigation proposed.

Orphan-related issues, all closed:
[#6042](https://github.com/Dart-Code/Dart-Code/issues/6042) (orphaned `lldb`, 2026-04-23),
[#5691](https://github.com/Dart-Code/Dart-Code/issues/5691) (Widget Preview leaks processes,
2025-09-08),
[#5155](https://github.com/Dart-Code/Dart-Code/issues/5155) (processes left orphaned after
IDE closed, 2024-06-25),
[#5084](https://github.com/Dart-Code/Dart-Code/issues/5084) (2024-04-26),
[#5018](https://github.com/Dart-Code/Dart-Code/issues/5018) (the design record for the
shell caveat — "This may reduce the chances of leaving orphaned processes around"),
[#4690](https://github.com/Dart-Code/Dart-Code/issues/4690),
[#4438](https://github.com/Dart-Code/Dart-Code/issues/4438),
[#1140](https://github.com/Dart-Code/Dart-Code/issues/1140) (2018).

### What the IntelliJ / Android Studio plugins do

**Caveat: the JetBrains Dart plugin is no longer open source.** It was removed from the
monorepo on 2026-06-04
([commit `4bb2408`](https://github.com/JetBrains/intellij-plugins/commit/4bb240841f),
"IDEA-388683 Remove Dart plugin source code from the monorepo"), and
`JetBrains/intellij-plugins/Dart` now 404s. Findings below are from the **last open
commit** and may not reflect shipping code.

**flutter-intellij does have a real tree kill.** It uses `ColoredProcessHandler`, and for
long-running processes
[`MostlySilentColoredProcessHandler`](https://github.com/flutter/flutter-intellij/blob/master/src/io/flutter/utils/MostlySilentColoredProcessHandler.java),
which overrides `doDestroyProcess()` to call
`UnixProcessManager.sendSigIntToProcessTree(process)`. The platform backs this up:
[`OSProcessHandler`](https://github.com/JetBrains/intellij-community/blob/master/platform/platform-util-io/src/com/intellij/execution/process/OSProcessHandler.java)
defaults `myDestroyRecursively` to **true** and calls `OSProcessUtil.killProcessTree`, with
the comment "such behaviour is better than default Java one, which doesn't kill children
processes". `KillableProcessHandler` implements soft-kill — "On Unix, graceful termination
corresponds to sending SIGINT signal. On Windows, graceful termination executes
GenerateConsoleCtrlEvent under the hood." This is materially better than Dart-Code: a
genuine tree operation rather than a hand-maintained PID list, and SIGINT rather than
SIGTERM. *Unverified:* the `runnerw.exe` mechanism — the Windows graceful path visible in
current sources is WinP / `GenerateConsoleCtrlEvent` plus `WinProcessTerminator`, so treat
`runnerw.exe` as likely superseded rather than confirmed.

**The crash case: also a verified negative.** Greps of `flutter-intellij/src` for
`ShutDownTracker`, `addShutdownHook` and `Runtime.getRuntime()` return zero hits. All
termination hangs off `Disposer` / `destroyProcess()` — in-process cleanup, dead letters
under SIGKILL. No watchdog, no parent-death detection. The Dart plugin's analysis server is
not even under a `ProcessHandler`: it uses the Dart-supplied `StdioServerSocket` directly,
so it gets none of the platform's tree-kill machinery.

### The one thing that does survive an IDE crash — and it is not in the IDEs

Some Dart processes survive an IDE `SIGKILL` cleanly, and the mechanism is **stdin EOF**,
implemented in the Dart SDK rather than in either plugin. Verified:

- The analysis server's `serveStdio()` is documented "Return a future that will be
  completed when stdin closes"
  ([`pkg/analysis_server/lib/src/server/stdio_server.dart`](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/lib/src/server/stdio_server.dart)),
  and `driver.dart` calls `exit(0)` on that future
  ([lines ~541 and ~598](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/lib/src/server/driver.dart)).
- The Flutter daemon does the same via the command stream's `onDone`
  ([`packages/flutter_tools/lib/src/commands/daemon.dart`](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/commands/daemon.dart)).

This is exactly the pipe/EOF idiom from Part 1, and it is why orphans from these IDEs are
intermittent rather than universal. But it is implicit and partial: it protects only
processes wired to the IDE over stdio that implement the EOF exit, and does nothing for
grandchildren (`gradle`, `lldb`, `flutter_tester`, the launched app) — precisely the
population in the issues listed above. **`build_runner` is not in the protected set**: it
reads stdin only to receive a state blob and deliberately never closes the subscription
(Part 3, citing [dart-lang/sdk#61571](https://github.com/dart-lang/sdk/issues/61571)).

---

## Part 4 — How comparable tools do it

Two distinct models turn up, and they are not in competition — they answer different
questions.

### Model A: "the watcher should die with its launcher"

**webpack.** Two separate mechanisms, both verified in source.

*Signals:* `webpack-cli` handles `const EXIT_SIGNALS = ["SIGINT", "SIGTERM"];`
([`packages/webpack-cli/src/webpack-cli.ts`](https://github.com/webpack/webpack-cli/blob/master/packages/webpack-cli/src/webpack-cli.ts),
line 44) and installs a graceful handler when watching, with a force path on the second
signal — "Gracefully shutting down. To force exit, press ^C again. Please wait..." then
`compiler.close(...)` → `process.exit(0)`. Note this is the **same double-tap shape
`build_runner` uses** for SIGINT.

*Pipe/EOF:* the `--watch-options-stdin` flag is real and current. webpack's own schema
declares `watchOptions.stdin` as "Stop watching when stdin stream has ended."
([`schemas/WebpackOptions.json`](https://github.com/webpack/webpack/blob/main/schemas/WebpackOptions.json)),
and webpack-cli implements it as:

```js
if (this.#needWatchStdin(compiler)) {
  process.stdin.on("end", () => { process.exit(0); });
  process.stdin.resume();
}
```

This is exactly the Part 1 pipe/EOF idiom, exposed as a first-class option for precisely
our situation. It is **opt-in**, and it is the cleanest precedent for "a watcher that dies
with whoever launched it". It was **renamed, not removed**: webpack-cli v3 spelled it
`--watch-stdin` with an alias `--stdin`
([v3.3.12 `bin/config/config-yargs.js`](https://github.com/webpack/webpack-cli/blob/v3.3.12/bin/config/config-yargs.js#L249-L254));
webpack-cli 4.3.0 (2020-12-25) renamed it to `--watch-options-stdin`, derived from the
schema path, and it is still in the current README's short help.

**tsc / tsserver.** My starting hypothesis — that tsserver takes a `--parentProcessId` and
polls it — **is wrong for current TypeScript**, and I want to be explicit that I checked
rather than assumed. `gh search code` for `parentProcessId` and for `process.kill` across
`microsoft/TypeScript` returns nothing relevant (the only `process.kill` hit is in
`src/testRunner/parallel/host.ts`), and greps of
[`src/tsserver/nodeServer.ts`](https://github.com/microsoft/TypeScript/blob/main/src/tsserver/nodeServer.ts)
and `src/tsserver/server.ts` for "parent" return zero hits. What tsserver actually does is
**EOF on its input channel**, in both transports:

```ts
// IOSession (stdio)
rl.on("close", () => { this.exit(); });
// IpcIOSession (node IPC)
process.on("disconnect", () => { this.exit(); });
```

(same file, `listen()` on each class). `exit()` is `process.exit(0)`. So TypeScript's
long-running server converges on the same answer as webpack's opt-in flag and the Dart
analysis server (Part 3): **the input pipe closing is the death signal.** The typings
installer — a *grandchild* — does the same, logging "Parent process has exited, shutting
down..." on `process.on("disconnect")`
([`src/typingsInstaller/nodeTypingsInstaller.ts`](https://github.com/microsoft/TypeScript/blob/main/src/typingsInstaller/nodeTypingsInstaller.ts#L202-L206)).

**The polling variant I was thinking of does exist — in TypeScript 7, the Go port.**
`typescript-go` implements the LSP contract literally, and the comment states the purpose
in our exact terms:

```go
// startParentProcessWatchdog starts a goroutine that monitors the parent process
// and cancels the context if the parent dies. This prevents orphaned language
// server processes when the editor crashes or is killed.
ticker := time.NewTicker(5 * time.Second)
```
([`cmd/tsgo/lsp.go`](https://github.com/microsoft/typescript-go/blob/main/cmd/tsgo/lsp.go#L74-L108)),
wired from `initialize`. Liveness is `proc.Signal(syscall.Signal(0))` treating **EPERM as
alive** ([`isprocessalive_unix.go`](https://github.com/microsoft/typescript-go/blob/main/cmd/tsgo/isprocessalive_unix.go));
on Windows it is `OpenProcess(SYNCHRONIZE)` + `WaitForSingleObject(handle, 0) ==
WAIT_TIMEOUT`. It keeps the EOF path as well. So the precedent is real, just one major
version newer than where I first looked.

**LSP makes the polling variant a formal requirement.** The `initialize` request's
`processId` is specified as:

> The process Id of the parent process that started the server. Is null if the process has
> not been started by another process. If the parent process is not alive then the server
> should exit (see exit notification) its process.

([LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)).
So the protocol tells every conforming server to watch its parent — but leaves the
mechanism to the server, and the word is **"should"**. Compliance is genuinely mixed:
Microsoft's reference implementation `vscode-languageserver-node` complies twice over, with
a `--clientProcessId` CLI argument *and* the `initialize` param, polling every **3000 ms**
via `process.kill(processId, 0)` and exiting with a code that encodes whether the shutdown
was orderly
([`server/src/node/main.ts`](https://github.com/microsoft/vscode-languageserver-node/blob/main/server/src/node/main.ts#L44-L95)).
**rust-analyzer does not comply at all** — a grep across its `crates/` for
`process_id|parent_process|getppid` returns zero; it relies entirely on the client sending
`shutdown`/`exit`, plus stdio EOF because it is stdio-transported.

**watchexec / cargo-watch** (cargo-watch is built on watchexec) take the *supervisor* route
rather than the child-cooperation route. `watchexec-supervisor` depends on
[`process-wrap`](https://github.com/watchexec/process-wrap) 9.1.0
([`crates/supervisor/Cargo.toml`](https://github.com/watchexec/watchexec/blob/main/crates/supervisor/Cargo.toml)),
whose README documents the two platform wrappers: `ProcessGroup::leader()` on Unix and
`JobObject` on Windows. And the Windows wrapper does the right thing — verified in
[`src/windows.rs`](https://github.com/watchexec/process-wrap/blob/main/src/windows.rs):
`CreateJobObjectW`, then `info.BasicLimitInformation.LimitFlags =
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;` (line 95), then `AssignProcessToJobObject` (line 111),
with the doc comment "If `kill_on_drop` is true, we opt into the
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` flag".

The source comment names the intent exactly: "we opt into the
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` flag, which essentially implements the 'reap children'
feature of Unix systems directly in Win32". Defaults are documented under `--wrap-process`:
"By default, Watchexec will run the command in a session on Mac, in a process group in
Unix, and in a Job Object in Windows"
([`crates/cli/src/args/command.rs`](https://github.com/watchexec/watchexec/blob/main/crates/cli/src/args/command.rs#L141-L162)).

**This is the only tool surveyed that solves the crash-of-parent case properly** — and only
on Windows, and only because Windows offers the primitive. On Unix `ProcessGroup::leader()`
gives clean tree-killing but still needs a live supervisor to do the killing: `KillOnDrop`
is a userspace `Drop` impl and does not run under `SIGKILL`, so a `SIGKILL`ed watchexec
leaves its group behind. Watchexec has **no parent-death detection of its own** — a grep of
`crates/` for `getppid|parent_pid|ppid|PDEATHSIG` finds only two unrelated comments about
signal-mask inheritance.

(`cargo-watch` itself is **archived** — the GitHub API reports `"archived": true`, last push
2025-01-14 — and its README redirects to watchexec, so watchexec is the live answer for that
row.)

**nodemon** does neither. `kill()` in
[`lib/monitor/run.js`](https://github.com/remy/nodemon/blob/main/lib/monitor/run.js)
enumerates descendants with `psTree` and signals each pid individually — the comment
explains why: "psTree gives us an array of PIDs that have spawned under nodemon, and we
send each the configured signal (default: SIGUSR2) signal, which fixes #335". On Windows it
shells out to `taskkill /pid <pid> /T /F`, and for graceful SIGINT it bundles a
`bin/windows-kill.exe` helper which it must launch fully detached (`start "windows-kill"
/min /wait …`). No process groups, no job objects, nothing for the crash case. This is the
same "hand-rolled pid enumeration" shape as Dart-Code's `additionalPidsToTerminate`.

### Model B: "the daemon is *supposed* to outlive the client"

**Bazel** and the **Gradle daemon** deliberately survive their launcher, and both solve the
resulting cleanup problem the same way: **self-expiry on idle**.

- Bazel: `--max_idle_secs` — "The number of seconds the build server will wait idling
  before shutting down. Zero means that the server will never shutdown", default
  **`10800`** (3 hours)
  ([command-line reference](https://bazel.build/reference/command-line-reference)). There is
  also `--shutdown_on_low_sys_mem` ("shut down the server when the system is low on free
  RAM. Linux and MacOS only", default false). The explicit command is `shutdown`, which
  "causes the Bazel server to exit as soon as it becomes idle"; the manual adds that
  "Bazel servers stop themselves after an idle timeout, so this command is rarely
  necessary" ([user manual](https://bazel.build/docs/user-manual)).
- Gradle (docs for 9.6.1): "The Gradle Daemon is a long-lived, persistent process that runs
  in the background." Daemons "automatically stop given any of the following conditions:
  Available system memory is low; **Daemon has been idle for 3 hours**." `--stop`
  "terminates all Daemon processes started with the same version of Gradle used to execute
  the command", and the docs also tell you that "You can also kill Daemons manually with
  your operating system"
  ([Gradle Daemon userguide](https://docs.gradle.org/current/userguide/gradle_daemon.html)).

Both landed on the *same* 3-hour default independently, and both ship an explicit
`stop`/`shutdown` command that finds the daemon through a well-known location rather than
through a parent relationship — structurally the same as `build_runner stop` finding the
lock holder through `.dart_tool/build/lock/`. Bazel's client goes further and **reaps on
next start**: `GetServerPid(server_dir)` → `VerifyServerProcess` → `KillServerProcess`
([`src/main/cpp/blaze.cc`](https://github.com/bazelbuild/bazel/blob/master/src/main/cpp/blaze.cc#L932-L937)).
Gradle's equivalent prunes unreachable entries from `~/.gradle/daemon/<version>/registry.bin`
via `CleanupOnStaleAddress`. Both reap *records*, not orphan processes — Gradle's docs
concede the remainder: "You can also kill Daemons manually with your operating system."

**Gradle, uniquely, also detects client death — and is tested against a real `SIGKILL`.**
Its receive loop fires a disconnect handler on socket EOF, and the handler is unambiguous:

```java
public static final String EXPIRATION_REASON = "client disconnected";
execution.getConnection().onDisconnect(new Runnable() {
    public void run() {
        LOGGER.warn("thread {}: client disconnection detected, canceling the build", ...);
        execution.getDaemonStateControl().requestCancel();
    }
});
```
([`WatchForDisconnection.java`](https://github.com/gradle/gradle/blob/master/platforms/core-runtime/launcher/src/main/java/org/gradle/launcher/daemon/server/exec/WatchForDisconnection.java)).
Cancellation is cooperative with a 10-second grace period, after which the daemon force-stops
its own JVM. An integration test drives this with a genuine `destroyForcibly()`
("tears down the daemon process when the client disconnects and build does not cancel in a
timely manner",
[`ProcessCrashHandlingIntegrationTest.groovy`](https://github.com/gradle/gradle/blob/master/platforms/core-runtime/launcher/src/integTest/groovy/org/gradle/launcher/daemon/ProcessCrashHandlingIntegrationTest.groovy)).
There is no heartbeat; detection relies on the OS tearing down the socket, which on local
loopback is immediate. So this is the pipe/EOF idiom again, over a socket.

The same test file records *why* Gradle detaches deliberately — it asserts the daemon lands
in a different POSIX session, because "we need to detach it from the terminal session of the
parent process, otherwise if a ctrl-c is entered on the terminal, it will kill all processes
in the session". That is the Part 1 process-group mechanic stated from the other side.

Bazel's client-death story is weaker and I want to flag it as **inference**: its gRPC
`setOnCancelHandler` → `Thread.currentThread().interrupt()`
([`GrpcCommandServerImpl.java`](https://github.com/bazelbuild/bazel/blob/master/src/main/java/com/google/devtools/build/lib/server/GrpcCommandServerImpl.java#L124-L127))
only trips when the server next writes output, so a silent build phase would not notice
promptly. No dedicated client-liveness watchdog was found. Bazel's `PidFileWatcher` does poll
a pid file every 3 seconds, but it watches the server's *own* pid file to defend against
another server stealing the output base — not the client.

### VS Code's own extension host does exactly what we are proposing

This matters directly for call site 2, because it establishes that the extension host is a
sound thing to watch. VS Code's extension host kills *itself* when its parent dies:

```js
if (initData.parentPid) {
    // Kill oneself if one's parent dies. Much drama.
    let epermErrors = 0;
    setInterval(function () {
        try { process.kill(initData.parentPid, 0); epermErrors = 0; }
        catch (e) {
            if (e && e.code === 'EPERM') {
                // Even if the parent process is still alive,
                // some antivirus software can lead to an EPERM error to be thrown here.
                // Let's terminate only if we get 3 consecutive EPERM errors.
                epermErrors++;
                if (epermErrors >= 3) { onTerminate(...); }
            } else { onTerminate(...); }
        }
    }, 1000);
    ...
    watchdog = require('@vscode/native-watchdog');
    watchdog.start(initData.parentPid);
}
```

([`src/vs/workbench/api/node/extensionHostProcess.ts`](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/api/node/extensionHostProcess.ts#L351-L383)).

Three lessons worth stealing:

- **The extension host reliably dies with VS Code.** Watching `process.pid` from inside an
  extension is therefore well-founded — it is a parent that both crashes *and* is
  guaranteed to be torn down.
- **EPERM is not death.** A permission error means the process exists. VS Code demands three
  consecutive EPERMs before acting; typescript-go treats EPERM as unconditionally alive. A
  naive `kill -0` reaper that treats any failure as "parent gone" will kill live watches.
  Note that `bash`'s `kill -0` returns non-zero on EPERM too, so **build_runner's own reaper
  one-liner has this bug** — as would a copy of it.
- **A poll written on a busy event loop can be starved**, which is why VS Code adds a native
  backstop: `@vscode/native-watchdog` "is implemented by launching a separate thread from
  C++ which periodically checks if the given process is still running… The watched process is
  checked every 1s and if it is no longer running, the current process will exit after 6
  seconds with the exit code 87"
  ([README](https://github.com/microsoft/node-native-watchdog/blob/master/README.md)). A
  reaper in a *separate process* — the build_runner shape — sidesteps this for free.

**esbuild closes the one hole EOF leaves**, and is worth naming as the most complete design
in the survey: it exits on stdin EOF (`if n == 0 || err == io.EOF { break }`) *and* pings
outward on a 1-second timer, with the reasoning in the comment — "Periodically ping the host
even when we're idle. This will catch cases where the host has disappeared and will never
send us anything else but we incorrectly think we are still needed. In that case we will now
try to write to stdout and fail, and then know that we should exit"
([`cmd/esbuild/service.go`](https://github.com/evanw/esbuild/blob/main/cmd/esbuild/service.go#L117-L136)).

### So what is the accepted pattern for "a long-running watcher started by an editor"?

There is no single one; there is a **layered consensus**, and each layer covers what the
one below cannot:

| Layer | Covers | Who does it |
|---|---|---|
| Signal handler in the parent, forwarding a graceful signal | Ctrl-C, `kill`, clean editor shutdown | webpack-cli, nodemon, Dart-Code, flutter-intellij, build_runner (SIGINT only) |
| Tree/group kill rather than single-pid kill | grandchildren | watchexec (`ProcessGroup`), flutter-intellij (`killProcessTree`), nodemon (`psTree`) |
| **Child exits on input EOF** | **parent crash, `SIGKILL`, editor death** | tsserver, Dart analysis server, Flutter daemon, esbuild, Gradle (socket), webpack (opt-in) |
| **Child polls the parent pid** | **parent crash, when there is no pipe** | VS Code extension host, `vscode-languageserver-node` (3 s), typescript-go (5 s), build_runner's reaper (1 s) |
| **Job object (Windows only)** | **parent crash, kernel-enforced** | watchexec / process-wrap |
| **Idle self-expiry** | everything else, eventually | Bazel (3 h), Gradle (3 h), Watchman (5 d) |
| Explicit `stop`/`shutdown` command found via a well-known path | orphans that already exist | Bazel, Gradle, build_runner |

**On the crash-of-parent case specifically**, three families genuinely solve it:
**watchexec on Windows** via `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`; the **EOF-exiting
servers** (tsserver, Dart analysis server, esbuild, Gradle over its socket, webpack with
`watchOptions.stdin`), which work because the kernel closes the pipe no matter how the
parent died; and the **pid-pollers** (VS Code's extension host, LSP servers, typescript-go),
which work but carry the EPERM and pid-reuse hazards above. Everyone else — Dart-Code,
flutter-intellij, nodemon, webpack without the flag, and `build_runner` for its own parent —
leaves the child running, and the accepted fallback is idle self-expiry plus a `stop`
command that reaps on the next run.

**When there is a pipe, EOF is enough, and most projects stop there.** The pid poll exists
for transports that cannot signal EOF, and the LSP spec says "should" precisely because it
is the weaker, racier mechanism. Our case has no pipe — `frx watch` uses
`inheritStdio`, and the VS Code extension does not feed build_runner's stdin — and
`build_runner` does not implement an EOF exit anyway (Part 3). So the poll is the available
route, which is exactly why build_runner's own reaper takes it.

`build_runner watch` implements **none** of the first four layers for its own parent: SIGINT
only, no EOF exit, no idle timeout. It does ship the `stop` command (bottom row) and it does
implement a poll-the-parent reaper — but for its own child, not for itself (Part 3).

---

## Part 5 — Applicable conclusions

### What is true for both call sites

1. **`build_runner watch` handles exactly one signal: SIGINT.** Not SIGTERM, not SIGHUP.
   Any shutdown path that sends SIGTERM gets an abrupt kill with no graceful drain; any
   path that sends SIGINT gets the drain. This single fact changes both call sites.
2. **The second SIGINT is a hard `exit(2)`.** So sending SIGINT to a child that the tty has
   *already* SIGINT'd converts a graceful Ctrl-C into a hard exit. Whether to forward
   depends on whether the child shares your foreground process group.
3. **`dart run build_runner stop --workspace` is the sanctioned remedy** and it is
   parent-agnostic — it talks to whoever holds the lock, via the filesystem (Part 3). It is
   the only mechanism that cleans up an orphan created *before* any fix shipped.
   **Caveat: it has no timeout.** `takeLock` is `while (true)` with a 100 ms delay
   (`build_process_lock.dart`, line 52/79). Against a wedged watch that never notices the
   `.requested` file, it blocks forever. Any programmatic caller must impose its own
   timeout.
4. **Nothing in the parent can cover parent-`SIGKILL`.** Covering it requires a third
   process (a reaper), the kernel (job object / PDEATHSIG), or the child noticing. Given
   that build_runner implements none of the child-side options, a reaper is the only route
   that does not require patching build_runner.
5. **Do not detach the watch.** Both `ProcessStartMode.detached` (Dart) and
   `spawn(…, {detached: true})` (Node) call `setsid()`. That puts the watch in its own
   session, which (a) removes it from the terminal's foreground process group so Ctrl-C
   stops reaching it, and (b) makes `frx doctor`'s session-based orphan test report a
   **live** watch as orphaned — after which `frx` would build over it and kill it. This is
   a real interaction between the two call sites.

### Call site 1 — `frx watch`

Today (`tools/lib/src/commands/watch_command.dart` → `streamProcess` in
`tools/lib/src/engine/build_step.dart`): `Process.start('dart', […, 'watch', '--workspace'],
mode: ProcessStartMode.inheritStdio)`, no signal handlers, awaits `proc.exitCode`.

Current behaviour, by case:

| Parent event | What happens now | Why |
|---|---|---|
| Ctrl-C in a terminal | **works** — graceful drain | tty SIGINTs the whole foreground process group; the child is in it (verified here) and drains. `frx` forwards nothing and needs to. |
| `kill <frx>` (SIGTERM) | **orphan** | `frx` dies by default disposition; the child never hears about it and does not watch SIGTERM anyway. |
| `kill -9 <frx>` | **orphan** (observed) | nothing runs. |
| terminal window closed | **unreliable** | SIGHUP goes to the controlling process (the shell); whether jobs are hung up is shell policy. `frx` does not watch SIGHUP. |

**Step 1 — signal handlers (small, covers SIGTERM/SIGHUP).** Watch SIGINT, SIGTERM and
SIGHUP; on each, bring the child down and then exit.

- On **SIGTERM / SIGHUP**: send `ProcessSignal.sigint` to the child, await `proc.exitCode`
  with a bounded timeout, then escalate to `sigkill`.
- On **SIGINT**: **do not forward.** In a terminal the tty already delivered it to the
  child; a forwarded second SIGINT triggers build_runner's `exit(2)` hard path. Just await
  the child. (If `frx watch` is ever run outside a terminal, the tty did not signal the
  child — but SIGINT does not arrive from a tty there either, so the case is moot in
  practice.)
- Platform caveat: `ProcessSignal.sigterm` **cannot be watched on Windows**; SIGINT and
  SIGHUP can. On Windows only the SIGINT path exists.

**Step 2 — a reaper (covers the parent `SIGKILL`, the actual bug).** Copy the pattern
build_runner already ships (`bootstrap/processes.dart`, quoted in Part 3) — it is pure
Dart plus a shell one-liner, no FFI, and it is proven in the same dependency tree:

```
bash -c 'while kill -0 <frxPid>; do sleep 1; done; kill -INT <childPid>'
```
started with `ProcessStartMode.detachedWithStdio`, and killed from
`proc.exitCode.then((_) => reaper.kill())` when the watch exits normally.

Two deliberate differences from build_runner's version: **`-INT`, not `-9`**, so the watch
drains and releases the lock cleanly (build_runner uses `-9` because it is killing a build
script, not a watch); and `<frxPid>` is `pid` from `dart:io`, i.e. `frx`'s own process.
Windows equivalent, also from build_runner:
`powershell -Command "Wait-Process -Id <frxPid>; Stop-Process -Id <childPid> -Force"` —
note `Stop-Process -Force` is a hard kill with no drain, which is acceptable because the
advisory lock is released by the OS regardless.

Caveats: 1-second polling granularity; one extra `bash`+`sleep` process per watch;
`bash` must be on PATH (build_runner's own comment notes macOS defaults to zsh but ships a
usable bash); and **PID reuse is unhandled** — if `<frxPid>` is recycled the reaper never
fires, and if `<childPid>` is recycled it kills a stranger. On a watch that runs for hours
this is unlikely but not impossible, and build_runner does not handle it either.

One more inherited bug worth knowing about: **`kill -0` fails on EPERM as well as on "no
such process"**, so the loop exits and the child is killed even though the parent is alive.
VS Code hit this in the field and its comment names the cause — "some antivirus software
can lead to an EPERM error to be thrown here" — and it therefore requires three consecutive
EPERMs before acting; typescript-go treats EPERM as unconditionally alive (Part 4). For
`frx watch` the parent is `frx` itself, same uid, so EPERM is close to impossible on Unix
and this is a low-priority refinement. It is worth a comment rather than code.

**Step 3 — make `frx doctor`'s remedy the sanctioned one.** `checkOrphanedWatch`
(`tools/lib/src/audit/checks.dart`, line 667) currently advises ``kill $pid``. That sends
SIGTERM, which `build_runner watch` does not handle — the process dies mid-build with no
drain. Advise `dart run build_runner stop --workspace` (project-scoped, graceful, verified
to work on a watch whose parent is long dead) or at minimum `kill -INT $pid`. This step is
worth doing **first**: it is the smallest change and it is the only one that helps with
orphans that already exist.

**Step 4 — note the macOS gap in the detector.** The session comparison in `_isOrphan`
(`build_step.dart`) is inert on macOS, because `ps -o sess=` there prints a redacted kernel
pointer, not a session id (Part 1). The check still returns the right answer on macOS via
its `ppid <= 1` fallback, and macOS has no subreapers, so there is no bug to fix — but the
doc comment claims a mechanism that is not running on that platform, and anyone reading it
will believe the session test is doing the work everywhere. Either say so in the comment or
gate the session branch on `Platform.isLinux`.

**What remains uncovered after all four:** power loss or a hard machine kill; `kill -9` of
the reaper as well as `frx`; PID reuse; and a *wedged* watch — one that holds the lock and
never responds — which no mechanism here distinguishes from a healthy one and which will
also hang `build_runner stop`.

### Call site 2 — the VS Code extension

Today: `child_process.spawn('dart', ['run','build_runner','watch','--workspace'])` and
`child.kill('SIGTERM')` on dispose.

Three defects, in order of severity:

1. **`dispose()` does not run when VS Code or the extension host crashes.** This is the same
   hole Dart-Code has, and the Dart-Code maintainer names it as the likely explanation for
   the orphan reports on that tracker (Part 3). No amount of dispose-side work closes it.
2. **SIGTERM is the wrong signal.** `build_runner watch` does not handle it — the drain
   never happens. Use `SIGINT`.
3. **On Windows, `child.kill()` ignores the signal entirely** and kills only that one
   process ("the `signal` argument will be ignored except for `'SIGKILL'`, `'SIGTERM'`,
   `'SIGINT'` and `'SIGQUIT'`, and the process will always be killed forcefully and
   abruptly" — [Node.js docs](https://nodejs.org/api/child_process.html)).

Recommended order:

**Step 1 — reap on activate (do this first).** Before starting a new watch, run
`dart run build_runner stop --workspace` in the project directory and wait for it, **with
your own timeout** (see the no-timeout caveat above; 10–15 s then give up and warn). This
is the highest-value, most portable step: identical on all three platforms, no
platform-specific code, and it is the only one that cleans up orphans left by a previous
crash. Cost is one Dart VM start; `stop` does not bootstrap builders, so it is on the cheap
end.

**Step 2 — `child.kill('SIGINT')` on dispose,** then wait for the `exit` event with a
timeout and escalate to `SIGKILL`. On Windows, prefer `taskkill /pid <pid> /T /F`, since
`/T` kills the tree and Node's `kill()` does not. Note that the inner build-script process
is already covered: build_runner spawns its own reaper for that link (Part 3), so killing
the outer `dart run` is sufficient there despite Node's warning that "on Linux, child
processes of child processes will not be terminated when attempting to kill their parent".

**Step 3 — a reaper, watching the extension host pid.** From Node:

```js
const reaper = spawn('bash', ['-c',
  `while kill -0 ${process.pid} 2>/dev/null; do sleep 1; done; kill -INT ${child.pid}`],
  { detached: true, stdio: 'ignore' });
reaper.unref();
child.on('exit', () => { try { process.kill(reaper.pid); } catch {} });
```

`process.pid` inside a VS Code extension is the **extension host**, which is the right
parent to watch — and Part 4 establishes *why* it is sound: the extension host already kills
itself when VS Code dies, polling `process.kill(parentPid, 0)` every second and backing that
with a native C++ watchdog thread
([`extensionHostProcess.ts`](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/api/node/extensionHostProcess.ts#L351-L383)).
So watching the extension host inherits a link VS Code itself guarantees. `detached: true`
and `unref()` here apply to the **reaper**, which is correct — it must outlive the extension
host. Do **not** apply them to the build_runner child itself, for the reasons in "what is
true for both call sites" above. Note the `2>/dev/null` and the EPERM caveat from call
site 1 apply here too.

**Platform caveat for step 3:** the Windows form is
`powershell -Command "Wait-Process -Id <hostPid>; Stop-Process -Id <childPid> -Force"`.
If a native dependency is ever acceptable, a Windows **job object** with
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` is strictly better than the reaper on that platform —
kernel-enforced, no polling, no PID-reuse hazard (Part 1). Node cannot create one without a
native module, so it is not the first move.

**What remains uncovered:** the window between extension-host death and the reaper's next
1-second poll; power loss; PID reuse; and a wedged watch. Step 1 is the backstop for all of
them — whatever leaks, the next activation reaps it.

### If only one thing gets done

Make `build_runner stop` the remedy everywhere: at VS Code extension activation, and in
`frx doctor`'s advice. It is parent-agnostic, project-scoped, graceful, needs no
platform-specific code, and is the only measure that repairs damage already done. The
signal handlers and the reaper reduce how often it is needed; they do not replace it.

---

## What could not be verified

Collected here so it is not buried. Each of these was looked for and not found, or found
only in a form weaker than primary.

- **`kqueue` registration race.** The macOS `kqueue(2)` text I read does not say what happens
  when you register `EVFILT_PROC` for a pid that has already exited. I did not test it.
- **Session-id reuse.** Whether a session id can be recycled onto an unrelated process while
  the session still has members. Not stated in the man-pages or POSIX text I read; untested.
- **Windows, everywhere.** I have no Windows machine here. Every Windows claim in this
  document is from Microsoft Learn or from source, never from observation. In particular the
  job-object-from-Dart sketch in Part 2 was **not built or run** — `SetInformationJobObject`
  exposure in the `win32` package is unconfirmed, and the `CreateProcess` →
  `AssignProcessToJobObject` race is unaddressed by the Learn page.
- **`runnerw.exe`** in the IntelliJ platform. The Windows graceful-termination path visible
  in current `intellij-community` sources is WinP / `GenerateConsoleCtrlEvent` plus
  `WinProcessTerminator`. Treat `runnerw.exe` as likely superseded rather than confirmed.
- **The JetBrains Dart plugin is closed source** as of 2026-06-04
  ([commit `4bb2408`](https://github.com/JetBrains/intellij-plugins/commit/4bb240841f)).
  Those findings are from the last open commit and may not reflect shipping code.
- **cargo-watch's own source** was not read — but it is **archived** (last push 2025-01-14)
  and its README redirects to watchexec, so the watchexec/process-wrap findings are the live
  answer for that row.
- **Bazel's client-death path is inferred, not proven.** The gRPC `setOnCancelHandler` →
  `Thread.currentThread().interrupt()` only fires when the server next writes output. No
  dedicated liveness watchdog was found, and no test asserting behaviour against a
  `SIGKILL`ed client (Gradle has such tests; Bazel, as far as was looked, does not). Bazel's
  issue tracker was not searched for orphan-server reports.
- **Gradle's no-FIN edge case is inference** — a `SIGSTOP`ped client, or a severed link where
  no FIN/RST arrives, would not trip `WatchForDisconnection`. No source-level defence found.
- **nodemon's orphan issue history** was not surveyed; the in-source references (#335) are
  all that was read.
- **Windows pipe-EOF semantics** for the IDE case are reasoned from code, not observed —
  EOF there requires *all* inherited write handles to close, so a grandchild holding the
  pipe can defeat it.
- **`ps -o sess=` was measured on this machine only** (macOS 15 / Darwin 25.5.0, inside a
  sandbox that limited the visible process table to ~31 entries). The reading is corroborated
  by Apple's `ps` source, so I am confident in the conclusion, but it is one machine.
- **The macOS-has-no-`prctl` claim** rests on `man -w 2 prctl` failing here while
  `man -w 2 setsid` succeeds, plus the absence of any Apple documentation for it. That is
  strong evidence, not a positive citation — Apple does not publish a document saying the
  call does not exist.

Secondary sources were used nowhere for a load-bearing claim. The one place a secondary
source appears is the macOS `kqueue(2)` man page, read via
[keith.github.io/xcode-man-pages](https://keith.github.io/xcode-man-pages/kqueue.2.html), a
mirror of the man pages Apple ships in Xcode — Apple's own online copy is in the deprecated
documentation archive.
