import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/splash_page.dart';

import '../dialogs/exception_dialog.dart';
import 'home_page_connector.dart';
import 'log_in_page_connector.dart';
import 'reset_password_page_connector.dart';

enum _HomePage {
  logIn,
  home,
  splash,
  resetPassword,
}

class InitialPageConnector extends StatelessWidget {
  const InitialPageConnector({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => ExceptionDialog<AppState>(
        child: StoreConnector<AppState, _Vm>(
          onWillChange: (context, store, previousVm, newVm) {},
          debug: this,
          vm: () => _Factory(this),
          builder: (context, vm) {
            switch (vm.homePage) {
              case _HomePage.logIn:
                return const LogInPageConnector();
              case _HomePage.home:
                return const HomePageConnector();
              case _HomePage.splash:
                return const SplashPage();
              case _HomePage.resetPassword:
                return const ResetPasswordPageConnector();
            }
          },
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, InitialPageConnector> {
  _Factory(InitialPageConnector widget) : super(widget);

  @override
  _Vm fromStore() {
    final homePage = _homePage(state);
    return _Vm(homePage: homePage);
  }

  _HomePage _homePage(AppState state) => _HomePage.logIn;
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({required this.homePage});

  final _HomePage homePage;

  @override
  List<Object?> get props => [homePage];
}
