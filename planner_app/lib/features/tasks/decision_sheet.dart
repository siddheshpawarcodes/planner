import 'package:flutter/material.dart';

/// DecisionSheet (README 6.6). Built in milestone 6.
class DecisionSheet extends StatelessWidget {
  const DecisionSheet({super.key, required this.taskId, required this.reschedule});
  final String taskId;
  final bool reschedule;

  @override
  Widget build(BuildContext context) => const SizedBox(height: 120);
}
