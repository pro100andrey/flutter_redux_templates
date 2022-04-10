import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/home_page.dart';

class HomePageConnector extends StatelessWidget {
  const HomePageConnector({
    Key? key,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) =>
      StoreConnector<AppState, _HomePageVm>(
        debug: this,
        vm: () => _Factory(this),
        builder: (context, vm) => HomePage(
          vm: HomePageVm(
            isWaiting: vm.isWaiting,
          ),
        ),
      );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, HomePageConnector> {
  _Factory(HomePageConnector widget) : super(widget);
  @override
  _HomePageVm fromStore() => _HomePageVm(
        isWaiting: false,
      );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
class _HomePageVm extends Vm with EquatableMixin {
  _HomePageVm({
    required this.isWaiting,
  });

  final bool isWaiting;

  @override
  List<Object?> get props => [isWaiting];
}
