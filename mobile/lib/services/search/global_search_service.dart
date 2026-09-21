/// ✅ (2026-09-22) خدمة البحث الشامل — محرك موحّد فوق كل كيانات النظام.
///
/// مبني على عقد طبقة البيانات الفعلية (لا اجتهاد):
/// - كل الجداول متزامنة تحمل `deletedAt` — البحث يستبعدها افتراضياً
///   (`includeDeleted` للمدير تدقيقياً).
/// - المدفوعات تحمل `isVoided`/`isPendingBalance` وتستبعد من التقارير
///   المالية — البحث يحترم نفس العقد ويضمها للمدير عند الطلب.
/// - التواريخ الفندقية: `hotelDayKey` هو المفتاح، مع سقوط تاريخي على
///   عمود التاريخ القديم حين يكون المفتاح NULL (نفس عقد
///   `PaymentsDao.listFilteredByHotelDay`).
/// - البحث النصي SQL-LIKE بتوسيع همزي عربي (`arabic_query.dart`) —
///   «احمد» تجد «أحمد» بلا أي تغيير مخطط.
/// - المدخل الرقمي المفرد يطابق المبالغ بالمساواة — «40000» تجد
///   المصروف والدفعة والسحبية بمبلغها — ويطابق رقم الحجز.
/// - الصلاحيات: كل كيان مربوط بمفتاح صلاحية شاشة موجود — النتائج
///   تُحجب قبل البناء لا بعده (لا يفتح البحث ما لا يفتحه التنقل).
///
/// الاستعلامات محدودة دائماً (سقف النتائج لكل نوع) مع عدّاد إجمالي صادق،
/// والواجهة مسؤولة عن الـ debounce — الخدمة صمّاء لا تعرف UI.
library;

import 'package:drift/drift.dart';

import '../../utils/arabic_query.dart';
import '../local_db.dart';
import '../repositories/blacklist_repository.dart';

/// أنواع الكيانات القابلة للبحث.
enum SearchEntityKind {
  booking,
  guestInfo,
  payment,
  expense,
  withdrawal,
  debt,
  employee,
  room,
  inventoryItem,
  blacklist,
}

/// نتيجة واحدة موحّدة من أي كيان.
class GlobalSearchHit {
  const GlobalSearchHit({
    required this.kind,
    required this.id,
    required this.localUuid,
    required this.title,
    required this.subtitle,
    this.amount,
    this.dayKey,
    this.matchedFields = const <String>[],
    this.record,
  });

  final SearchEntityKind kind;

  /// المعرف المحلي (int autoIncrement).
  final int id;
  final String localUuid;

  /// السطر الأول في النتيجة (اسم/وصف).
  final String title;

  /// السطر الثاني (غرفة/نوع/سبب).
  final String subtitle;

  /// الرقم المالي ذو الصلة إن وجد (مبلغ/متبقي).
  final double? amount;

  /// مفتاح اليوم الفندقي 'yyyy-MM-dd' المرتبط بالسجل.
  final String? dayKey;

  /// أسماء الحقول (عربية) التي طابق عليها الاستعلام.
  final List<String> matchedFields;

  /// الصف الأصلي بفئته (Booking/Payment/... — انظر شاشة العرض).
  final Object? record;
}

/// استعلام بحث شامل.
class GlobalSearchQuery {
  const GlobalSearchQuery({
    required this.text,
    this.fromDay,
    this.toDay,
    this.includeDeleted = false,
    this.includeInactivePayments = false,
    this.kinds,
  });

  /// نص البحث الخام — يُقسم ويُوسَّع همزياً داخل الخدمة.
  final String text;

  /// بداية النطاق (مفتاح يوم 'yyyy-MM-dd'، شامل) — null = بلا حد.
  final String? fromDay;

  /// نهاية النطاق (مفتاح يوم 'yyyy-MM-dd'، شامل) — null = بلا حد.
  final String? toDay;

  /// إظهار السجلات المحذوفة ناعماً (تدقيق المدير).
  final bool includeDeleted;

  /// إظهار المدفوعات الملغاة والمعلقة مع السليم.
  final bool includeInactivePayments;

