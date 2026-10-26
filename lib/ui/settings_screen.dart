import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/format.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import '../core/timetable.dart' show dateOnly;
import '../core/version.dart';
import '../lms/changes.dart';
import '../lms/models.dart';
import '../services/automation.dart';
import '../services/background_login.dart';
import '../services/notifier.dart';
import '../services/server_link.dart';
import 'ai_settings_page.dart';
import 'automation_page.dart';
import 'lms_web_page.dart';
import 'server_page.dart';
import 'theme_picker.dart';
import 'widgets.dart';

export 'ai_settings_page.dart' show AiSettingsPage;

/// Profile (student info, tuition contract) and all app settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final snap = app.snapshot;
    final i = snap.info;
    final infoRows = i == null ? const <_InfoItem>[] : _infoItems(i, s);
    // Current academic year first, the rest in the LMS's order.
    final contracts = [...snap.contracts.where((c) => c.current), ...snap.contracts.where((c) => !c.current)];

    final hasLeft = infoRows.isNotEmpty || contracts.isNotEmpty;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (infoRows.isNotEmpty) ...[
        SectionHeader(s['pfStudentInfo']),
        _InfoCard(items: infoRows),
      ],
      if (contracts.isNotEmpty) ...[
        SectionHeader(s['pfContracts']),
        ResponsiveGrid(minItemWidth: 340, children: [for (final c in contracts) _ContractCard(c)]),
      ],
    ]);
    const right = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_SettingsSections()]);

    return PageScaffold(
      title: s['profile'],
      lmsPath: '/student/info',
      children: [
        _ProfileHeader(info: i),
        LayoutBuilder(builder: (context, c) {
          if (!hasLeft) return right;
          if (c.maxWidth < 900) return Column(children: [left, right]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            const Expanded(child: right),
          ]);
        }),
        if (snap.updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(s.f('updated', {'time': fmtAgo(snap.updatedAt, s)}),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- header

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({this.info});
  final StudentInfo? info;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final i = info;
    final white70 = Colors.white.withValues(alpha: 0.8);
    final name = _clean(i?.fullName);
    final spec = _clean(i?.specialization);
    final group = _clean(i?.group);
    final id = _clean(i?.studentId);
    final year = _clean(i?.year);
    final degree = _clean(i?.degree);
    return HeroCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Avatar(photo: i?.photo, name: name),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name ?? s['student'],
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.4)),
              if (spec != null) ...[
                const SizedBox(height: 4),
                Text(spec, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: white70, fontSize: 13.5)),
              ],
            ]),
          ),
        ]),
        if (group != null || id != null || year != null || degree != null) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (group != null) _HeroChip(icon: Icons.groups_rounded, text: '${s['group']}: $group'),
            if (id != null)
              _HeroChip(
                icon: Icons.badge_rounded,
                text: 'ID $id',
                tooltip: s['copy'],
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: id));
                  messenger.showSnackBar(SnackBar(content: Text(s['copied']), duration: const Duration(seconds: 2)));
                },
              ),
            if (year != null)
              _HeroChip(
                icon: Icons.school_rounded,
                text: RegExp(r'^\d+$').hasMatch(year) ? s.f('pfYearN', {'n': year}) : year,
              ),
            if (degree != null) _HeroChip(icon: Icons.workspace_premium_rounded, text: degree),
          ]),
        ],
      ]),
    );
  }
}

String? _clean(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.text, this.onTap, this.tooltip});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 5),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Explicit: the Material around a tappable chip resets the inherited text colour.
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white)),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 5),
          Icon(Icons.copy_rounded, size: 12, color: Colors.white.withValues(alpha: 0.8)),
        ],
      ]),
    );
    if (onTap != null) {
      chip = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: chip),
      );
    }
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}

/// Student photo (data: URI or URL) with an initials fallback for any error.
class _Avatar extends StatefulWidget {
  const _Avatar({this.photo, this.name});
  final String? photo;
  final String? name;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  static const _size = 76.0;
  String? _src;
  ImageProvider? _img;

