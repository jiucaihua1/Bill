part of 'assets_pages.dart';

class _AssetDebtPage extends StatelessWidget {
  const _AssetDebtPage();

  @override
  Widget build(BuildContext context) {
    final controller = VeriFinScope.of(context);
    final l10n = AppLocalizations.of(context);
    final currencyCode = controller.activeBook.baseCurrencyCode;
    final unit = optionalCurrencyUnit(currencyCode);
    const mode = AssetAccountViewMode.type;
    final balances = <Account, double>{};
    final payable = <Account>[];
    final receivable = <Account>[];
    final credit = <Account>[];
    for (final account in _sortedAccounts(controller.accounts)) {
      if (account.hidden ||
          !(account.type.isDebt || account.type.supportsCredit)) {
        continue;
      }
      final balance = controller.accountBalance(account);
      if (account.type == AccountType.payable) {
        payable.add(account);
      } else if (account.type == AccountType.receivable) {
        receivable.add(account);
      } else if (balance < 0) {
        credit.add(account);
      } else {
        continue;
      }
      balances[account] = balance;
    }
    final valuation = controller.accountBalancesInBase(
      accounts: balances.keys.where((account) => account.includeInAssets),
    );
    final sections = [
      _AssetAccountSection(
        id: AccountType.payable.name,
        title: l10n.accountTypePayable,
        accounts: payable,
      ),
      _AssetAccountSection(
        id: AccountType.receivable.name,
        title: l10n.accountTypeReceivable,
        accounts: receivable,
      ),
      _AssetAccountSection(
        id: 'credit_debt',
        title: l10n.assetCreditDebt,
        accounts: credit,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: VeriPage(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
            children: [
              VeriHeader(
                title: l10n.entryTypeDebt,
                subtitle: unit == null
                    ? null
                    : l10n.baseCurrencyAmountLabel(unit),
                showBack: true,
                actions: [_assetAmountVisibilityAction(controller, l10n)],
              ),
              const SizedBox(height: 12),
              if (!valuation.isComplete) ...[
                VeriCard(
                  onTap: () => _openCurrencyRates(context),
                  child: AssetMissingRateNotice(
                    affectedAccountCount: valuation.affectedAccountIds.length,
                    currencyCodes: valuation.missingCurrencyCodes,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (balances.isEmpty)
                VeriCard(
                  child: EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: l10n.assetDebtEmptyTitle,
                    description: l10n.assetDebtEmptyDesc,
                  ),
                ),
              for (final section in sections)
                if (section.accounts.isNotEmpty)
                  Padding(
                    key: ValueKey('asset_debt_section_${section.id}'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AccountSectionCard(
                      title: section.title,
                      accounts: controller.sortedAccountsForAssetSection(
                        mode: mode,
                        sectionId: section.id,
                        accounts: section.accounts,
                      ),
                      balances: balances,
                      hideAmounts: controller.assetAmountsHidden,
                      totalText: section.id == AccountType.receivable.name
                          ? _assetSectionTotalText(
                              accounts: section.accounts,
                              valuation: valuation,
                              baseCurrencyCode: currencyCode,
                            )
                          : formatAssetAmount(
                              _assetDebtTotal(
                                section.accounts,
                                balances,
                                valuation,
                              ),
                              currencyCode,
                              hidden: false,
                            ),
                      collapsed: controller.isAssetSectionCollapsed(
                        mode: mode,
                        sectionId: section.id,
                      ),
                      onToggleCollapsed: () =>
                          controller.toggleAssetSectionCollapsed(
                            mode: mode,
                            sectionId: section.id,
                          ),
                      onAccountTap: (account) =>
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  AccountDetailPage(account: account),
                            ),
                          ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

HeaderAction _assetAmountVisibilityAction(
  VeriFinController controller,
  AppLocalizations l10n,
) {
  final hidden = controller.assetAmountsHidden;
  return HeaderAction(
    key: const Key('asset_amount_visibility'),
    icon: hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
    tooltip: hidden ? l10n.showAssetAmounts : l10n.hideAssetAmounts,
    onPressed: () => unawaited(controller.setAssetAmountsHidden(!hidden)),
  );
}

double? _assetDebtTotal(
  Iterable<Account> accounts,
  Map<Account, double> balances,
  ConvertedAccountBalances valuation,
) {
  var total = 0.0;
  for (final account in accounts) {
    if (!account.includeInAssets ||
        !(account.type == AccountType.payable || account.type.supportsCredit) ||
        (balances[account] ?? 0) >= 0) {
      continue;
    }
    final value = valuation.amountsByAccountId[account.id];
    if (value == null) return null;
    total -= value;
  }
  return total;
}
