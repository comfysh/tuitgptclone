import '../core/storage.dart';
import '../lms/changes.dart';
import '../lms/snapshot.dart';

/// One thing that changed in LMS, as the Inbox shows it.
class InboxItem {
  const InboxItem({
    required this.kind,
    required this.key,
    required this.subject,
    required this.detail,
    required this.at,
    this.when,
    this.value,
    this.max,
    this.read = false,
  });

  final ChangeKind kind;
  final String key;
  final String subject;
  final String detail;
  final DateTime? when;
  final double? value;
  final double? max;

  /// When TuitMate noticed the change.
  final DateTime at;
  final bool read;

  /// One item per kind and key: a later change of the same thing (the deadline
  /// moved again, the grade changed again) replaces the older item.
  String get id => '${kind.name}|$key';

  LmsChange get change => LmsChange(kind, key, subject, detail, when: when, value: value, max: max);

  InboxItem copyWith({bool? read}) => InboxItem(
        kind: kind,
        key: key,
        subject: subject,
        detail: detail,
        at: at,
        when: when,
        value: value,
        max: max,
        read: read ?? this.read,
      );

  factory InboxItem.fromChange(LmsChange c, DateTime at, {bool read = false}) => InboxItem(
        kind: c.kind,
        key: c.key,
        subject: c.subject,
        detail: c.detail,
        when: c.when,
        value: c.value,
        max: c.max,
        at: at,
        read: read,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'key': key,
        'subject': subject,
        'detail': detail,
        'when': when?.toIso8601String(),
        'value': value,
        'max': max,
        'at': at.toIso8601String(),
        'read': read,
      };

  static InboxItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = ChangeKind.values.where((k) => k.name == j['kind']).firstOrNull;
    final at = DateTime.tryParse('${j['at']}');
    if (kind == null || at == null || j['key'] is! String) return null;
    return InboxItem(
      kind: kind,
      key: j['key'] as String,
      subject: '${j['subject'] ?? ''}',
      detail: '${j['detail'] ?? ''}',
      when: DateTime.tryParse('${j['when'] ?? ''}'),
      value: (j['value'] as num?)?.toDouble(),
      max: (j['max'] as num?)?.toDouble(),
      at: at,
      read: j['read'] == true,
    );
  }
}

/// The Inbox: every change a sync found (in the app or in the Android
/// background check), newest first, kept in inbox.json. Deadline reminders are
/// not kept: they are about time passing, not about something new in LMS.
class Inbox {
  Inbox._();

  static const maxItems = 300;

  static Future<List<InboxItem>> load(AppStorage storage) async {
    final j = await storage.readJson(storage.inboxFile);
    final items = <InboxItem>[];
    for (final e in (j['items'] as List? ?? const [])) {
      final item = InboxItem.fromJson(e);
      if (item != null) items.add(item);
    }
    return items;
  }

  static Future<void> _save(AppStorage storage, List<InboxItem> items) =>
      storage.writeJson(storage.inboxFile, {'v': 1, 'items': [for (final i in items.take(maxItems)) i.toJson()]});

  /// Adds the changes of one sync on top. Never throws.
  static Future<void> record(List<LmsChange> changes, AppStorage storage, {DateTime? now}) async {
    try {
      final fresh = [for (final c in changes) if (c.kind != ChangeKind.reminder) InboxItem.fromChange(c, now ?? DateTime.now())];
      if (fresh.isEmpty) return;
      final ids = {for (final i in fresh) i.id};
      final old = await load(storage);
      await _save(storage, [...fresh, ...old.where((i) => !ids.contains(i.id))]);
    } catch (_) {}
  }

  /// The first time (no inbox file yet): the latest LMS news, already read,
  /// so the Inbox isn't empty before anything changes. Never throws.
  static Future<void> seed(LmsSnapshot snap, AppStorage storage) async {
    try {
      if (snap.isEmpty || await storage.inboxFile.exists()) return;
      final news = [...snap.news.where((n) => n.date != null)]..sort((a, b) => b.date!.compareTo(a.date!));
      await _save(storage, [
        for (final n in news.take(5))
          InboxItem(kind: ChangeKind.news, key: n.key, subject: n.title, detail: n.body ?? '', when: n.date, at: n.date!, read: true),
      ]);
    } catch (_) {}
  }

  /// Marks [ids] read (all items when null). Returns the updated list.
  static Future<List<InboxItem>> markRead(AppStorage storage, {Set<String>? ids}) async {
    final items = await load(storage);
    if (items.isEmpty) return items;
    final out = [for (final i in items) (ids == null || ids.contains(i.id)) && !i.read ? i.copyWith(read: true) : i];
    try {
      await _save(storage, out);
    } catch (_) {}
    return out;
  }
}