  /// Decoded once per photo string, so rebuilds don't reload (and flicker) the image.
  ImageProvider? _provider() {
    final p = widget.photo?.trim();
    if (p == _src) return _img;
    _src = p;
    _img = null;
    if (p == null || p.isEmpty) return null;
    try {
      if (p.startsWith('data:')) {
        final bytes = UriData.parse(p).contentAsBytes();
        if (bytes.isNotEmpty) _img = MemoryImage(bytes);
      } else {
        final u = Uri.tryParse(p);
        if (u != null && (u.scheme == 'http' || u.scheme == 'https')) _img = NetworkImage(p);
      }
    } catch (_) {
      _img = null;
    }
    return _img;
  }

  String _initials() {
    final parts = (widget.name ?? '').split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2);
    return parts.map((e) => e.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final img = _provider();
    final initials = _initials();
    final fallback = Container(
      color: Colors.white.withValues(alpha: 0.2),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? const Icon(Icons.person_rounded, size: 38, color: Colors.white)
          : Text(initials, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
    );
    return Container(
      width: _size,
      height: _size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.35)),
      child: ClipOval(
        child: img == null
            ? fallback
            : Image(
                image: img,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- student info

class _InfoItem {
  const _InfoItem(this.icon, this.color, this.label, this.value);
  final IconData icon;
  final Color color;
  final String label;
  final String value;
}

List<_InfoItem> _infoItems(StudentInfo i, S s) => [
      for (final (icon, color, label, value) in [
        (Icons.cake_rounded, const Color(0xFFEC4899), s['birthDate'], i.birthDate),
        (Icons.wc_rounded, Brand.info, s['pfGender'], i.gender),
        (Icons.school_rounded, Brand.primary, s['studyForm'], i.studyForm),
        (Icons.translate_rounded, const Color(0xFF14B8A6), s['studyLanguage'], i.studyLanguage),
        (Icons.workspace_premium_rounded, Brand.warning, s['degree'], i.degree),
        (Icons.timeline_rounded, Brand.violet, s['year'], i.year),
        (Icons.supervisor_account_rounded, Brand.primaryDeep, s['tutor'], i.tutor),
        (Icons.payments_rounded, Brand.success, s['stipend'], i.stipend),
        (Icons.home_rounded, const Color(0xFFF97316), s['pfAddress'], i.address),
        (Icons.location_on_rounded, Brand.danger, s['pfTempAddress'], i.tempAddress),
      ])
        if (_clean(value) case final v?) _InfoItem(icon, color, label, v),
    ];

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.items});
  final List<_InfoItem> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 2 : 1;
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(spacing: 12, children: [
          for (final it in items)
            SizedBox(
              width: w,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TintIcon(it.icon, color: it.color, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.label,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      SelectableText(it.value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    ]),
                  ),
                ]),
              ),
            ),
        ]);
      }),
    );
  }
}

// ---------------------------------------------------------------- tuition contract

class _ContractCard extends StatelessWidget {
  const _ContractCard(this.c);
  final ContractYear c;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final currency = _clean(c.currency) ?? s['pfCurrency'];
    final total = c.total, paid = c.paid, debt = c.debt;
    final pct = c.paidPercent ?? ((total != null && total > 0 && paid != null) ? paid / total * 100 : null);
    final hasDebt = (debt ?? 0) > 0;
    final fullyPaid = !hasDebt && ((pct ?? 0) >= 99.5 || (debt != null && debt <= 0));
    final color = !c.hasData
        ? cs.outline
        : hasDebt
            ? Brand.danger
            : fullyPaid
                ? Brand.success
                : Brand.warning;
    final status = _clean(c.status);
    final notice = _clean(c.notice);

