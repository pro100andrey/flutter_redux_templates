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
import '../navigation/routes.dart';

class LogInPageConnector extends StatelessWidget {
  const LogInPageConnector({
    super.key,
  });

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
        ),
      );
}

/// Factory that creates a view-model  for the StoreConnector.
class _Factory extends BaseFactory<LogInPageConnector, _Vm> {
  _Factory(super.connector);

  @override
  _Vm fromStore() {
    final email = selectLogInEmail(state);
    final password = selectLogInPassword(state);
    final emailError = emailValidator(email);
    final passwordError = passwordValidator(password);
    final formIsValid = selectLogInDataIsSet(state) &&
        emailError == null &&
        passwordError == null;

    return _Vm(
      email: ValueChangedWithErrorVm(
        value: email,
        error: emailError,
        onChanged: (email) => dispatchSync(
          SetEmailAction(email),
        ),
      ),
      password: ValueChangedWithErrorVm(
        value: password,
        error: passwordError,
        onChanged: (password) => dispatchSync(
          SetPasswordAction(password: password),
        ),
      ),
      onPressedLogIn: formIsValid
          ? () async => dispatchAsync(
                LogInWithEmailAction(),
              )
          : null,
      onPressedForgotPassword: () => router.pushNamed(
        Routes.forgotPassword,
      ),
      onPressedRegister: () => router.pushNamed(
        Routes.registration,
      ),
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.email,
    required this.password,
    required this.onPressedLogIn,
    required this.onPressedForgotPassword,
    required this.onPressedRegister,
  });

  final ValueChangedWithErrorVm<String> email;
  final ValueChangedWithErrorVm<String> password;
  final VoidCallback? onPressedLogIn;
  final VoidCallback onPressedForgotPassword;
  final VoidCallback onPressedRegister;

  @override
  List<Object?> get props => [email, password];
}
