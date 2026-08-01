/// The base every service in `redux/services/` extends.
///
/// **A service is what pushes *into* the app.** That is the whole distinction
/// against a `ReduxAction`, which runs because the app asked: a platform
/// stream, a socket, a timer or a sensor produces an event nobody requested,
/// and something has to turn it into a dispatch. That is why a service has a
/// lifecycle and an action does not.
///
/// **A service comes in two halves, and the split is the point.**
///
/// - `<Name>Service` — extends this base, talks to the outside world, and
///   **knows nothing of Redux**: it must not import `app_state.dart` or hold a
///   `Store`. It declares `<Name>ServiceListener` beside itself — what it needs
///   from whoever is listening — so the dependency points inward at the service
///   rather than out at its caller.
/// - `<Name>Dispatcher` — implements that interface and is the **only** half
///   holding the `Store<AppState>`, turning an event into a dispatch.
///
/// That is an Observer with the subject naming the contract. The interface is
/// named for the role the service sees ("something I notify") and the class for
/// what it does ("it dispatches"), which is what leaves room for a second
/// listener — a test double, a logger — that listens without dispatching.
///
/// Scaffold both halves with `frx add-service <name>`. Neither is wired for
/// you: add the field to `AppDependencies` and its
/// [DisposableServiceInterface.start] call to `warmUp()` yourself. Unlike a
/// substate left out of `AppState`, `frx doctor` has nothing to say about a
/// service that was never composed.
library;

import 'dart:async';

import 'package:logging/logging.dart';

/// A service with a logger and two construction hooks.
///
/// **[init] and [setup] are called from the constructor**, which is what makes
/// them worth knowing about before overriding them. Dart runs a subclass's
/// field initializers and initializing formals *before* the superclass
/// constructor body, so those are safe to read from an override — but two
/// things are not, and both fail quietly or late:
///
/// ```dart
/// class Bad extends ServiceInterface {
///   Bad() {
///     _fromBody = 'set';        // runs AFTER init() — the override sees null
///   }
///   String? _fromBody;
///   late final String _uninitialized;   // reading it in init() throws LateError
/// }
/// ```
///
/// So take everything an override needs through the constructor's parameter
/// list (`this.x` or a field initializer), never by assigning it in the body.
/// `ConnectivityService` does exactly that with its listener.
///
/// Prefer [DisposableServiceInterface] unless the service genuinely has nothing
/// to start or release: these two hooks are synchronous, so they cannot do the
/// awaiting that opening a stream or a socket needs.
abstract class ServiceInterface {
  ServiceInterface() {
    init();
    setup();
  }

  /// First construction hook. Override for wiring that needs no `await`.
  void init() {
    logger.fine('init');
  }

  /// Second construction hook, run straight after [init]. The pair exists so a
  /// subclass can separate "build my parts" from "connect them" without either
  /// having to call `super` at the right moment.
  void setup() {
    logger.fine('setup');
  }

  /// Named after [identifier], so a service's lines are filterable by class.
  ///
  /// `late` because [identifier] is overridable: an eager initializer would
  /// capture the base's answer before the subclass exists. The laziness is why
  /// reading it inside [init] works at all.
  late final logger = Logger(identifier);

  /// The logger's name. Defaults to the runtime type; override to group several
  /// services under one name, or to keep it stable through a rename.
  String get identifier => runtimeType.toString();
}

/// A service that owns something with a lifetime — a subscription, a socket, a
/// timer, a file handle.
///
/// [start] carries the asynchronous setup a constructor cannot do: a Dart
/// constructor may not `await`, so anything that has to open a resource before
/// the service is usable belongs here rather than in [ServiceInterface.init].
/// It is called from `AppDependencies.warmUp()`, once, right after the store is
/// built — see `business/lib/dependencies.dart`.
///
/// **[dispose] is yours to call — nothing in this template calls it.** Services
/// here are composed once per `Store` and live as long as the process, so the
/// gap costs nothing today; it starts costing the moment a service is built per
/// screen or per session, or a test builds a second store. Whoever creates a
/// service outside `AppDependencies` owns releasing it.
///
/// Both return `FutureOr<void>` so a service whose setup happens to be
/// synchronous is not forced to be async. `await` works either way.
abstract class DisposableServiceInterface extends ServiceInterface {
  /// Begin work: subscribe, connect, schedule. Call `super.start()` first.
  FutureOr<void> start() {
    logger.fine('start');
  }

  /// Release what [start] acquired. Call `super.dispose()` first.
  FutureOr<void> dispose() {
    logger.fine('dispose');
  }
}
