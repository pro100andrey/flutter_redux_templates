import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/login/actions/log_in_with_email_action.dart';
import 'package:business/redux/login/actions/set_email_action.dart';
import 'package:business/redux/login/actions/set_password_action.dart';
import 'package:business/redux/theme/actions/set_theme_mode_action.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/log_in_page.dart';

import '../common/validators.dart';
import '../navigation/app_router.dart';
import '../navigation/go_action.dart';

@RoutePage()
class LogInPageConnector extends StatelessWidget {
  const LogInPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => LogInPage(
      email: vm.email,
      password: vm.password,
      onPressedForgotPassword: vm.onPressedForgotPassword,
      onPressedLogIn: vm.onPressedLogIn,
      onPressedRegister: vm.onPressedRegister,
      theme: vm.theme,
    ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LogInPageConnector, _Vm>
    with Selectors {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    email: FieldVm(
      value: login.email,
      validator: (v) => emailValidator(v),
      onChanged: (v) => dispatchSync(SetEmailAction(v)),
    ),
    password: FieldVm(
      value: login.password,
      validator: (v) => passwordValidator(v),
      onChanged: (v) => dispatchSync(SetPasswordAction(v)),
    ),
    onPressedLogIn: () => dispatchAndWait(LogInWithEmailAction()),
    onPressedForgotPassword: () =>
        dispatch(GoAction.push(const ForgotPasswordRoute())),
    onPressedRegister: () => dispatch(GoAction.push(const RegistrationRoute())),
    theme: FieldVm(
      value: theme.mode,
      onChanged: (mode) => dispatchSync(SetThemeModeAction(mode)),
    ),
  );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm {
  _Vm({
    required this.email,
    required this.password,
    required this.onPressedLogIn,
    required this.onPressedForgotPassword,
    required this.onPressedRegister,
    required this.theme,
  }) : super(equals: [email, password, theme]);

  final FieldVm<String?> email;
  final FieldVm<String?> password;
  final VoidCallback onPressedLogIn;
  final VoidCallback onPressedForgotPassword;
  final VoidCallback onPressedRegister;
  final FieldVm<ThemeMode> theme;
}