    Widget money(String label, double? v, Color valueColor) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500))),
            Text(v == null ? '—' : '${fmtMoney(v)} $currency',
                style: TextStyle(fontWeight: FontWeight.w800, color: valueColor, fontSize: 15)),
          ]),
        );

    return AppCard(
      accent: c.current ? color : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TintIcon(Icons.account_balance_wallet_rounded, color: c.current ? Brand.primary : cs.outline, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.year, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (status != null) ...[
                const SizedBox(height: 4),
                Tag(status, color: color, icon: fullyPaid ? Icons.check_circle_rounded : null),
              ],
            ]),
          ),
          if (c.current) ...[const SizedBox(width: 8), Tag(s['pfCurrent'], color: Brand.primary, filled: true)],
        ]),
        if (c.hasData) ...[
          const SizedBox(height: 12),
          money(s['pfTotal'], total, cs.onSurface),
          money(s['pfPaid'], paid, Brand.success),
          money(s['pfDebt'], debt, hasDebt ? Brand.danger : cs.onSurfaceVariant),
          if (pct != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Bar(value: pct / 100, color: fullyPaid ? Brand.success : Brand.primary)),
              const SizedBox(width: 10),
              Text(s.f('pfPaidPct', {'pct': fmtNum(pct)}),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: cs.onSurfaceVariant)),
            ]),
          ],
        ] else ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 17, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(notice ?? s['pfNoContract'], style: TextStyle(color: cs.onSurfaceVariant))),
          ]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- settings

