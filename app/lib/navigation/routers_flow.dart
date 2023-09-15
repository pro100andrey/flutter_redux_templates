import 'package:equatable/equatable.dart';

sealed class RoutersFlow extends Equatable {
  const RoutersFlow();
  @override
  List<Object?> get props => [];
}

enum AuthFlowRedirection {
  login,
  resetPassword,
  createPassword;
}

final class AuthFlow extends RoutersFlow {
  const AuthFlow({
    required this.redirection,
  });

  final AuthFlowRedirection redirection;

  @override
  List<Object?> get props => [redirection];
}

final class SplashFlow extends RoutersFlow {
  const SplashFlow();
}

final class HomeFlow extends RoutersFlow {
  const HomeFlow();
}
