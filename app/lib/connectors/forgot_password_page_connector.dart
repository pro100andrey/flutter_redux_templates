import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/forgot_password/actions/forgot_password_action.dart';
import 'package:business/redux/forgot_password/actions/set_email_action.dart';
import 'package:business/redux/forgot_password/forgot_password_selectors.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/forgot_password_page.dart';

import '../common/validators.dart';
import '../navigation/routes.dart';

class ForgotPasswordPageConnector extends StatelessWidget {
  const ForgotPasswordPageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder:
        (context, vm) => ForgotPasswordPage(
          isWaiting: vm.isWaiting,
          email: vm.email,
          onPressedResetPassword: vm.onPressedResetPassword,
          onPressedBackToLogin: vm.onPressedBackToLogin,
        ),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ForgotPasswordPageConnector, _Vm> {
  _Factory(super._connector);

  @override
  _Vm fromStore() {
    final email = selectForgotPasswordEmail(state);
    final emailError = emailValidator(email);

    return _Vm(
      isWaiting: false,
      email: ValueChangedWithErrorVm(
        value: email,
        error: emailError,
        onChanged: (value) => dispatchSync(SetEmailAction(email: value!)),
      ),
      onPressedResetPassword: () => dispatchSync(ForgotPasswordAction()),
      onPressedBackToLogin: router.pop,
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.isWaiting,
    required this.email,
    required this.onPressedResetPassword,
    required this.onPressedBackToLogin,
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String?> email;
  final VoidCallback? onPressedResetPassword;
  final VoidCallback onPressedBackToLogin;

  @override
  List<Object?> get props => [isWaiting, email];
}
