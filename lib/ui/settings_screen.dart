import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_service.dart';
import '../app_state.dart';
import '../core/format.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../core/strings.dart';
import '../lms/models.dart';
import '../services/notifier.dart';
import 'lms_web_page.dart';
import 'widgets.dart';

/// Shown in About (keep in sync with pubspec.yaml).
const _appVersion = '1.0.0';

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
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
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
        _SwitchRow(
          icon: Icons.password_rounded,
          color: Brand.violet,
          title: s['rememberPassword'],
          value: st.rememberPassword,
          onChanged: (v) {
            st.rememberPassword = v;
            if (!v) Secrets.deleteLms();
            app.touch();
          },
        ),
        _SwitchRow(
          icon: Icons.login_rounded,
          color: Brand.info,
          title: s['autoLogin'],
          value: st.autoLogin,
          onChanged: (v) {
            st.autoLogin = v;
            app.touch();
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
          icon: Icons.dark_mode_rounded,
          color: Brand.violet,
          title: s['theme'],
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
          subtitle: st.aiProvider == AiProvider.gemini
              ? 'Google Gemini · ${st.geminiModel}'
              : '${st.openaiBaseUrl} · ${st.openaiModel}',
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
                decoration: BoxDecoration(gradient: Brand.heroFor(context), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.school_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['appName'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  Text(s.f('pfVersion', {'v': _appVersion}), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
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
                    boxShadow: value == mode
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 1))]
                        : null,
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

// ---------------------------------------------------------------- AI settings

/// AI provider, key and model.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _geminiKey = TextEditingController();
  final _openaiKey = TextEditingController();
  final _geminiModel = TextEditingController();
  final _openaiModel = TextEditingController();
  final _openaiBase = TextEditingController();
  List<String> _models = [];
  String? _status;
  bool _busy = false;

  static const _presets = {
    'Groq (free tier)': ('https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile', 'https://console.groq.com/keys'),
    'OpenRouter': ('https://openrouter.ai/api/v1', 'openrouter/auto', 'https://openrouter.ai/keys'),
    'OpenAI': ('https://api.openai.com/v1', 'gpt-4o-mini', 'https://platform.openai.com/api-keys'),
  };

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>().settings;
    _geminiModel.text = st.geminiModel;
    _openaiModel.text = st.openaiModel;
    _openaiBase.text = st.openaiBaseUrl;
    Secrets.read(Secrets.geminiKey).then((v) => _geminiKey.text = v ?? '');
    Secrets.read(Secrets.openaiKey).then((v) => _openaiKey.text = v ?? '');
  }

  @override
  void dispose() {
    for (final c in [_geminiKey, _openaiKey, _geminiModel, _openaiModel, _openaiBase]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _persist() async {
    final st = context.read<AppState>().settings;
    await Secrets.write(Secrets.geminiKey, _geminiKey.text.trim());
    await Secrets.write(Secrets.openaiKey, _openaiKey.text.trim());
    if (_geminiModel.text.trim().isNotEmpty) st.geminiModel = _geminiModel.text.trim();
    if (_openaiModel.text.trim().isNotEmpty) st.openaiModel = _openaiModel.text.trim();
    if (_openaiBase.text.trim().isNotEmpty) st.openaiBaseUrl = _openaiBase.text.trim();
  }

  Future<void> _run(Future<void> Function(AiService ai) f) async {
    await _persist();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await f(AiService(context.read<AppState>().settings));
    } catch (e) {
      _status = '✗ $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final app = context.watch<AppState>();
    final st = app.settings;
    final gemini = st.aiProvider == AiProvider.gemini;
    final modelCtl = gemini ? _geminiModel : _openaiModel;
    final cs = Theme.of(context).colorScheme;
    final status = _status;

    void selectProvider(AiProvider p) {
      st.aiProvider = p;
      setState(() => _models = []);
      app.touch();
    }

    return Scaffold(
      appBar: AppBar(title: Text(s['aiSettings'])),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            // ---- provider
            SectionHeader(s['provider'], padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _ProviderTile(
                    selected: gemini,
                    icon: Icons.auto_awesome_rounded,
                    color: Brand.primary,
                    title: 'Gemini',
                    subtitle: 'Google · ${s['pfAiFree']}',
                    onTap: () => selectProvider(AiProvider.gemini),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProviderTile(
                    selected: !gemini,
                    icon: Icons.hub_rounded,
                    color: Brand.violet,
                    title: s['pfAiCompatible'],
                    subtitle: 'Groq · OpenRouter · OpenAI',
                    onTap: () => selectProvider(AiProvider.openai),
                  ),
                ),
              ]),
            ),

            // ---- key
            SectionHeader(s['apiKey']),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (gemini) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const TintIcon(Icons.key_rounded, color: Brand.warning, size: 36),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s['aiSetupBody'], style: TextStyle(color: cs.onSurfaceVariant))),
                  ]),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          launchUrl(Uri.parse('https://aistudio.google.com/apikey'), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(s['getKey']),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _geminiKey,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Gemini ${s['apiKey']}',
                      prefixIcon: const Icon(Icons.vpn_key_rounded),
                    ),
                  ),
                ] else ...[
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in _presets.entries)
                      ActionChip(
                        avatar: const Icon(Icons.bolt_rounded, size: 18),
                        label: Text(e.key),
                        onPressed: () => setState(() {
                          _openaiBase.text = e.value.$1;
                          _openaiModel.text = e.value.$2;
                        }),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _openaiBase,
                    decoration: InputDecoration(labelText: s['baseUrl'], prefixIcon: const Icon(Icons.link_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _openaiKey,
                    obscureText: true,
                    decoration: InputDecoration(labelText: s['apiKey'], prefixIcon: const Icon(Icons.vpn_key_rounded)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, children: [
                    for (final e in _presets.entries)
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse(e.value.$3), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: Text('${e.key.split(' ').first}: ${s['getKey']}'),
                      ),
                  ]),
                ],
              ]),
            ),

            // ---- model
            SectionHeader(s['model']),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _models.isEmpty
                    ? TextField(
                        controller: modelCtl,
                        decoration: InputDecoration(labelText: s['model'], prefixIcon: const Icon(Icons.memory_rounded)),
                      )
                    : DropdownButtonFormField<String>(
                        initialValue: _models.contains(modelCtl.text) ? modelCtl.text : null,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: s['model'], prefixIcon: const Icon(Icons.memory_rounded)),
                        items: [
                          for (final m in _models) DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => modelCtl.text = v ?? modelCtl.text,
                      ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run((ai) async {
                              final m = await ai.listModels();
                              setState(() => _models = m.toSet().toList());
                            }),
                    icon: const Icon(Icons.cloud_download_rounded, size: 18),
                    label: Text(s['loadModels']),
                  ),
                ),
              ]),
            ),

            // ---- actions
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await _persist();
                          if (context.mounted) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(s['save']),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run((ai) async {
                            final r = await ai.test();
                            _status = '✓ ${s['keyWorks']} ($r)';
                          }),
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: Text(s['testKey']),
                ),
              ),
            ]),
            if (status != null) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final ok = status.startsWith('✓');
                final c = ok ? Brand.success : Brand.danger;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(radiusS)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded, color: c, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: SelectableText(status, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                );
              }),
            ],
            const SizedBox(height: 24),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s['chatGptNote'],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radiusL),
          border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        ),
        child: AppCard(
          onTap: onTap,
          radius: radiusL - 2,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              TintIcon(icon, color: color, size: 36),
              const Spacer(),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? color : cs.outlineVariant,
                size: 22,
              ),
            ]),
            const SizedBox(height: 12),
            Text(title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(subtitle,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