class _SettingsSections extends StatelessWidget {
  const _SettingsSections();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final st = app.settings;
    final cs = Theme.of(context).colorScheme;
    final semesters = app.snapshot.semesters;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ---- account
      SectionHeader(s['pfAccount']),
      _Group([
        if (semesters.length > 1)
          _ChoiceRow<int>(
            icon: Icons.date_range_rounded,
            color: Brand.primary,
            title: s['semester'],
            value: app.snapshot.semesterId,
            valueBelow: true,
            notifySame: true,
            options: [
              for (final sem in semesters) (sem.id, sem.selected ? '${sem.name} · ${s['pfCurrent']}' : sem.name),
            ],
            onChanged: (v) {
              // Picking the LMS's current semester means "follow the LMS", not "pin this one".
              final current = semesters.where((x) => x.selected).map((x) => x.id).firstOrNull;
              final target = v == current ? null : v;
              // After a failed sync the shown semester differs from the saved
              // choice; picking the shown one again must undo that choice.
              if (target == app.settings.semesterId && v == app.snapshot.semesterId) return;
              app.changeSemester(target);
            },
          ),
        _Row(
          icon: Icons.logout_rounded,
          color: cs.error,
          title: s['logout'],
          titleColor: cs.error,
          subtitle: s['pfLogoutSub'],
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                icon: Icon(Icons.logout_rounded, color: cs.error),
                content: Text(s['logoutConfirm'], textAlign: TextAlign.center),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(s['logout']),
                  ),
                ],
              ),
            );
            if (ok == true) await app.logout();
          },
        ),
      ]),

      // ---- sign-in and sync
      SectionHeader(s['slTitle']),
      const _SignInGroup(),
      SectionHeader(s['syTitle']),
      const _SyncGroup(),

      // ---- appearance
      SectionHeader(s['pfAppearance']),
      _Group([
        _ChoiceRow<String>(
          icon: Icons.translate_rounded,
          color: const Color(0xFF14B8A6),
          title: s['language'],
          value: st.language,
          options: [for (final e in S.languages.entries) (e.key, e.value)],
          onChanged: (v) => app.setLanguage(v),
        ),
        _Row(
          icon: Icons.palette_outlined,
          color: Brand.primary,
          title: s['thStyle'],
          subtitle: s[styleSpecs[app.style]!.nameKey],
          onTap: () => showThemePicker(context),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        _Row(
          icon: Icons.dark_mode_rounded,
          color: Brand.violet,
          title: s['thMode'],
          trailing: _ThemeSwitch(value: st.themeMode, onChanged: (v) => app.setThemeMode(v)),
        ),
      ]),

      // ---- notifications
      SectionHeader(s['notifications']),
      _Group([
        _SwitchRow(
          icon: Icons.notifications_active_rounded,
          color: Brand.primary,
          title: s['notifications'],
          subtitle: '${s['notificationsSub']}${Platform.isAndroid ? '' : '\n${s['desktopNote']}'}',
          value: st.notifications,
          onChanged: (v) async {
            st.notifications = v;
            app.touch();
            if (v) await Notifier.requestPermission();
            await app.configureBackground();
            await Notifier.scheduleClassReminders(app.snapshot, st); // cancels them when off
          },
        ),
        _ChoiceRow<int>(
          icon: Icons.timer_rounded,
          color: Brand.info,
          title: s['checkEvery'],
          value: st.checkMinutes,
          options: [
            for (final m in ({...const [15, 30, 60, 120], st.checkMinutes}.toList()..sort())) (m, '$m ${s['minutes']}'),
          ],
          onChanged: (v) async {
            st.checkMinutes = v;
            app.touch();
            await app.configureBackground();
          },
        ),
        _SwitchRow(
          icon: Icons.bedtime_outlined,
          color: Brand.violet,
          title: s['nfQuiet'],
          subtitle: s.f('nfQuietSub', {'from': _hhmm(st.quietFrom), 'to': _hhmm(st.quietTo)}),
          value: st.quietHours,
          onChanged: (v) async {
            st.quietHours = v;
            app.touch();
            await Notifier.scheduleMorningBrief(app.snapshot, st);
          },
        ),
        if (st.quietHours)
          _Row(
            icon: Icons.schedule_rounded,
            color: Brand.violet,
            title: '${s['nfQuietFrom']} – ${s['nfQuietTo']}',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _TimeChip(minutes: st.quietFrom, onChanged: (m) {
                st.quietFrom = m;
                app.touch();
              }),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('–')),
              _TimeChip(minutes: st.quietTo, onChanged: (m) {
                st.quietTo = m;
                app.touch();
              }),
            ]),
          ),
        _SwitchRow(
          icon: Icons.wb_twilight_rounded,
          color: Brand.warning,
          title: s['nfBrief'],
          subtitle: s.f('nfBriefSub', {'time': _hhmm(st.briefAt)}),
          value: st.morningBrief,
          onChanged: (v) async {
            st.morningBrief = v;
            app.touch();
            await Notifier.scheduleMorningBrief(app.snapshot, st);
          },
        ),
        if (st.morningBrief)
          _Row(
            icon: Icons.alarm_on_rounded,
            color: Brand.warning,
            title: s['nfBriefAt'],
            trailing: _TimeChip(minutes: st.briefAt, onChanged: (m) async {
              st.briefAt = m;
              app.touch();
              await Notifier.scheduleMorningBrief(app.snapshot, st);
            }),
          ),
        _Row(
          icon: Icons.tune_rounded,
          color: Brand.info,
          title: s['nfKinds'],
          subtitle: s['nfKindsSub'],
          trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          onTap: () => _pickKinds(context),
        ),
        if (Platform.isWindows)
          _SwitchRow(
            icon: Icons.move_to_inbox_rounded,
            color: Brand.primary,
            title: s['nfTray'],
            subtitle: s['nfTraySub'],
            value: st.closeToTray,
            onChanged: (v) {
              st.closeToTray = v;
              app.touch();
            },
          ),
        _SwitchRow(
          icon: Icons.alarm_rounded,
          color: Brand.warning,
          title: s['remindDeadlines'],
          value: st.remindDeadlines,
          onChanged: (v) {
            st.remindDeadlines = v;
            app.touch();
          },
        ),
        _SwitchRow(
          icon: Icons.class_rounded,
          color: Brand.success,
          title: s['remindClasses'],
          value: st.remindClasses,
          onChanged: (v) async {
            st.remindClasses = v;
            app.touch();
            await Notifier.scheduleClassReminders(app.snapshot, st);
          },
        ),
        _Row(
          icon: Icons.notification_add_rounded,
          color: Brand.violet,
          title: s['testNotification'],
          trailing: Icon(Icons.send_rounded, size: 20, color: cs.onSurfaceVariant),
          onTap: () async {
            await Notifier.requestPermission();
            await Notifier.show('test', 'TuitMate', s['testNotificationBody']);
          },
        ),
      ]),

      // ---- timetable & attendance
      SectionHeader('${s['schedule']} · ${s['attendance']}'),
      _Group([
        _NumberRow(
          icon: Icons.av_timer_rounded,
          color: Brand.primary,
          title: s['lessonLength'],
          value: st.lessonMinutes,
          suffix: s['minutes'],
          options: const [45, 50, 80, 90],
          onChanged: (v) {
            st.lessonMinutes = v;
            app.touch();
          },
        ),
        _NumberRow(
          icon: Icons.event_busy_rounded,
          color: Brand.danger,
          title: s['absenceLimit'],
          value: st.absenceLimitHours,
          options: const [36, 48, 60, 74, 80, 100],
          onChanged: (v) {
            st.absenceLimitHours = v;
            app.touch();
          },
        ),
        _NumberRow(
          icon: Icons.looks_two_rounded,
          color: Brand.warning,
          title: s['hoursPerNb'],
          value: st.hoursPerAbsence,
          options: const [1, 2, 3, 4],
          onChanged: (v) {
            st.hoursPerAbsence = v;
            app.touch();
          },
        ),
      ]),

      // ---- AI assistant
      SectionHeader(s['assistant']),
      _Group([
        _Row(
          icon: Icons.auto_awesome_rounded,
          color: Brand.violet,
          title: s['aiSettings'],
          subtitle: st.aiSummary,
          trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiSettingsPage())),
        ),
        _SwitchRow(
          icon: Icons.dataset_linked_rounded,
          color: Brand.primary,
          title: s['useLmsData'],
          subtitle: s['pfUseLmsDataSub'],
          value: st.aiUseLmsContext,
          onChanged: (v) {
            st.aiUseLmsContext = v;
            app.touch();
          },
        ),
      ]),

      // ---- automation (owner only)
      if (st.adminUnlocked) ...[
        SectionHeader(s['auTitle']),
        _Group([
          _Row(
            icon: Icons.hub_outlined,
            color: Brand.primary,
            title: s['auSettingsRow'],
            subtitle: st.webhookUrl == null ? s['auSettingsSub'] : Uri.tryParse(st.webhookUrl!)?.host ?? st.webhookUrl!,
            trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            onTap: () => AutomationPage.open(context),
          ),
        ]),
      ],

      // ---- about
      SectionHeader(s['about']),
      _Group([
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.onSurface, borderRadius: BorderRadius.circular(radiusS)),
                child: Text('T', style: TextStyle(fontFamily: brandFont, fontSize: 26, fontWeight: FontWeight.w700, color: cs.surface, height: 1)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['appName'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  const _VersionLine(),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Text(s['aboutBody'], style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.shield_outlined, size: 16, color: Brand.warning),
              const SizedBox(width: 6),
              Expanded(child: Text(s['unofficial'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            ]),
          ]),
        ),
        _Row(
          icon: Icons.public_rounded,
          color: Brand.info,
          title: s['openInLms'],
          subtitle: 'lms.tuit.uz',
          trailing: Icon(Icons.open_in_new_rounded, size: 20, color: cs.onSurfaceVariant),
          onTap: () => LmsWebPage.open(context),
        ),
      ]),
    ]);
  }
}

