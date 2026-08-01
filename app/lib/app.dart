import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:localization/localization.dart';
import 'package:ui/theme/common.dart';

import 'connectors/top_level_page_connector.dart';
import 'dialogs/exception_dialog.dart';

/// Root of the app. Reads theme + language from the store and feeds them into
/// [MaterialApp.router]; auth gating lives in the router's auth guard.
class AppConnector extends StatelessWidget {
  const AppConnector({required this.routerConfig, super.key});

  final RouterConfig<Object> routerConfig;

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: routerConfig,
      themeMode: vm.mode,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      locale: Locale(vm.locale),
      // Both live above the router's Navigator: ExceptionDialog shows
      // UserException dialogs (via NavigateAction.navigatorKey, wired in
      // run_env), TopLevelPageConnector paints the barrier / no-internet
      // overlays over everything.
      builder: (context, child) => TopLevelPageConnector(
        child: ExceptionDialog<AppState>(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, AppConnector, _Vm> with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(mode: theme.mode, locale: language.locale);
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({required this.mode, required this.locale})
    : super(equals: [mode, locale]);

  final ThemeMode mode;
  final String locale;
}
