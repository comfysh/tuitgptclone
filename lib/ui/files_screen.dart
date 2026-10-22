import 'package:flutter/material.dart';

import '../core/strings.dart';
import 'widgets.dart';

/// All teacher files of the semester.
class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) => PageScaffold(title: S.of(context)['navFiles'], children: const []);
}