/// Settings rows in one card, separated by hairlines.
/// Saved LMS login and password, automatic sign-in, and how it went last.
class _SignInGroup extends StatefulWidget {
  const _SignInGroup();

  @override
  State<_SignInGroup> createState() => _SignInGroupState();
}

class _SignInGroupState extends State<_SignInGroup> {
  String? _login;
  bool _hasPassword = false;
  LoginStatus _status = const LoginStatus();
  bool _busy = false;

  // Reload after each sync or sign-in (the background may have signed in).
  DateTime? _seenSync;
  bool? _seenExpired;

  Future<void> _load() async {
    final storage = context.read<AppState>().storage;
    final login = await Secrets.read(Secrets.lmsLogin);
    final pass = await Secrets.read(Secrets.lmsPassword);
    final status = await BackgroundLogin.status(storage);
    if (!mounted) return;
    setState(() {
      _login = login;
      _hasPassword = (pass ?? '').isNotEmpty;
      _status = status;
    });
  }

  bool get _saved => (_login ?? '').isNotEmpty && _hasPassword;

  String _when(DateTime t, S s) =>
      dateOnly(t) == dateOnly(DateTime.now()) ? fmtTime(t) : fmtDateTime(t, s.lang);

  Future<void> _edit() async {
    final app = context.read<AppState>();
    final s = S.read(context);
    final login = TextEditingController(text: _login ?? '');
    final pass = TextEditingController();
    var show = false;
    final saved = _saved;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) {
        final ready = login.text.trim().isNotEmpty && (pass.text.isNotEmpty || _hasPassword);
        return AlertDialog(
          title: Text(s['slSaved']),
          content: SizedBox(
            width: 380,
            child: AutofillGroup(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: login,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: s['slLogin'], prefixIcon: const Icon(Icons.badge_outlined)),
                  onChanged: (_) => setDialog(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pass,
                  obscureText: !show,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: s['slPassword'],
                    helperText: _hasPassword ? s['slKeepPassword'] : null,
                    prefixIcon: const Icon(Icons.password_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setDialog(() => show = !show),
                    ),
                  ),
                  onChanged: (_) => setDialog(() {}),
                  onSubmitted: (_) {
                    if (ready) Navigator.pop(ctx, 'save');
                  },
                ),
                const SizedBox(height: 12),
                Text(s['slStoredSafely'], style: TextStyle(fontSize: 12.5, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ]),
            ),
          ),
          actions: [
            if (saved) TextButton(onPressed: () => Navigator.pop(ctx, 'remove'), child: Text(s['slRemove'])),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s['cancel'])),
            FilledButton(onPressed: ready ? () => Navigator.pop(ctx, 'save') : null, child: Text(s['save'])),
          ],
        );
      }),
    );
    final l = login.text, p = pass.text;
    login.dispose();
    pass.dispose();
    if (action == 'save') {
      await app.saveLogin(l, p);
    } else if (action == 'remove') {
      await app.forgetLogin();
    }
    await _load();
  }

  Future<void> _tryNow() async {
    final app = context.read<AppState>();
    final s = S.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final ok = await app.signInNow();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(ok ? s['slTryOk'] : s['slTryFail'])));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final st = app.settings;
    if (_seenSync != app.snapshot.updatedAt || _seenExpired != app.sessionExpired) {
      _seenSync = app.snapshot.updatedAt;
      _seenExpired = app.sessionExpired;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final auto = st.autoLogin && st.backgroundLogin;
    final failing = _status.failures > 0 && _status.result != LoginResult.ok;
    final why = switch (_status.result) {
      LoginResult.refused => s['slWhyRefused'],
      LoginResult.timeout => s['slWhyTimeout'],
      _ => s['slWhyError'],
    };
    final okAt = _status.okAt;
    final next = _status.nextTry;
    return _Group([
      _Row(
        icon: Icons.key_rounded,
        color: Brand.violet,
        title: s['slSaved'],
        subtitle: _saved ? s.f('slSavedAs', {'login': _login}) : s['slNotSaved'],
        onTap: _edit,
        trailing: TextButton(onPressed: _edit, child: Text(_saved ? s['slChange'] : s['slAdd'])),
      ),
      _SwitchRow(
        icon: Icons.sync_lock_rounded,
        color: Brand.success,
        title: s['slAuto'],
        subtitle: s['slAutoSub'],
        value: auto,
        onChanged: (v) {
          st.autoLogin = v;
          st.backgroundLogin = v;
          app.touch();
        },
      ),
      if (_saved && auto)
        _Row(
          icon: failing ? Icons.error_outline_rounded : Icons.verified_user_outlined,
          color: failing ? Brand.warning : Brand.success,
          title: failing
              ? s.f('slFailed', {'why': why, 'time': next == null ? '—' : _when(next, s)})
              : okAt != null
                  ? s.f('slLastOk', {'time': _when(okAt, s)})
                  : s['slNever'],
          trailing: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              : TextButton(onPressed: _tryNow, child: Text(s['slTryNow'])),
        ),
    ]);
  }
}

