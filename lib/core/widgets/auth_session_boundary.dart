import 'package:flutter/material.dart';

/// Clears private route state whenever the signed-in identity changes.
class AuthSessionBoundary extends StatefulWidget {
  const AuthSessionBoundary({
    super.key,
    required this.sessionId,
    required this.onSessionChanged,
    required this.child,
  });
  final String? sessionId;
  final VoidCallback onSessionChanged;
  final Widget child;
  @override
  State<AuthSessionBoundary> createState() => _AuthSessionBoundaryState();
}

class _AuthSessionBoundaryState extends State<AuthSessionBoundary> {
  @override
  void didUpdateWidget(covariant AuthSessionBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId == widget.sessionId) return;
    widget.onSessionChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
