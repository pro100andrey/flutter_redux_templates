import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/log_in/actions/log_in_with_email_action.dart';
import 'package:business/redux/log_in/actions/set_email_action.dart';
import 'package:business/redux/log_in/actions/set_password_action.dart';
import 'package:business/redux/log_in/log_in_selectors.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/log_in_page.dart';

import '../common/validators.dart';
import '../routes.dart';

class LogInPageConnector extends StatelessWidget {
  const LogInPageConnector({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => LogInPage(
          isWaiting: vm.isWaiting,
          email: vm.email,
          password: vm.password,
          onPressedForgotPassword: vm.onPressedForgotPassword,
          onPressedLogIn: vm.onPressedLogIn,
          onPressedRegister: vm.onPressedRegister,
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, LogInPageConnector> {
  _Factory(LogInPageConnector widget) : super(widget);

  @override
  _Vm fromStore() {
    final isWaiting = selectLogInWaiting(state);
    final email = selectLogInEmail(state);
    final password = selectLogInPassword(state);
    final emailError = emailValidator(email);
    final passwordError = passwordValidator(password);
    final formIsValid = selectLogInDataIsSet(state) &&
        emailError == null &&
        passwordError == null;

    return _Vm(
      isWaiting: isWaiting,
      email: ValueChangedWithErrorVm<String>(
        value: email,
        error: emailError,
        onChanged: (email) => dispatch(
          SetEmailAction(email),
        ),
      ),
      password: ValueChangedWithErrorVm<String>(
        value: password,
        error: passwordError,
        onChanged: (password) => dispatch(
          SetPasswordAction(password),
        ),
      ),
      onPressedLogIn: formIsValid
          ? () => dispatch(
                LogInWithEmailAction(),
              )
          : null,
      onPressedForgotPassword: () => routemaster.push(
        Routes.forgotPassword,
      ),
      onPressedRegister: () => routemaster.push(
        Routes.register,
      ),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.isWaiting,
    required this.email,
    required this.password,
    required this.onPressedLogIn,
    required this.onPressedForgotPassword,
    required this.onPressedRegister,
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String> email;
  final ValueChangedWithErrorVm<String> password;
  final VoidCallback? onPressedLogIn;
  final VoidCallback onPressedForgotPassword;
  final VoidCallback onPressedRegister;

  @override
  List<Object?> get props => [isWaiting, email, password];
}