/// When LMS was last checked, how often it is checked, and "check everything now".
class _SyncGroup extends StatelessWidget {
  const _SyncGroup();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = S.of(context);
    final st = app.settings;
    final snap = app.snapshot;
    final at = snap.updatedAt, full = snap.fullAt;
    final everything = at != null && full != null && at.difference(full).inSeconds.abs() < 120;
    final open = min(st.checkMinutes, AppState.openCheckMinutes).clamp(5, 240);
    final closedOn = st.notifications || Automation.active(st);
    final failed = app.failedParts;
    return _Group([
      _Row(
        icon: Icons.update_rounded,
        color: Brand.info,
        title: s['syLast'],
        subtitle: [fmtAgo(at, s), if (everything) s['syEverything'], if (app.fromServer) s['srvVia']].join(' · '),
      ),
      _Row(
        icon: Icons.folder_copy_outlined,
        color: Brand.violet,
        title: s['syFullAt'],
        subtitle: '${fmtAgo(full, s)} · ${s['syFullEvery']}',
      ),
      _Row(
        icon: Icons.timer_outlined,
        color: Brand.primary,
        title: s.f(Platform.isAndroid ? 'syOpen' : 'syOpenPc', {'n': open}),
        subtitle: Platform.isAndroid
            ? (closedOn ? s.f('syClosed', {'n': max(15, st.checkMinutes)}) : s['syClosedOff'])
            : null,
      ),
      if (failed.isNotEmpty)
        _Row(
          icon: Icons.sync_problem_rounded,
          color: Brand.warning,
          title: s.f('syPartsFailed', {'parts': syncPartLabels(failed, snap, s).join(', ')}),
        ),
      const _ServerRow(),
      _Row(
        icon: Icons.cloud_sync_rounded,
        color: Brand.success,
        title: s['syNow'],
        onTap: app.syncing ? null : () => app.refresh(full: true),
        trailing: app.syncing
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
            : const Icon(Icons.chevron_right_rounded),
      ),
    ]);
  }
}

