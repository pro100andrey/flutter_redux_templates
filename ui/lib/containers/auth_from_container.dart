import 'package:flutter/material.dart';

import '../generated/assets.gen.dart';

class AuthFormContainer extends StatelessWidget {
  const AuthFormContainer({
    required this.title,
    required this.children,
    this.placeholder,
    super.key,
  });

  final SvgGenImage? placeholder;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (placeholder != null) ...[
            const SizedBox(height: 32),
            placeholder!.svg(height: 180),
            const SizedBox(height: 32),
          ],
          SizedBox(
            width: 320,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                ...children,
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
