import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/forgot_password_page.dart';

import '../routes.dart';

class ForgotPasswordPageConnector extends StatelessWidget {
  const ForgotPasswordPageConnector({
    super.key,
  });

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => ForgotPasswordPage(
          isWaiting: vm.isWaiting,
          email: vm.email,
          onPressedResetPassword: vm.onPressedResetPassword,
          onPressedBackToLogin: vm.onPressedBackToLogin,
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ForgotPasswordPageConnector> {
  _Factory(ForgotPasswordPageConnector super.widget);

  @override
  _Vm fromStore() {
    const String? email = null;
    const String? emailError = null;
    return _Vm(
      isWaiting: false,
      email: ValueChangedWithErrorVm(
        value: email,
        error: emailError,
        onChanged: (email) {},
      ),
      onPressedResetPassword: () {},
      onPressedBackToLogin: routemaster.pop,
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
  final ValueChangedWithErrorVm<String> email;
  final VoidCallback? onPressedResetPassword;
  final VoidCallback onPressedBackToLogin;

  @override
  List<Object?> get props => [isWaiting, email];
}
