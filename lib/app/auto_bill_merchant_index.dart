part of 'auto_bill_rules.dart';

typedef _MerchantKey = (EntryType, String);
typedef _MerchantPeriodKey = (EntryType, String, _MealPeriod);

/// One active ledger's normalized merchant history. Created only on demand.
final class AutoBillMerchantIndex {
  AutoBillMerchantIndex(this.bookId, Iterable<LedgerEntry> entries) {
    for (final entry in entries) {
      upsert(entry);
    }
  }

  final String bookId;
  final _byId = <String, LedgerEntry>{};
  final _keysById = <String, _MerchantPeriodKey>{};
  final _byMerchant = <_MerchantKey, SplayTreeSet<LedgerEntry>>{};
  final _byPeriod = <_MerchantPeriodKey, SplayTreeSet<LedgerEntry>>{};

  static SplayTreeSet<LedgerEntry> _newBucket() =>
      SplayTreeSet((first, second) {
        final date = second.occurredAt.compareTo(first.occurredAt);
        return date == 0 ? second.id.compareTo(first.id) : date;
      });

  void upsert(LedgerEntry entry) {
    remove(entry.id);
    if (entry.bookId != bookId) return;
    _byId[entry.id] = entry;
    final merchant = AutoBillSuggestions._merchantFromNote(entry.note);
    if (merchant.isEmpty) return;
    final period = _MealPeriod.at(entry.occurredAt);
    final key = (entry.type, merchant, period);
    _keysById[entry.id] = key;
    _byMerchant.putIfAbsent((entry.type, merchant), _newBucket).add(entry);
    _byPeriod.putIfAbsent(key, _newBucket).add(entry);
  }

  void remove(String id) {
    final entry = _byId.remove(id);
    final key = _keysById.remove(id);
    if (entry == null || key == null) return;
    _removeFrom(_byMerchant, (key.$1, key.$2), entry);
    _removeFrom(_byPeriod, key, entry);
  }

  static void _removeFrom<K>(
    Map<K, SplayTreeSet<LedgerEntry>> groups,
    K key,
    LedgerEntry entry,
  ) {
    final bucket = groups[key];
    if (bucket == null) return;
    bucket.remove(entry);
    if (bucket.isEmpty) groups.remove(key);
  }

  Iterable<LedgerEntry> _history(
    EntryType type,
    String merchant,
    DateTime occurredAt, [
    _MealPeriod? period,
  ]) {
    final bucket = period == null
        ? _byMerchant[(type, merchant)]
        : _byPeriod[(type, merchant, period)];
    return bucket?.skipWhile((entry) => entry.occurredAt.isAfter(occurredAt)) ??
        const [];
  }
}
