import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/registration/actions/registration_action.dart';
import 'package:business/redux/registration/actions/set_confirm_password_action.dart';
import 'package:business/redux/registration/actions/set_email_action.dart';
import 'package:business/redux/registration/actions/set_password_action.dart';
import 'package:business/redux/registration/models/registration_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/registration_page.dart';

import '../common/validators.dart';
import '../navigation/routes.dart';

class RegistrationPageConnector extends StatelessWidget {
  const RegistrationPageConnector({
    super.key,
  });

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => RegistrationPage(
          email: vm.email,
          password: vm.password,
          confirmPassword: vm.confirmPassword,
          onPressedRegister: vm.onPressedRegister,
          onPressedBackToLogin: vm.onPressedBackToLogin,
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, RegistrationPageConnector, _Vm> {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final graph = RegistrationGraph(state);

    final emailError = emailValidator(graph.email);
    final passwordError = passwordValidator(graph.password);
    final confirmPasswordError = passwordValidator(graph.confirmPassword);
    final passwordsMatchError =
        passwordsMatchValidator(graph.password, graph.confirmPassword);
    final formIsValid = graph.allDataIsSet &&
        emailError == null &&
        passwordError == null &&
        confirmPasswordError == null &&
        passwordsMatchError == null;

    return _Vm(
      email: ValueChangedWithErrorVm(
        value: graph.email,
        error: emailError,
        onChanged: (value) => dispatchSync(
          SetEmailAction(value!),
        ),
      ),
      password: ValueChangedWithErrorVm(
        value: graph.password,
        error: passwordError,
        onChanged: (value) => dispatchSync(
          SetPasswordAction(value!),
        ),
      ),
      confirmPassword: ValueChangedWithErrorVm(
        value: graph.confirmPassword,
        error: confirmPasswordError ?? passwordsMatchError,
        onChanged: (value) => dispatchSync(
          SetConfirmPasswordAction(value!),
        ),
      ),
      onPressedRegister: formIsValid
          ? () async {
              await dispatchAndWait(RegistrationAction());
              router.pop();
            }
          : null,
      onPressedBackToLogin: router.pop,
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.onPressedRegister,
    required this.onPressedBackToLogin,
  });

  final ValueChangedWithErrorVm<String?> email;
  final ValueChangedWithErrorVm<String?> password;
  final ValueChangedWithErrorVm<String?> confirmPassword;
  final VoidCallback? onPressedRegister;
  final VoidCallback? onPressedBackToLogin;

  @override
  List<Object?> get props => [email, password, confirmPassword];
}
