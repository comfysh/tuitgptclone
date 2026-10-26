import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/settings.dart';
import '../core/strings.dart';
import 'nav.dart';
import 'widgets.dart';

/// The parts of the Today screen, in their default order.
enum TodaySection { agenda, whatsNew, due, numbers, nextExam, debt, tomorrow, workload, attendance, news }

/// Shown by default; the others can be switched on in "Customize Today".
const _offByDefault = {TodaySection.workload, TodaySection.attendance, TodaySection.news};

/// On PC Today has two columns: the day (left) and everything else (right).
bool isDayColumn(TodaySection t) =>
    t == TodaySection.agenda || t == TodaySection.tomorrow || t == TodaySection.workload || t == TodaySection.attendance;

/// The sections in the saved order with on/off. Names the app no longer knows
/// are dropped; sections added in a later version join at the end with their
/// default.
List<(TodaySection, bool)> todayLayout(Settings settings) {
  final saved = settings.todayLayout;
  if (saved == null) return [for (final t in TodaySection.values) (t, !_offByDefault.contains(t))];
  final out = <(TodaySection, bool)>[];
  for (final e in saved) {
    final on = !e.startsWith('-');
    final t = TodaySection.values.where((t) => t.name == (on ? e : e.substring(1))).firstOrNull;
    if (t != null && !out.any((x) => x.$1 == t)) out.add((t, on));
  }
  for (final t in TodaySection.values) {
    if (!out.any((x) => x.$1 == t)) out.add((t, !_offByDefault.contains(t)));
  }
  return out;
}

void saveTodayLayout(Settings settings, List<(TodaySection, bool)>? layout) =>
    settings.todayLayout = layout == null ? null : [for (final (t, on) in layout) on ? t.name : '-${t.name}'];

String todaySectionLabel(TodaySection t, S s) => switch (t) {
      TodaySection.agenda => s['tdAgenda'],
      TodaySection.whatsNew => s['tdWhatsNew'],
      TodaySection.due => s['tdDueNext'],
      TodaySection.numbers => s['tlNumbers'],
      TodaySection.nextExam => s['tlNextExam'],
      TodaySection.debt => s['tlDebt'],
      TodaySection.tomorrow => s['tdTomorrow'],
      TodaySection.workload => s['wlTitle'],
      TodaySection.attendance => s['tlAttendance'],
      TodaySection.news => s['tlNews'],
    };

IconData todaySectionIcon(TodaySection t) => switch (t) {
      TodaySection.agenda => Icons.view_agenda_outlined,
      TodaySection.whatsNew => Icons.inbox_outlined,
      TodaySection.due => Icons.assignment_outlined,
      TodaySection.numbers => Icons.grid_view_rounded,
      TodaySection.nextExam => Icons.fact_check_outlined,
      TodaySection.debt => Icons.account_balance_wallet_outlined,
      TodaySection.tomorrow => Icons.wb_twilight_rounded,
      TodaySection.workload => Icons.bar_chart_rounded,
      TodaySection.attendance => Icons.event_busy_outlined,
      TodaySection.news => Icons.campaign_outlined,
    };

/// "Customize Today": the place the app opens on, and Today's sections to
/// reorder (drag) and switch on or off.
Future<void> showTodayCustomizer(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.9, child: _Customizer()),
    );

class _Customizer extends StatefulWidget {
  const _Customizer();

  @override
  State<_Customizer> createState() => _CustomizerState();
}

class _CustomizerState extends State<_Customizer> {
  late List<(TodaySection, bool)> _layout;

  @override
  void initState() {
    super.initState();
    _layout = todayLayout(context.read<AppState>().settings);
  }

  void _save(List<(TodaySection, bool)>? layout) {
    final app = context.read<AppState>();
    saveTodayLayout(app.settings, layout);
    setState(() => _layout = todayLayout(app.settings));
    app.touch();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
        child: Row(children: [
          Expanded(child: Text(s['tlCustomize'], style: Theme.of(context).textTheme.titleLarge)),
          TextButton(onPressed: settingsDefault(app.settings) ? null : () => _save(null), child: Text(s['tlReset'])),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Text(s['tlStart'], style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final h in Hub.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(hubInfo[h]!.icon, size: 18),
                label: Text(s[hubInfo[h]!.key]),
                selected: app.settings.startHub == h.name,
                onSelected: (_) {
                  app.settings.startHub = h.name;
                  app.touch();
                },
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(s['tlDrag'], style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      ),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          buildDefaultDragHandles: false,
          itemCount: _layout.length,
          onReorderItem: (from, to) {
            // [to] already accounts for the item taken out at [from].
            final l = [..._layout];
            l.insert(to, l.removeAt(from));
            _save(l);
          },
          itemBuilder: (context, i) {
            final (t, on) = _layout[i];
            return Padding(
              key: ValueKey(t),
              padding: const EdgeInsets.only(bottom: 6),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(Icons.drag_indicator_rounded, color: cs.onSurfaceVariant),
                    ),
                  ),
                  Icon(todaySectionIcon(t), size: 20, color: on ? cs.onSurface : cs.outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(todaySectionLabel(t, s),
                        style: TextStyle(fontWeight: FontWeight.w600, color: on ? cs.onSurface : cs.onSurfaceVariant)),
                  ),
                  Switch(
                    value: on,
                    onChanged: (v) => _save([for (final e in _layout) e.$1 == t ? (t, v) : e]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  /// Nothing to reset: default sections and order.
  static bool settingsDefault(Settings settings) => settings.todayLayout == null;
}