  /// حصر البحث بأنواع محددة — null = كل الأنواع المسموحة.
  final Set<SearchEntityKind>? kinds;
}

/// حصيلة بحث شامل.
class GlobalSearchResults {
  const GlobalSearchResults({
    required this.hits,
    required this.totals,
    required this.elapsed,
  });

  /// النتائج المعروضة لكل نوع (بحد [GlobalSearchService.maxHitsPerKind]).
  final Map<SearchEntityKind, List<GlobalSearchHit>> hits;

  /// العدد الإجمالي المطابق لكل نوع (قد يتجاوز المعروض).
  final Map<SearchEntityKind, int> totals;

  /// زمن التنفيذ الفعلي.
  final Duration elapsed;

  int get totalHits => hits.values.fold(0, (sum, list) => sum + list.length);
  bool get isEmpty => totals.values.every((total) => total == 0);
}

/// نتيجة باحث واحد.
typedef _KindResult = ({List<GlobalSearchHit> hits, int total});

/// مفتاح صلاحية الشاشة الذي يحرس بيانات كل كيان.
///
/// مصدرها مسارات `main.dart` (`_validRoutes`) — البحث الشامل لا يفتح
/// ما لا يفتحه التنقل العادي.
const Map<SearchEntityKind, String> kSearchPermissionKeyByKind = {
  SearchEntityKind.booking: 'bookings',
  SearchEntityKind.guestInfo: 'bookings',
  SearchEntityKind.payment: 'payments',
  SearchEntityKind.expense: 'expenses',
  SearchEntityKind.withdrawal: 'employees',
  SearchEntityKind.debt: 'debts',
  SearchEntityKind.employee: 'employees',
  SearchEntityKind.room: 'rooms',
  SearchEntityKind.inventoryItem: 'settings',
  SearchEntityKind.blacklist: 'blacklist',
};

class GlobalSearchService {
  GlobalSearchService(this.db, {Set<String>? allowedPermissionKeys})
    : _allowedPermissionKeys = allowedPermissionKeys;

  /// سقف النتائج المعروضة لكل نوع — الواجهة تعرض «+N أخرى» من الإجمالي.
  static const int maxHitsPerKind = 15;

  /// null = بلا قيد (المدير يرى كل الأنواع).
  final Set<String>? _allowedPermissionKeys;
  final AppDatabase db;

  /// الأنواع التي يُسمح لهذه الخدمة بالبحث فيها.
  Set<SearchEntityKind> get allowedKinds =>
      SearchEntityKind.values.where(isKindAllowed).toSet();

  bool isKindAllowed(SearchEntityKind kind) {
    final keys = _allowedPermissionKeys;
    if (keys == null) {
      return true;
    }
    return keys.contains(kSearchPermissionKeyByKind[kind]);
  }

