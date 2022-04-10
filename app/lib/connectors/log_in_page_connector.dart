import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/log_in/actions/set_email_action.dart';
import 'package:business/redux/log_in/actions/set_password_action.dart';
import 'package:business/redux/log_in/log_in_selectors.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/log_in_page.dart';

import '../common/validators.dart';

class LogInPageConnector extends StatelessWidget {
  const LogInPageConnector({
    Key? key,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _LogInPageVm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => LogInPage(
          vm: LogInPageVm(
            isWaiting: vm.isWaiting,
            email: vm.email,
            password: vm.password,
            onPressedForgotPassword: vm.onPressedForgotPassword,
            onPressedLogIn: vm.onPressedLogIn,
          ),
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LogInPageConnector> {
  _Factory(LogInPageConnector widget) : super(widget);
  @override
  _LogInPageVm fromStore() {
    final email = selectLogInEmail(state);
    final password = selectLogInPassword(state);
    final emailError = emailValidator(email);
    final passwordError = passwordValidator(password);

    return _LogInPageVm(
      isWaiting: false,
      email: ValueChangedWithErrorVm<String>(
        value: email,
        error: emailError,
        onChanged: (v) => SetEmailAction(value: v),
      ),
      password: ValueChangedWithErrorVm<String>(
        value: password,
        error: passwordError,
        onChanged: (v) => SetPasswordAction(value: v),
      ),
      onPressedLogIn: () {},
      onPressedForgotPassword: () {},
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _LogInPageVm extends Vm with EquatableMixin {
  _LogInPageVm({
    required this.isWaiting,
    required this.email,
    required this.password,
    required this.onPressedLogIn,
    required this.onPressedForgotPassword,
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String> email;
  final ValueChangedWithErrorVm<String> password;
  final VoidCallback? onPressedLogIn;
  final VoidCallback? onPressedForgotPassword;

  @override
  List<Object?> get props => [isWaiting, email, password];
}