/// Your TuitMate server: connect, or open its page.
class _ServerRow extends StatefulWidget {
  const _ServerRow();

  @override
  State<_ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends State<_ServerRow> {
  ServerConfig? _config;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ServerLink.load();
    if (mounted) setState(() => _config = c);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = _config;
    return _Row(
      icon: Icons.dns_outlined,
      color: Brand.violet,
      title: s['srvTitle'],
      subtitle: c == null ? s['srvNotConnected'] : s.f('srvConnectedTo', {'host': c.host}),
      onTap: () async {
        await openServer(context);
        await _load();
      },
      trailing: c == null
          ? TextButton(
              onPressed: () async {
                await openServer(context);
                await _load();
              },
              child: Text(s['srvConnect']))
          : const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, w) in children.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 66),
          w,
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(children: [
          TintIcon(icon, color: color, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: titleColor)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _Row(
        icon: icon,
        color: color,
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      );
}

/// Row that opens a bottom-sheet list of options.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.valueBelow = false,
    this.notifySame = false,
  });
  final IconData icon;
  final Color color;
  final String title;
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  /// Show the current value under the title (for long values) instead of on the right.
  final bool valueBelow;

  /// Also report picking the value already shown.
  final bool notifySame;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = options.where((o) => o.$1 == value).map((o) => o.$2).firstOrNull ?? '—';
    return _Row(
      icon: icon,
      color: color,
      title: title,
      subtitle: valueBelow ? label : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!valueBelow)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(width: 2),
        Icon(Icons.unfold_more_rounded, size: 20, color: cs.onSurfaceVariant),
      ]),
      onTap: () async {
        final v = await _pickOption<T>(context, title, options, value);
        if (v != null && (notifySame || v != value)) onChanged(v);
      },
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.suffix,
  });
  final IconData icon;
  final Color color;
  final String title;
  final int value;
  final List<int> options;
  final String? suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final opts = {...options, value}.toList()..sort();
    return _ChoiceRow<int>(
      icon: icon,
      color: color,
      title: title,
      value: value,
      options: [for (final o in opts) (o, suffix == null ? '$o' : '$o $suffix')],
      onChanged: onChanged,
    );
  }
}

