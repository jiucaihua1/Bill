part of 'transactions_pages.dart';

String _periodName(AppLocalizations l10n, SubscriptionMark mark) =>
    switch (mark.months) {
      1 => l10n.monthlySubscription,
      3 => l10n.quarterlySubscription,
      12 => l10n.yearlySubscription,
      24 => l10n.biennialSubscription,
      final int months => l10n.subscriptionMonthCount(months),
      null => l10n.unspecifiedSubscription,
    };

Future<SubscriptionMark?> _pickSubscriptionPeriod(
  BuildContext context,
  SubscriptionMark current, {
  bool allowRemove = false,
}) {
  return showModalBottomSheet<SubscriptionMark>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) =>
        _SubscriptionPeriodSheet(current: current, allowRemove: allowRemove),
  );
}

class _SubscriptionPeriodSheet extends StatefulWidget {
  const _SubscriptionPeriodSheet({
    required this.current,
    required this.allowRemove,
  });

  final SubscriptionMark current;
  final bool allowRemove;

  @override
  State<_SubscriptionPeriodSheet> createState() =>
      _SubscriptionPeriodSheetState();
}

class _SubscriptionPeriodSheetState extends State<_SubscriptionPeriodSheet> {
  late final TextEditingController _monthsController;

  @override
  void initState() {
    super.initState();
    _monthsController = TextEditingController(
      text: widget.current.months?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _monthsController.dispose();
    super.dispose();
  }

  int? get _parsedMonths {
    final text = _monthsController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  bool get _valid {
    final text = _monthsController.text.trim();
    if (text.isEmpty) return true;
    final months = _parsedMonths;
    return months != null &&
        months >= 1 &&
        months <= SubscriptionMark.maxMonths;
  }

  void _setMonths(int? months) {
    setState(() {
      _monthsController.text = months == null ? '' : '$months';
      _monthsController.selection = TextSelection.collapsed(
        offset: _monthsController.text.length,
      );
    });
  }

  void _save() {
    if (!_valid) return;
    final months = _parsedMonths;
    Navigator.pop(
      context,
      months == null
          ? SubscriptionMark.unspecified
          : SubscriptionMark.forMonths(months),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tokens = VeriStyleTokens.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final currentMonths = _parsedMonths;
    final presets = <({String label, int? months})>[
      (label: l10n.unspecifiedSubscription, months: null),
      (label: l10n.monthlySubscription, months: 1),
      (label: l10n.quarterlySubscription, months: 3),
      (label: l10n.subscriptionMonthCount(6), months: 6),
      (label: l10n.yearlySubscription, months: 12),
      (label: l10n.biennialSubscription, months: 24),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.subscriptionPeriod,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.allowRemove)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, SubscriptionMark.excluded),
                    style: TextButton.styleFrom(
                      foregroundColor: veriSemantic(context, veriExpense),
                    ),
                    child: Text(l10n.removeSubscription),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((preset) {
                final selected = _monthsController.text.trim().isEmpty
                    ? preset.months == null
                    : currentMonths == preset.months;
                return ChoiceChip(
                  label: Text(preset.label),
                  selected: selected,
                  onSelected: (_) => _setMonths(preset.months),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.surfaceAltColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.subscriptionMonthsLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          l10n.subscriptionMonthsOptional,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.56,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: (currentMonths ?? 1) > 1
                        ? () => _setMonths((currentMonths ?? 1) - 1)
                        : currentMonths == 1
                        ? () => _setMonths(null)
                        : null,
                  ),
                  SizedBox(
                    width: 56,
                    child: TextField(
                      controller: _monthsController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        hintText: '-',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: (currentMonths ?? 0) < SubscriptionMark.maxMonths
                        ? () => _setMonths((currentMonths ?? 0) + 1)
                        : null,
                  ),
                ],
              ),
            ),
            if (!_valid) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                l10n.subscriptionMonthsInvalid,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: veriSemantic(context, veriExpense),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _valid ? _save : null,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showDailySubscriptions(
  BuildContext context,
  VeriFinController controller,
  List<({LedgerEntry entry, SubscriptionMark period, double daily})> active,
  double total,
) {
  final l10n = AppLocalizations.of(context);
  final currency = controller.activeBook.baseCurrencyCode;
  final rows = active.toList()..sort((a, b) => b.daily.compareTo(a.daily));
  return showVeriModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .68,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.activeSubscriptionItems,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.subscriptionDailyAmount(
                  formatUserMoney(total, currency, forceUnit: true),
                ),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Divider(),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(l10n.noActiveSubscriptions),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final entry = row.entry;
                      final name = entry.note.trim().isEmpty
                          ? controller.categoryById(entry.categoryId).label
                          : entry.note;
                      final lastDay = addCalendarDays(
                        addCalendarMonths(
                          entry.occurredAt,
                          row.period.months!,
                          entry.occurredAt.day,
                        ),
                        -1,
                      );
                      final dates = MaterialLocalizations.of(context);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.subscriptionDailyAmount(
                                    formatUserMoney(
                                      row.daily,
                                      currency,
                                      forceUnit: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${_periodName(l10n, row.period)} · ${formatUserMoney(entry.netBaseAmount, currency, forceUnit: true)}',
                            ),
                            Text(
                              '${dates.formatCompactDate(entry.occurredAt)} – ${dates.formatCompactDate(lastDay)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SubscriptionBreakdown extends StatelessWidget {
  const _SubscriptionBreakdown({required this.totals, required this.currency});
  final Map<SubscriptionMark, (int, double)> totals;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final periods = totals.keys.toList()
      ..sort(
        (a, b) => (a.months ?? SubscriptionMark.maxMonths + 1).compareTo(
          b.months ?? SubscriptionMark.maxMonths + 1,
        ),
      );
    return VeriCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.subscriptionPeriodTotals,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final period in periods)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(child: Text(_periodName(l10n, period))),
                  Text(
                    l10n.entriesCountFull(totals[period]!.$1),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  Text(formatUserMoney(totals[period]!.$2, currency)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.entry});
  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final controller = VeriFinScope.of(context);
    final l10n = AppLocalizations.of(context);
    final period = subscriptionPeriod(entry)!;
    final category = controller.categoryById(entry.categoryId);
    return AnchoredMenuChoice<String>(
      values: const <String>['detail', 'edit_period'],
      selected: '',
      idOf: (value) => 'subscription_${entry.id}_$value',
      labelOf: (value) =>
          value == 'detail' ? l10n.viewOriginalBill : l10n.subscriptionPeriod,
      iconOf: (value) =>
          value == 'detail' ? Icons.receipt_long_outlined : Icons.edit_outlined,
      onSelected: (value) async {
        if (value == 'detail') {
          openEntryDetail(context, entry);
          return;
        }
        final picked = await _pickSubscriptionPeriod(
          context,
          period,
          allowRemove: true,
        );
        if (picked != null && context.mounted) {
          await controller.markSubscriptionExpenses(entry.bookId, {
            entry.id,
          }, picked);
        }
      },
      semanticLabel: entry.note.isEmpty ? category.label : entry.note,
      builder: (context, openMenu, menuOpen) => ListTile(
        leading: CategoryIconBox(
          iconCode: category.iconCode,
          categoryName: category.label,
          size: 36,
        ),
        contentPadding: EdgeInsets.zero,
        title: Text(
          entry.note.isEmpty ? category.label : entry.note,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(_periodName(l10n, period)),
        trailing: Text(
          formatUserMoney(
            entry.netBaseAmount,
            controller.activeBook.baseCurrencyCode,
          ),
        ),
        onTap: openMenu,
      ),
    );
  }
}

class _SubscriptionPicker extends StatefulWidget {
  const _SubscriptionPicker({required this.bookId});
  final String bookId;

  @override
  State<_SubscriptionPicker> createState() => _SubscriptionPickerState();
}

class _SubscriptionPickerState extends State<_SubscriptionPicker> {
  final _selected = <String>{};
  SubscriptionMark _period = SubscriptionMark.unspecified;
  String _query = '';
  bool _saving = false;
  List<Object?>? _signature;
  List<LedgerEntry> _candidates = const [];

  List<LedgerEntry> _matchingEntries(VeriFinController controller) {
    final signature = [controller.entries, controller.categories, _query];
    if (listEquals(_signature, signature)) return _candidates;
    _signature = signature;
    final categories = {
      for (final category in controller.categories)
        category.id: category.label.toLowerCase(),
    };
    final matches = <LedgerEntry>[];
    final eligibleSelected = <String>{};
    for (final entry in controller.entries) {
      if (entry.bookId != widget.bookId ||
          entry.type != EntryType.expense ||
          subscriptionPeriod(entry) != null) {
        continue;
      }
      if (_selected.contains(entry.id)) eligibleSelected.add(entry.id);
      if (_query.isEmpty ||
          entry.note.toLowerCase().contains(_query) ||
          (categories[entry.categoryId]?.contains(_query) ?? false) ||
          formatCurrencyNumber(
            entry.amount,
            entry.currencyCode,
          ).contains(_query)) {
        matches.add(entry);
      }
    }
    if (!_saving) _selected.retainAll(eligibleSelected);
    _candidates = matches;
    return _candidates;
  }

  Future<void> _save(VeriFinController controller) async {
    if (_saving || _selected.isEmpty) return;
    setState(() => _saving = true);
    final saved = await controller.markSubscriptionExpenses(
      widget.bookId,
      Set.of(_selected),
      _period,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _signature = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = VeriFinScope.of(context);
    final l10n = AppLocalizations.of(context);
    final entries = _matchingEntries(controller);
    return Scaffold(
      body: SafeArea(
        child: VeriPage(
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VeriHeader(
                    title: l10n.selectSubscriptionOrders,
                    showBack: true,
                    subtitle: l10n.selectedCount(_selected.length),
                    actions: [
                      SaveHeaderAction(
                        onPressed: _selected.isEmpty || _saving
                            ? null
                            : () => _save(controller),
                      ),
                    ],
                  ),
                  TextField(
                    enabled: !_saving,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.subscriptionPickerHint,
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.subscriptionPeriod),
                    trailing: Text(_periodName(l10n, _period)),
                    onTap: _saving
                        ? null
                        : () async {
                            final period = await _pickSubscriptionPeriod(
                              context,
                              _period,
                            );
                            if (mounted && period != null) {
                              setState(() => _period = period);
                            }
                          },
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Text(
                              _query.isEmpty
                                  ? l10n.noSubscriptionCandidates
                                  : l10n.noMatchTitle,
                            ),
                          )
                        : ListView.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              final category = controller
                                  .categoryById(entry.categoryId)
                                  .label;
                              return CheckboxListTile(
                                key: ValueKey(entry.id),
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  entry.note.isEmpty ? category : entry.note,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${l10n.dateYearMonthDay(entry.occurredAt)} · ${formatUserMoney(entry.amount, entry.currencyCode, forceUnit: entry.currencyCode != controller.activeBook.baseCurrencyCode)}',
                                ),
                                value: _selected.contains(entry.id),
                                onChanged: _saving
                                    ? null
                                    : (checked) => setState(() {
                                        if (checked == true) {
                                          _selected.add(entry.id);
                                        } else {
                                          _selected.remove(entry.id);
                                        }
                                      }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
