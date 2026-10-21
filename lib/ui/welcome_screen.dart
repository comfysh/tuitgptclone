import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/strings.dart';
import 'lms_web_page.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final app = context.watch<AppState>();
    final features = [
      (Icons.calendar_month, s['schedule']),
      (Icons.assignment, s['deadlines']),
      (Icons.school, s['courses']),
      (Icons.event_busy, s['attendance']),
      (Icons.fact_check, s['exams']),
      (Icons.notifications_active, s['notifications']),
      (Icons.auto_awesome, s['assistant']),
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
              Align(
                alignment: Alignment.centerRight,
                child: DropdownButton<String>(
                  value: app.language,
                  underline: const SizedBox(),
                  items: [for (final e in S.languages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => app.setLanguage(v!),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(color: lmsBlue, borderRadius: BorderRadius.circular(24)),
                  child: const Icon(Icons.school, color: Colors.white, size: 46),
                ),
              ),
              const SizedBox(height: 18),
              Text('TuitMate', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(s['welcomeTitle'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text(s['welcomeBody'], textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                for (final f in features) Chip(avatar: Icon(f.$1, size: 18), label: Text(f.$2)),
              ]),
              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: app.wiping ? null : () => LmsWebPage.login(context),
                icon: const Icon(Icons.login),
                label: Text(s['signIn']),
              ),
              const SizedBox(height: 12),
              Text(s['signInNote'], textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 18),
              Text(s['unofficial'], textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
            ]),
          ),
        ),
      ),
    );
  }
}