  /// بحث شامل — يُرجع نتائج كل الأنواع المطلوبة المسموحة (متزامنة).
  Future<GlobalSearchResults> search(GlobalSearchQuery query) async {
    final sw = Stopwatch()..start();
    final words = tokenizeQuery(query.text);
    if (words.isEmpty) {
      return const GlobalSearchResults(
        hits: {},
        totals: {},
        elapsed: Duration.zero,
      );
    }

    // مدخل رقمي مفرد: مبلغ أو رقم حجز
    final single = words.length == 1 ? words.first : null;
    final matchers = _SharedMatchers(
      words: words,
      amount: single == null ? null : tryParseAmount(single),
      bookingId: single == null
          ? null
          : int.tryParse(single.replaceFirst(RegExp('^#'), '')),
    );

    final requestedKinds = query.kinds ?? SearchEntityKind.values.toSet();
    final searchers = <SearchEntityKind, Future<_KindResult> Function()>{
      SearchEntityKind.booking: () => _searchBookings(query, matchers),
      SearchEntityKind.guestInfo: () => _searchGuestInfos(query, matchers),
      SearchEntityKind.payment: () => _searchPayments(query, matchers),
      SearchEntityKind.expense: () => _searchExpenses(query, matchers),
      SearchEntityKind.withdrawal: () => _searchWithdrawals(query, matchers),
      SearchEntityKind.debt: () => _searchDebts(query, matchers),
      SearchEntityKind.employee: () => _searchEmployees(query, matchers),
      SearchEntityKind.room: () => _searchRooms(query, matchers),
      SearchEntityKind.inventoryItem: () =>
          _searchInventoryItems(query, matchers),
      SearchEntityKind.blacklist: () => _searchBlacklist(query, matchers),
    };

    final jobs = <Future<MapEntry<SearchEntityKind, _KindResult>>>[];
    for (final entry in searchers.entries) {
      if (!requestedKinds.contains(entry.key) || !isKindAllowed(entry.key)) {
        continue;
      }
      jobs.add(
        _guarded(entry.key, entry.value).then(
          (result) => MapEntry(entry.key, result),
        ),
      );
    }
    if (jobs.isEmpty) {
      return const GlobalSearchResults(
        hits: {},
        totals: {},
        elapsed: Duration.zero,
      );
    }

    final entries = await Future.wait(jobs);
    final hits = <SearchEntityKind, List<GlobalSearchHit>>{};
    final totals = <SearchEntityKind, int>{};
    for (final entry in entries) {
      if (entry.value.total > 0) {
        hits[entry.key] = entry.value.hits;
        totals[entry.key] = entry.value.total;
      }
    }
    return GlobalSearchResults(
      hits: hits,
      totals: totals,
      elapsed: sw.elapsed,
    );
  }

  /// حصن كل باحث: فشل نوع لا يُسقط البحث كله — يُرجع صفراً لذلك النوع.
  Future<_KindResult> _guarded(
    SearchEntityKind kind,
    Future<_KindResult> Function() body,
  ) async {
    try {
      return await body();
    } catch (_) {
      return const (hits: <GlobalSearchHit>[], total: 0);
    }
  }

  // ══════════════════════════ باحثو الكيانات ══════════════════════════

