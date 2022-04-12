import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/profile_page.dart';

class ProfilePageConnector extends StatelessWidget {
  const ProfilePageConnector({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => ProfilePage(
          isWaiting: vm.isWaiting,
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, ProfilePageConnector> {
  _Factory(ProfilePageConnector widget) : super(widget);

  @override
  _Vm fromStore() => _Vm(
        isWaiting: false,
      );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _Vm extends Vm with EquatableMixin {
  _Vm({
    required this.isWaiting,
  });

  final bool isWaiting;

  @override
  List<Object?> get props => [isWaiting];
}