Future<T?> _pickOption<T>(BuildContext context, String title, List<(T, String)> options, T? current) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final (v, label) in options)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusS)),
                selected: v == current,
                selectedTileColor: cs.primary.withValues(alpha: 0.08),
                title: Text(label, style: TextStyle(fontWeight: v == current ? FontWeight.w700 : FontWeight.w500)),
                trailing: v == current ? Icon(Icons.check_rounded, color: cs.primary) : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
          ]),
        ),
      );
    },
  );
}

/// System / light / dark as a compact icon segmented control.
class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch({required this.value, required this.onChanged});
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final items = [
      (ThemeMode.system, Icons.brightness_auto_rounded, s['themeSystem']),
      (ThemeMode.light, Icons.light_mode_rounded, s['themeLight']),
      (ThemeMode.dark, Icons.dark_mode_rounded, s['themeDark']),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(radiusS)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (mode, icon, label) in items)
          Tooltip(
            message: label,
            child: Semantics(
              button: true,
              selected: value == mode,
              label: label,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 40,
                  decoration: BoxDecoration(
                    color: value == mode ? cs.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: value == mode ? cs.outlineVariant : Colors.transparent),
                  ),
                  child: Icon(icon, size: 18, color: value == mode ? cs.primary : cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

String _hhmm(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// A time of day that opens the time picker.
class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.minutes, required this.onChanged});
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: const Size(0, 40)),
      onPressed: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
        );
        if (t != null) onChanged(t.hour * 60 + t.minute);
      },
      child: Text(_hhmm(minutes), style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w700)),
    );
  }
}

/// Which kinds of updates notify (Settings.mutedKinds holds the ones turned off).
Future<void> _pickKinds(BuildContext context) {
  final app = context.read<AppState>();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      final s = S.of(ctx);
      final muted = app.settings.mutedKinds;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(s['nfKinds'], style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(s['nfKindsSub'], style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ),
            for (final k in ChangeKind.values)
              CheckboxListTile(
                title: Text(s['nfKind_${k.name}']),
                value: !muted.contains(k.name),
                onChanged: (v) {
                  final next = {...muted};
                  v == true ? next.remove(k.name) : next.add(k.name);
                  app.settings.mutedKinds = next;
                  app.touch();
                  setState(() {});
                },
              ),
          ]),
        ),
      );
    }),
  );
}

/// Version; tapping it 7 times asks for the owner's key (admin mode).
class _VersionLine extends StatefulWidget {
  const _VersionLine();

  @override
  State<_VersionLine> createState() => _VersionLineState();
}

class _VersionLineState extends State<_VersionLine> {
  int _taps = 0;
  DateTime? _last;

  Future<void> _tap() async {
    final now = DateTime.now();
    _taps = (_last != null && now.difference(_last!) < const Duration(seconds: 2)) ? _taps + 1 : 1;
    _last = now;
    if (_taps < 7) return;
    _taps = 0;
    final app = context.read<AppState>();
    if (app.settings.adminUnlocked) {
      await AutomationPage.open(context);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final s = S.read(context);
    if (await showAdminUnlock(context)) {
      messenger.showSnackBar(SnackBar(content: Text(s['auUnlocked'])));
      if (mounted) await AutomationPage.open(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return GestureDetector(
      onTap: _tap,
      behavior: HitTestBehavior.opaque,
      child: Text(s.f('pfVersion', {'v': appVersion}),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
    );
  }
}
