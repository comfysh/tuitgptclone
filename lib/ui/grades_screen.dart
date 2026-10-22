import 'package:flutter/material.dart';

import '../core/strings.dart';
import 'widgets.dart';

/// Grades, GPA and the study plan.
class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key});

  @override
  Widget build(BuildContext context) => PageScaffold(title: S.of(context)['navGrades'], children: const []);
}
