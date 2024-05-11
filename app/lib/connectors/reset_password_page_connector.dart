import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/reset_password/reset_password.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/reset_password_page.dart';

import '../common/validators.dart';
import '../navigation/routes.dart';

class ResetPasswordPageConnector extends StatelessWidget {
  const ResetPasswordPageConnector({
    super.key,
  });

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => ResetPasswordPage(
          password: vm.password,
          confirmPassword: vm.confirmPassword,
          onPressedResetPassword: vm.onPressedResetPassword,
          onPressedBackToLogin: vm.onPressedBackToLogin,
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ResetPasswordPageConnector, _Vm> {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final graph = ResetPasswordGraph(state);

    final passwordError = passwordValidator(graph.password);
    final confirmPasswordError = passwordValidator(graph.confirmPassword);
    final passwordsMatchError =
        passwordsMatchValidator(graph.password, graph.confirmPassword);

    final formIsValid = graph.allDataIsSet &&
        passwordError == null &&
        confirmPasswordError == null &&
        passwordsMatchError == null;

    return _Vm(
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
      onPressedResetPassword: formIsValid
          ? () => dispatchSync(
                ResetPasswordAction(),
              )
          : null,
      onPressedBackToLogin: router.pop,
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.password,
    required this.confirmPassword,
    required this.onPressedResetPassword,
    required this.onPressedBackToLogin,
  });

  final ValueChangedWithErrorVm<String?> password;
  final ValueChangedWithErrorVm<String?> confirmPassword;
  final VoidCallback? onPressedResetPassword;
  final VoidCallback? onPressedBackToLogin;

  @override
  List<Object?> get props => [password, confirmPassword];
}
