import 'package:flutter/material.dart';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class ErrorText extends StatelessWidget {
  final String message;
  const ErrorText(this.message, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );
}

/// Full screen message with an optional action, for loading and errors.
class CenteredMessage extends StatelessWidget {
  final IconData? icon;
  final String message;
  final List<Widget> actions;
  final bool loading;

  const CenteredMessage({
    super.key,
    this.icon,
    required this.message,
    this.actions = const [],
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) const CircularProgressIndicator(),
          if (icon != null) Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ...actions,
        ],
      ),
    ),
  );
}