  Future<_KindResult> _searchBookings(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    final t = db.bookings;
    Expression<bool> where = _alive(t.deletedAt, query.includeDeleted);
    Expression<bool> match =
        _textMatch([
          t.guestName,
          t.guestPhone,
          t.guestIdNumber,
          t.guestNationality,
          t.roomNumber,
          t.notes,
        ], m.words) ??
        const Constant(false);
    if (m.bookingId != null) {
      match = match | t.id.equals(m.bookingId!);
    }
    where = where & match;
    where = where & _plainDayRange(t.checkinDate, query);

    final count = t.id.count();
    final totalRow =
        await (db.selectOnly(t)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    final rows =
        await (db.select(t)
              ..where((_) => where)
              ..orderBy([
                (x) => OrderingTerm.desc(x.checkinDate),
                (x) => OrderingTerm.desc(x.id),
              ])
              ..limit(maxHitsPerKind))
            .get();

    return (
      hits: [
        for (final b in rows)
          GlobalSearchHit(
            kind: SearchEntityKind.booking,
            id: b.id,
            localUuid: b.localUuid,
            title: b.guestName,
            subtitle: 'غرفة ${b.roomNumber} • ${b.status}',
            amount: b.remainingBalanceCached,
            dayKey: _dayOf(b.checkinDate),
            matchedFields: _matchedFields(
              {
                'اسم النزيل': b.guestName,
                'الهاتف': b.guestPhone,
                'رقم الهوية': b.guestIdNumber,
                'الجنسية': b.guestNationality,
                'الغرفة': b.roomNumber,
                'ملاحظات': b.notes,
              },
              m,
              idHit: m.bookingId != null && b.id == m.bookingId
                  ? 'رقم الحجز'
                  : null,
            ),
            record: b,
          ),
      ],
      total: totalRow.read(count) ?? 0,
    );
  }

  Future<_KindResult> _searchGuestInfos(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    final t = db.guestInfos;
    Expression<bool> where = _alive(t.deletedAt, query.includeDeleted);
    where =
        where &
        (_textMatch([
              t.guestName,
              t.idNumber,
              t.guestPhone,
              t.nationality,
              t.roomNumber,
              t.governorate,
              t.notes,
            ], m.words) ??
            const Constant(false));

    final count = t.id.count();
    final totalRow =
        await (db.selectOnly(t)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    final rows =
        await (db.select(t)
              ..where((_) => where)
              ..orderBy([(x) => OrderingTerm.desc(x.id)])
              ..limit(maxHitsPerKind))
            .get();

    return (
      hits: [
        for (final g in rows)
          GlobalSearchHit(
            kind: SearchEntityKind.guestInfo,
            id: g.id,
            localUuid: g.localUuid,
            title: g.guestName,
            subtitle: 'غرفة ${g.roomNumber} • ${g.nationality}',
            matchedFields: _matchedFields({
              'اسم الضيف': g.guestName,
              'رقم الهوية': g.idNumber,
              'الهاتف': g.guestPhone,
              'الجنسية': g.nationality,
              'الغرفة': g.roomNumber,
              'المحافظة': g.governorate,
              'ملاحظات': g.notes,
            }, m),
            record: g,
          ),
      ],
      total: totalRow.read(count) ?? 0,
    );
  }

  Future<_KindResult> _searchPayments(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    final t = db.payments;
    Expression<bool> where = _alive(t.deletedAt, query.includeDeleted);
    if (!query.includeInactivePayments) {
      where = where & t.isVoided.equals(false);
      where = where & t.isPendingBalance.equals(false);
    }
    Expression<bool> match =
        _textMatch([
          t.roomNumber,
          t.notes,
          t.referenceNumber,
          t.receivedByName,
          t.revenueType,
          t.paymentMethod,
        ], m.words) ??
        const Constant(false);
    final amountMatch = _amountMatch([t.amount], m.amount);
    if (amountMatch != null) {
      match = match | amountMatch;
    }
    where = where & match;
    where =
        where &
        _hotelDayRange(
          t.hotelDayKey,
          t.paymentDate,
          fromDay: query.fromDay,
          toDay: query.toDay,
          legacyIsIso: true,
        );

    final count = t.id.count();
    final totalRow =
        await (db.selectOnly(t)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    final rows =
        await (db.select(t)
              ..where((_) => where)
              ..orderBy([
                (x) => OrderingTerm.desc(x.paymentDate),
                (x) => OrderingTerm.desc(x.id),
              ])
              ..limit(maxHitsPerKind))
            .get();

    return (
      hits: [
        for (final p in rows)
          GlobalSearchHit(
            kind: SearchEntityKind.payment,
            id: p.id,
            localUuid: p.localUuid,
            title: p.roomNumber != null && p.roomNumber!.isNotEmpty
                ? 'دفعة — غرفة ${p.roomNumber}'
                : 'دفعة — ${p.revenueType}',
            subtitle: [
              if (p.receivedByName != null && p.receivedByName!.isNotEmpty)
                p.receivedByName!,
              p.paymentMethod,
            ].join(' • '),
            amount: p.amount,
            dayKey: p.hotelDayKey ?? _dayOf(p.paymentDate),
            matchedFields: _matchedFields(
              {
                'الغرفة': p.roomNumber,
                'ملاحظات': p.notes,
                'رقم المرجع': p.referenceNumber,
                'المستلم': p.receivedByName,
                'نوع الإيراد': p.revenueType,
                'طريقة الدفع': p.paymentMethod,
              },
              m,
              amountHit: m.amount != null && p.amount == m.amount
                  ? 'المبلغ'
                  : null,
            ),
            record: p,
          ),
      ],
      total: totalRow.read(count) ?? 0,
    );
  }

  Future<_KindResult> _searchExpenses(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    final t = db.expenses;
    Expression<bool> where = _alive(t.deletedAt, query.includeDeleted);
    Expression<bool> match =
        _textMatch([t.description, t.expenseType], m.words) ??
        const Constant(false);
    final amountMatch = _amountMatch([t.amount], m.amount);
    if (amountMatch != null) {
      match = match | amountMatch;
    }
    where = where & match;
    where =
        where &
        _hotelDayRange(
          t.hotelDayKey,
          t.date,
          fromDay: query.fromDay,
          toDay: query.toDay,
          legacyIsIso: false,
        );

    final count = t.id.count();
    final totalRow =
        await (db.selectOnly(t)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    final rows =
        await (db.select(t)
              ..where((_) => where)
              ..orderBy([
                (x) => OrderingTerm.desc(x.date),
                (x) => OrderingTerm.desc(x.id),
              ])
              ..limit(maxHitsPerKind))
            .get();

    return (
      hits: [
        for (final e in rows)
          GlobalSearchHit(
            kind: SearchEntityKind.expense,
            id: e.id,
            localUuid: e.localUuid,
            title: e.description,
            subtitle: e.expenseType,
            amount: e.amount,
            dayKey: e.hotelDayKey ?? _dayOf(e.date),
            matchedFields: _matchedFields(
              {
                'الوصف': e.description,
                'النوع': e.expenseType,
              },
              m,
              amountHit: m.amount != null && e.amount == m.amount
                  ? 'المبلغ'
                  : null,
            ),
            record: e,
          ),
      ],
      total: totalRow.read(count) ?? 0,
    );
  }

  Future<_KindResult> _searchWithdrawals(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    final t = db.salaryWithdrawals;
    final emp = db.employees;
    Expression<bool> where = _alive(t.deletedAt, query.includeDeleted);
    Expression<bool> match =
        _textMatch([t.reason, t.description, t.withdrawalType], m.words) ??
        const Constant(false);

    // مطابقة اسم الموظف: جلب المعرفات المطابقة أولاً بدل subquery —
    // الموظف المحذوف ناعمياً يظل اسمه يطابق سحبياته.
    final employeeRows =
        await (db.select(emp)..where(
              (_) => _textMatch([emp.name], m.words) ?? const Constant(false),
            ))
            .get();
    if (employeeRows.isNotEmpty) {
      match = match | t.employeeId.isIn(employeeRows.map((e) => e.id));
    }
    final amountMatch = _amountMatch([t.amount], m.amount);
    if (amountMatch != null) {
      match = match | amountMatch;
    }
    where = where & match;
    where =
        where &
        _hotelDayRange(
          t.hotelDayKey,
          t.withdrawDate,
          fromDay: query.fromDay,
          toDay: query.toDay,
          legacyIsIso: false,
        );

    final count = t.id.count();
    final totalRow =
        await (db.selectOnly(t)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    final rows =
        await (db.select(t)
              ..where((_) => where)
              ..orderBy([
                (x) => OrderingTerm.desc(x.withdrawDate),
                (x) => OrderingTerm.desc(x.id),
              ])
              ..limit(maxHitsPerKind))
            .get();

    final resultEmployeeIds = rows.map((r) => r.employeeId).toSet();
    final nameRows = resultEmployeeIds.isEmpty
        ? const <Employee>[]
        : await (db.select(
            emp,
          )..where((x) => x.id.isIn(resultEmployeeIds))).get();
    final nameById = {for (final e in nameRows) e.id: e.name};

    return (
      hits: [
        for (final w in rows)
          GlobalSearchHit(
            kind: SearchEntityKind.withdrawal,
            id: w.id,
            localUuid: w.localUuid,
            title: nameById[w.employeeId] ?? 'موظف محذوف',
            subtitle: [
              if (w.reason != null && w.reason!.isNotEmpty) w.reason!,
              if (w.withdrawalType != null && w.withdrawalType!.isNotEmpty)
                w.withdrawalType!,
            ].join(' • '),
            amount: w.amount,
            dayKey: w.hotelDayKey ?? _dayOf(w.withdrawDate),
            matchedFields: _matchedFields(
              {
                'السبب': w.reason,
                'الوصف': w.description,
                'النوع': w.withdrawalType,
                'اسم الموظف': nameById[w.employeeId],
              },
              m,
              amountHit: m.amount != null && w.amount == m.amount
                  ? 'المبلغ'
                  : null,
            ),
            record: w,
          ),
      ],
      total: totalRow.read(count) ?? 0,
    );
  }

  Future<_KindResult> _searchDebts(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    final t = db.debts;
    Expression<bool> where = _alive(t.deletedAt, query.includeDeleted);
    Expression<bool> match =
        _textMatch([
          t.guestName,
          t.debtorName,
          t.debtReason,
          t.note,
          t.pledge,
          t.guestPhone,
        ], m.words) ??
        const Constant(false);
    final amountMatch = _amountMatch([
      t.totalAmount,
      t.paidAmount,
      t.remainingAmount,
    ], m.amount);
    if (amountMatch != null) {
      match = match | amountMatch;
    }
    where = where & match;
    where = where & _plainDayRange(t.paymentDate, query);

    final count = t.id.count();
    final totalRow =
        await (db.selectOnly(t)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    final rows =
        await (db.select(t)
              ..where((_) => where)
              ..orderBy([
                (x) => OrderingTerm.desc(x.paymentDate),
                (x) => OrderingTerm.desc(x.id),
              ])
              ..limit(maxHitsPerKind))
            .get();

    return (
      hits: [
        for (final d in rows)
          GlobalSearchHit(
            kind: SearchEntityKind.debt,
            id: d.id,
            localUuid: d.localUuid,
            title: d.guestName,
            subtitle: [
              if (d.debtReason.isNotEmpty) d.debtReason,
              if (d.isSettled == 1) 'مسدد' else 'قائم',
            ].join(' • '),
            amount: d.remainingAmount,
            dayKey: _dayOf(d.paymentDate),
            matchedFields: _matchedFields(
              {
                'اسم المدين': d.guestName,
                'المدين (تفصيلي)': d.debtorName,
                'السبب': d.debtReason,
                'ملاحظات': d.note,
                'الرهان': d.pledge,
                'الهاتف': d.guestPhone,
              },
              m,
              amountHit:
                  m.amount != null &&
                      (d.totalAmount == m.amount ||
                          d.paidAmount == m.amount ||
                          d.remainingAmount == m.amount)
                  ? 'المبلغ'
                  : null,
            ),
            record: d,
          ),
      ],
      total: totalRow.read(count) ?? 0,
    );
  }

  Future<_KindResult> _searchEmployees(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    final t = db.employees;
    Expression<bool> where = _alive(t.deletedAt, query.includeDeleted);
    where =
        where &
        (_textMatch([t.name, t.position, t.phone, t.employeeID], m.words) ??
            const Constant(false));

    final count = t.id.count();
    final totalRow =
        await (db.selectOnly(t)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    final rows =
        await (db.select(t)
              ..where((_) => where)
              ..orderBy([(x) => OrderingTerm.asc(x.name)])
              ..limit(maxHitsPerKind))
            .get();

    return (
      hits: [
        for (final e in rows)
          GlobalSearchHit(
            kind: SearchEntityKind.employee,
            id: e.id,
            localUuid: e.localUuid,
            title: e.name,
            subtitle: '${e.position} • ${e.status}',
            matchedFields: _matchedFields({
              'الاسم': e.name,
              'الوظيفة': e.position,
              'الهاتف': e.phone,
              'الرقم الوظيفي': e.employeeID,
            }, m),
            record: e,
          ),
      ],
      total: totalRow.read(count) ?? 0,
    );
  }

  Future<_KindResult> _searchRooms(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    final t = db.rooms;
    Expression<bool> where = _alive(t.deletedAt, query.includeDeleted);
    where =
        where &
        (_textMatch([t.roomNumber, t.type, t.status], m.words) ??
            const Constant(false));

    final count = t.id.count();
    final totalRow =
        await (db.selectOnly(t)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    final rows =
        await (db.select(t)
              ..where((_) => where)
              ..orderBy([(x) => OrderingTerm.asc(x.roomNumber)])
              ..limit(maxHitsPerKind))
            .get();

    return (
      hits: [
        for (final r in rows)
          GlobalSearchHit(
            kind: SearchEntityKind.room,
            id: r.id,
            localUuid: r.localUuid,
            title: 'غرفة ${r.roomNumber}',
            subtitle: '${r.type} • ${r.status}',
            matchedFields: _matchedFields({
              'رقم الغرفة': r.roomNumber,
              'النوع': r.type,
              'الحالة': r.status,
            }, m),
            record: r,
          ),
      ],
      total: totalRow.read(count) ?? 0,
    );
  }

  Future<_KindResult> _searchInventoryItems(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    final t = db.inventoryItems;
    Expression<bool> where = _alive(t.deletedAt, query.includeDeleted);
    where =
        where &
        (_textMatch([t.name, t.category, t.unit], m.words) ??
            const Constant(false));

    final count = t.id.count();
    final totalRow =
        await (db.selectOnly(t)
              ..addColumns([count])
              ..where(where))
            .getSingle();
    final rows =
        await (db.select(t)
              ..where((_) => where)
              ..orderBy([(x) => OrderingTerm.asc(x.name)])
              ..limit(maxHitsPerKind))
            .get();

    return (
      hits: [
        for (final i in rows)
          GlobalSearchHit(
            kind: SearchEntityKind.inventoryItem,
            id: i.id,
            localUuid: i.localUuid,
            title: i.name,
            subtitle: [
              if (i.category != null && i.category!.isNotEmpty) i.category!,
              'الكمية: ${i.quantity}',
              if (i.isActive) 'نشط' else 'موقوف',
            ].join(' • '),
            matchedFields: _matchedFields({
              'الاسم': i.name,
              'التصنيف': i.category,
              'الوحدة': i.unit,
            }, m),
            record: i,
          ),
      ],
      total: totalRow.read(count) ?? 0,
    );
  }

  Future<_KindResult> _searchBlacklist(
    GlobalSearchQuery query,
    _SharedMatchers m,
  ) async {
    // القائمة السوداء صغيرة وتُقرأ عبر مستودعها المعتمد (عقد JSON في
    // shift_notes) — الفلترة في Dart عمداً: إعادة استخدام نفس التحليل،
    // والسجلات المحذوفة ناعمياً لا تظهر (عقد listAll الثابت).
    final entries = await BlacklistRepository(db).listAll();
    final matched = entries.where((entry) {
      var textHit = false;
      for (final value in {
        entry.name,
        entry.nationality,
        entry.nationalId,
        entry.phone,
        entry.reason,
        entry.notes,
      }) {
        if (value == null || value.isEmpty) {
          continue;
        }
        if (m.words.any(normalizeArabicForSearch(value).contains)) {
          textHit = true;
          break;
        }
      }
      final day = _dayKeyOfDate(entry.createdAt);
      final afterFrom =
          query.fromDay == null || day.compareTo(query.fromDay!) >= 0;
      final beforeTo = query.toDay == null || day.compareTo(query.toDay!) <= 0;
      return textHit && afterFrom && beforeTo;
    }).toList();

    return (
      hits: [
        for (final entry in matched.take(maxHitsPerKind))
          GlobalSearchHit(
            kind: SearchEntityKind.blacklist,
            id: entry.id,
            localUuid: '',
            title: entry.name,
            subtitle: [
              if (entry.reason != null && entry.reason!.isNotEmpty)
                entry.reason!,
              if (entry.active) 'نشط' else 'موقوف',
            ].join(' • '),
            dayKey: _dayKeyOfDate(entry.createdAt),
            record: entry,
          ),
      ],
      total: matched.length,
    );
  }

  // ══════════════════════════ مساعدات البناء ══════════════════════════

  /// شرط الحياة: deletedAt IS NULL ما لم يطلب المدير إظهار المحذوف.
  Expression<bool> _alive(
    GeneratedColumn<int> deletedAt,
    bool includeDeleted,
  ) => includeDeleted ? const Constant(true) : deletedAt.isNull();

  /// مطابقة نصية: كلمات AND، متغيرات همزية OR عبر الأعمدة.
  Expression<bool>? _textMatch(
    List<GeneratedColumn<String>> columns,
    List<String> words,
  ) {
    if (columns.isEmpty || words.isEmpty) {
      return null;
    }
    Expression<bool>? combined;
    for (final word in words) {
      final patterns = likePatternsForWord(word);
      if (patterns.isEmpty) {
        continue;
      }
      Expression<bool>? wordMatch;
      for (final column in columns) {
        for (final pattern in patterns) {
          final m = column.like(pattern, escapeChar: r'\');
          wordMatch = wordMatch == null ? m : wordMatch | m;
        }
      }
      if (wordMatch == null) {
        return null;
      }
      combined = combined == null ? wordMatch : combined & wordMatch;
    }
    return combined;
  }

  /// مطابقة مبلغ رقمي بالمساواة على أي من الأعمدة.
  Expression<bool>? _amountMatch(
    List<GeneratedColumn<double>> columns,
    double? amount,
  ) {
    if (amount == null || columns.isEmpty) {
      return null;
    }
    Expression<bool>? match;
    for (final column in columns) {
      final e = column.equals(amount);
      match = match == null ? e : match | e;
    }
    return match;
  }

  /// نطاق يوم فندقي على عمود مفتاح + سقوط تاريخي (عقد listFilteredByHotelDay).
  Expression<bool> _hotelDayRange(
    GeneratedColumn<String> hotelDayKey,
    GeneratedColumn<String> legacyDate, {
    required String? fromDay,
    required String? toDay,
    required bool legacyIsIso,
  }) {
    Expression<bool>? range;
    if (fromDay != null) {
      range =
          (hotelDayKey.isNotNull() &
              hotelDayKey.isBiggerOrEqualValue(fromDay)) |
          (hotelDayKey.isNull() & legacyDate.isBiggerOrEqualValue(fromDay));
    }
    if (toDay != null) {
      final toExpr = legacyIsIso
          ? legacyDate.isSmallerThanValue(_nextDay(toDay))
          : legacyDate.isSmallerOrEqualValue(toDay);
      final upper =
          (hotelDayKey.isNotNull() & hotelDayKey.isSmallerOrEqualValue(toDay)) |
          (hotelDayKey.isNull() & toExpr);
      range = range == null ? upper : range & upper;
    }
    return range ?? const Constant(true);
  }

  /// نطاق على عمود تاريخ نصي 'yyyy-MM-dd' (شامل الطرفين).
  Expression<bool> _plainDayRange(
    GeneratedColumn<String> dateColumn,
    GlobalSearchQuery query,
  ) {
    if (query.fromDay != null && query.toDay != null) {
      return dateColumn.isBetweenValues(query.fromDay!, query.toDay!);
    }
    if (query.fromDay != null) {
      return dateColumn.isBiggerOrEqualValue(query.fromDay!);
    }
    if (query.toDay != null) {
      return dateColumn.isSmallerOrEqualValue(query.toDay!);
    }
    return const Constant(true);
  }

  /// أسماء الحقول التي طابقت — مقارنة مطبَّعة في Dart على الصفوف المرجعة فقط.
  List<String> _matchedFields(
    Map<String, String?> fieldsByLabel,
    _SharedMatchers m, {
    String? idHit,
    String? amountHit,
  }) {
    final labels = <String>[];
    for (final entry in fieldsByLabel.entries) {
      final value = entry.value;
      if (value == null || value.isEmpty) {
        continue;
      }
      final normalized = normalizeArabicForSearch(value);
      if (m.words.any(normalized.contains)) {
        labels.add(entry.key);
      }
    }
    if (idHit != null) {
      labels.add(idHit);
    }
    if (amountHit != null) {
      labels.add(amountHit);
    }
    return labels;
  }

  static String _dayOf(String value) =>
      value.length >= 10 ? value.substring(0, 10) : value;

  static String _nextDay(String day) {
    final d = DateTime.tryParse(day);
    if (d == null) {
      return day;
    }
    return d.add(const Duration(days: 1)).toIso8601String().substring(0, 10);
  }

  static String _dayKeyOfDate(DateTime d) =>
      d.toIso8601String().substring(0, 10);
}

/// قيم مشتقة من الاستعلام يشترك فيها كل الباحثين.
class _SharedMatchers {
  const _SharedMatchers({
    required this.words,
    required this.amount,
    required this.bookingId,
  });

  final List<String> words;
  final double? amount;
  final int? bookingId;
}
