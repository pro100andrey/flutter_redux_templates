import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/value_changed.dart';
import 'package:ui/pages/registration_page.dart';

import '../routes.dart';

class RegistrationPageConnector extends StatelessWidget {
  const RegistrationPageConnector({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => RegistrationPage(
          isWaiting: vm.isWaiting,
          email: vm.email,
          password: vm.password,
          confirmPassword: vm.confirmPassword,
          onPressedRegister: vm.onPressedRegister,
          onPressedBackToLogin: vm.onPressedBackToLogin,
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, RegistrationPageConnector> {
  _Factory(RegistrationPageConnector widget) : super(widget);

  @override
  _Vm fromStore() {
    const String? password = null;
    const String? passwordError = null;

    return _Vm(
      isWaiting: false,
      email: ValueChangedWithErrorVm<String>(
        value: password,
        error: passwordError,
        onChanged: (email) {},
      ),
      password: ValueChangedWithErrorVm<String>(
        value: password,
        error: passwordError,
        onChanged: (password) {},
      ),
      confirmPassword: ValueChangedWithErrorVm<String>(
        value: password,
        error: passwordError,
        onChanged: (confirmPassword) {},
      ),
      onPressedRegister: () {},
      onPressedBackToLogin: routemaster.pop,
    );
  }
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.isWaiting,
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.onPressedRegister,
    required this.onPressedBackToLogin,
  });

  final bool isWaiting;
  final ValueChangedWithErrorVm<String> email;
  final ValueChangedWithErrorVm<String> password;
  final ValueChangedWithErrorVm<String> confirmPassword;
  final VoidCallback? onPressedRegister;
  final VoidCallback? onPressedBackToLogin;

  @override
  List<Object?> get props => [isWaiting, email, password, confirmPassword];
}
