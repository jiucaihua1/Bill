import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'calc_expression.dart';
import 'category_tree.dart';
import 'common_widgets.dart';
import 'currency_catalog.dart';
import 'currency_math.dart';
import 'haptics.dart';
import 'ledger_math.dart';
import 'models.dart';
import '../l10n/app_localizations.dart';

/// 金额键盘。作为弹层时经 `showNumberPadSheet` 打开，手动记账页使用内嵌布局。
class NumberPadSheet extends StatefulWidget {
  const NumberPadSheet({
    super.key,
    required this.title,
    this.initialAmount,
    this.allowNegative = false,
    this.allowZero = false,
    this.maxAmount,
    this.maxFractionDigits = 2,
    this.currencyCode,
    this.layout = NumberPadLayout.phone,
    this.showTitle = true,
  }) : onAmountChanged = null,
       onSubmitted = null,
       onContinue = null,
       onCancel = null,
       submitEnabled = true,
       blockReason = null,
       amountLeading = null,
       amountColor = null,
       metadata = null,
       assert(maxFractionDigits >= 0 && maxFractionDigits <= 12);

  const NumberPadSheet.inline({
    super.key,
    required this.initialAmount,
    required String this.currencyCode,
    required this.maxFractionDigits,
    this.layout = NumberPadLayout.phone,
    required ValueChanged<double?> this.onAmountChanged,
    required ValueChanged<double> this.onSubmitted,
    required ValueChanged<double> this.onContinue,
    required VoidCallback this.onCancel,
    required this.submitEnabled,
    this.blockReason,
    this.amountLeading,
    this.amountColor,
    required this.metadata,
  }) : title = '',
       showTitle = false,
       allowNegative = false,
       allowZero = false,
       maxAmount = null,
       assert(maxFractionDigits >= 0 && maxFractionDigits <= 12);

  final String title;
  final double? initialAmount;
  final bool allowNegative;
  final bool allowZero;

  /// 单个操作数允许的小数位数。普通金额默认为 2；本地汇率可提高到 10。
  final int maxFractionDigits;
  final String? currencyCode;
  final NumberPadLayout layout;
  final ValueChanged<double?>? onAmountChanged;
  final ValueChanged<double>? onSubmitted;
  final ValueChanged<double>? onContinue;
  final VoidCallback? onCancel;
  final bool submitEnabled;
  final String? blockReason;
  final Widget? amountLeading;
  final Color? amountColor;
  final Widget? metadata;

  /// 快速记账入口已由底部按钮表达语义，金额键盘不重复显示标题。
  final bool showTitle;

  /// 可选金额上限：非空时输入框下方展示「最多 {max}」提示（超上限时变红），
  /// 点 OK 确认的结果会被封顶到该值。用于退款「剩余可退」等有上限的输入。
  final double? maxAmount;

  @override
  State<NumberPadSheet> createState() => _NumberPadSheetState();
}

class _NumberPadSheetState extends State<NumberPadSheet> {
  final _amountFocus = FocusNode();
  late final _editor = TextEditingController.fromValue(
    _valueAtEnd(_initialInput(widget.initialAmount, widget.maxFractionDigits)),
  );

  String get _input => _editor.text;

  static TextEditingValue _valueAtEnd(String input) => TextEditingValue(
    text: input,
    selection: TextSelection.collapsed(offset: input.length),
  );

  @override
  void dispose() {
    _editor.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  /// 初始输入串：空值与 0 都从空输入开始，不再把 `0` 预填成值。
  ///
  /// 预填的 `0` 会被当成已输入内容——按数字要顶掉它、按运算符要接在它后面，
  /// 用户看不到「还没输入」的状态。0 由占位提示表达；需要确认 0 的场景走
  /// `allowZero`，清空后按 OK 仍会提交 0。
  static String _initialInput(double? amount, int fractionDigits) {
    if (amount == null || amount == 0) {
      return '';
    }
    return _formatInitialValue(amount, fractionDigits);
  }

  /// 求值当前输入（可能是 `500+800` 这类算式）；不完整/无效时为 null。
  double? get _result =>
      evaluateAmountExpression(_input, decimalPlaces: widget.maxFractionDigits);
  double get _amount => _result ?? 0;
  bool get _inline => widget.onSubmitted != null;

  /// 输入是否为算式（含运算符）——决定是否展示右下角结果预览。
  bool get _hasOperator => amountExpressionHasOperator(_input);

  @override
  Widget build(BuildContext context) {
    // 页内备注由系统键盘编辑。只在金额与键盘区处理底部遮挡，分类网格只读取宽度和字号。
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomInset = _inline
        ? MediaQuery.viewPaddingOf(context).bottom
        : math.max(keyboardInset, MediaQuery.paddingOf(context).bottom);
    final tokens = VeriStyleTokens.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metadataSurface = Color.lerp(
      tokens.cardColor,
      tokens.surfaceAltColor,
      0.45,
    );
    final symbol = CurrencyCatalog.find(widget.currencyCode)?.symbol;
    Widget amountDisplayBox(Widget display) {
      return Container(
        width: widget.amountLeading == null ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: _inline ? 5 : 12,
        ),
        decoration: BoxDecoration(
          color: _inline ? metadataSurface : tokens.raisedSurfaceColor,
          borderRadius: BorderRadius.circular(tokens.innerRadius),
          border: _inline
              ? null
              : Border.all(
                  color: Color.lerp(tokens.borderColor, scheme.primary, 0.22)!,
                ),
        ),
        child: _inline && symbol != null
            ? Row(
                children: [
                  Text(
                    symbol,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: display),
                ],
              )
            : display,
      );
    }

    Widget amountRow(Widget display) {
      final leading = widget.amountLeading;
      if (leading == null) return amountDisplayBox(display);
      return Row(
        children: [
          Expanded(
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: metadataSurface,
                borderRadius: BorderRadius.circular(tokens.innerRadius),
              ),
              child: leading,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 112, maxWidth: 180),
            child: amountDisplayBox(display),
          ),
        ],
      );
    }

    final body = Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: veriPageMaxWidth),
        child: Padding(
          padding: _inline
              ? EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset)
              : EdgeInsets.fromLTRB(14, 14, 14, 14 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (widget.showTitle) ...[
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // 隔离频繁变动的金额显示和下方键区。
              RepaintBoundary(
                child: amountRow(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      TextField(
                        key: const Key('number_pad_display'),
                        controller: _editor,
                        focusNode: _amountFocus,
                        groupId: _amountFocus,
                        readOnly: true,
                        showCursor: true,
                        selectAllOnFocus: false,
                        keyboardType: TextInputType.none,
                        onTapOutside: (_) => _amountFocus.unfocus(),
                        textAlign: TextAlign.end,
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                        cursorColor: scheme.primary,
                        decoration: InputDecoration(
                          hintText: _inline
                              ? formatCurrencyNumber(
                                  0,
                                  widget.currencyCode!,
                                  style: CurrencyFractionStyle.standard,
                                )
                              : AppLocalizations.of(
                                  context,
                                ).numberPadAmountHint,
                          hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: widget.amountColor ?? tokens.inkColor,
                        ),
                      ),
                      // 算式模式在右下角展示浅色结果预览；不完整则提示。
                      if (_hasOperator) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          _result == null
                              ? AppLocalizations.of(context).calcIncomplete
                              : '= ${_formatResult(_result!)}',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (widget.metadata case final metadata?) ...[
                const SizedBox(height: 8),
                metadata,
              ],
              if (widget.maxAmount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    AppLocalizations.of(context).numberPadMax(
                      widget.currencyCode == null
                          ? formatAmount(widget.maxAmount!)
                          : formatCurrencyNumber(
                              widget.maxAmount!,
                              widget.currencyCode!,
                            ),
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _amount > widget.maxAmount! + _maxTolerance
                          ? veriSemantic(context, veriExpense)
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.55),
                      fontWeight: _amount > widget.maxAmount! + _maxTolerance
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              if (widget.blockReason case final reason? when _canSubmit)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    reason,
                    key: const Key('entry_save_block_reason'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(height: _inline ? 8 : 12),
              TextFieldTapRegion(
                groupId: _amountFocus,
                child: _buildKeyTray(
                  context,
                  keyboardOverlap: _inline
                      ? math.max(0.0, keyboardInset - bottomInset)
                      : 0.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!_inline) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.cardColor,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.cardRadius),
        ),
        border: Border(top: BorderSide(color: tokens.borderColor)),
      ),
      child: body,
    );
  }

  Widget _buildKeyTray(
    BuildContext context, {
    required double keyboardOverlap,
  }) {
    final tokens = VeriStyleTokens.of(context);
    final keys = LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        final cellWidth = (constraints.maxWidth - spacing * 3) / 4;
        return _buildKeys(
          context,
          cellWidth,
          spacing,
          keyboardOverlap: keyboardOverlap,
        );
      },
    );
    if (keyboardOverlap > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: keys,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(tokens.cardColor, tokens.surfaceAltColor, 0.68),
        borderRadius: BorderRadius.circular(tokens.innerRadius),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Padding(padding: const EdgeInsets.all(8), child: keys),
    );
  }

  Widget _buildKeys(
    BuildContext context,
    double width,
    double spacing, {
    required double keyboardOverlap,
  }) {
    final height = math.min(
      width * 0.75,
      (MediaQuery.sizeOf(context).height * 0.065).clamp(28.0, 54.0),
    );
    if (keyboardOverlap > 0) {
      // 输入法开始展开时仍占住原数字键区，备注不会先下坠、再被系统键盘推上去。
      return SizedBox(
        height: math.max(height * 4 + spacing * 3 + 16, keyboardOverlap),
      );
    }
    Widget cell(String value, {double? cellWidth}) => SizedBox(
      width: cellWidth ?? width,
      height: height,
      child: _buildKey(context, value),
    );
    Widget splitCell(String left, String right) {
      final halfWidth = (width - spacing) / 2;
      return Row(
        spacing: spacing,
        children: [
          cell(left, cellWidth: halfWidth),
          cell(right, cellWidth: halfWidth),
        ],
      );
    }

    Widget numberRow(List<String> digits, Widget end) => Row(
      spacing: spacing,
      children: [...digits.map((digit) => cell(digit)), end],
    );

    const lowDigits = ['1', '2', '3'];
    const highDigits = ['7', '8', '9'];
    final ascending = widget.layout == NumberPadLayout.phone;

    return RepaintBoundary(
      child: Column(
        spacing: spacing,
        children: [
          numberRow(ascending ? lowDigits : highDigits, cell('⌫')),
          numberRow(const ['4', '5', '6'], splitCell('+', '-')),
          numberRow(ascending ? highDigits : lowDigits, splitCell('×', '÷')),
          Row(
            spacing: spacing,
            children: [
              cell(_inline ? 'AGAIN' : 'C'),
              cell('0'),
              cell('.'),
              cell(_inline && _input.isEmpty ? 'CANCEL' : 'OK'),
            ],
          ),
        ],
      ),
    );
  }

  /// 单个按键：尺寸由外层 SizedBox 约束，按分组配色。
  Widget _buildKey(BuildContext context, String value) {
    final isOk = value == 'OK';
    final isContinue = value == 'AGAIN';
    final isSubmit = isOk || isContinue;
    final isOperator = _operators.contains(value);
    final isUtility = value == 'C' || value == '⌫' || value == 'CANCEL';
    final isDot = value == '.';
    final tokens = VeriStyleTokens.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSubmit = _canSubmit && widget.submitEnabled;
    final enabled =
        (!isSubmit || canSubmit) && (!isDot || widget.maxFractionDigits > 0);
    final buttonBackground = switch (value) {
      'OK' => scheme.primary,
      'AGAIN' => Color.lerp(
        tokens.raisedSurfaceColor,
        scheme.primaryContainer,
        0.46,
      )!,
      _ when isOperator => Color.lerp(
        tokens.raisedSurfaceColor,
        scheme.secondaryContainer,
        0.58,
      )!,
      _ when isUtility => tokens.cardColor,
      _ => tokens.raisedSurfaceColor,
    };
    final buttonForeground = switch (value) {
      'OK' => scheme.onPrimary,
      'AGAIN' => scheme.onPrimaryContainer,
      _ when isOperator => scheme.onSecondaryContainer,
      _ when isUtility => scheme.onSurfaceVariant,
      _ => tokens.inkColor,
    };
    final l10n = AppLocalizations.of(context);
    final label = switch (value) {
      'OK' when _inline => l10n.commonDone,
      'OK' => l10n.commonConfirm,
      'AGAIN' => l10n.entrySaveAndContinue,
      'C' => l10n.numberPadClear,
      'CANCEL' => l10n.commonCancel,
      _ => value,
    };
    return FilledButton.tonal(
      key: isOk
          ? Key(_inline ? 'save_entry_button' : 'number_pad_ok')
          : Key('number_key_$value'),
      style: FilledButton.styleFrom(
        backgroundColor: buttonBackground,
        foregroundColor: buttonForeground,
        disabledBackgroundColor: tokens.cardColor,
        disabledForegroundColor: scheme.onSurfaceVariant.withValues(
          alpha: 0.46,
        ),
        side: isOk && enabled
            ? BorderSide.none
            : BorderSide(color: tokens.borderColor),
        textStyle:
            (isSubmit || isUtility
                    ? theme.textTheme.labelLarge
                    : theme.textTheme.titleLarge)
                ?.copyWith(
                  fontWeight: isOperator ? FontWeight.w600 : FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(veriRadiusMd),
        ),
      ),
      onPressed: enabled ? () => _handleKey(value) : null,
      onLongPress: _inline && value == '⌫' ? () => _handleKey('C') : null,
      child: value == '⌫'
          ? const Icon(Icons.backspace_outlined, size: 19)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
            ),
    );
  }

  bool get _canSubmit {
    final result = _result;
    if (result == null) {
      // 空输入在允许零时视为 0（清空后可直接确认为 0，如清除预算/信用额度）；
      // 非空但算式不完整/无效（如末尾挂着运算符）时才不允许确认。
      return _input.isEmpty && widget.allowZero;
    }
    if (widget.allowNegative) {
      final isZero = widget.currencyCode == null
          ? isZeroAmount(result)
          : isZeroCurrencyAmount(result, widget.currencyCode!);
      return widget.allowZero || !isZero;
    }
    return widget.allowZero ? result >= 0 : result > 0;
  }

  double get _maxTolerance => widget.currencyCode == null
      ? 0.0001
      : currencyAmountTolerance(widget.currencyCode!);

  static const String _operators = '+-×÷';
  static final _operandSeparator = RegExp(r'[+\-×÷]');

  void _handleKey(String value) {
    if (value == 'CANCEL') {
      widget.onCancel?.call();
      return;
    }
    if (value == 'AGAIN') {
      widget.onContinue?.call(_amount);
      return;
    }
    // 数字键与确认键分两档：确认是一次明确提交，按重一档给反馈。
    if (value == 'OK') {
      final max = widget.maxAmount;
      // 有上限时确认即封顶（配合下方「最多 xxx」提示，超额当场生效、不必等保存）。
      final result = max != null && _amount > max ? max : _amount;
      final submit = widget.onSubmitted;
      if (submit != null) {
        submit(result);
      } else {
        VeriHaptics.commit();
        Navigator.of(context).pop(result);
      }
      return;
    }

    VeriHaptics.tap();
    final edit = value == 'C' ? _valueAtEnd('') : _editAtSelection(value);
    if (edit != null) {
      setState(() => _editor.value = edit);
      widget.onAmountChanged?.call(_result);
    }
    _amountFocus.requestFocus();
  }

  TextEditingValue? _editAtSelection(String key) {
    final input = _input;
    final selection = _editor.selection;
    final length = input.length;
    var start = selection.isValid ? math.min(selection.start, length) : length;
    var end = selection.isValid ? math.min(selection.end, length) : length;
    var inserted = key;
    bool isOperatorAt(int index) =>
        index >= 0 && index < length && _operators.contains(input[index]);

    if (key == '⌫') {
      if (start == end && start > 0) start--;
      inserted = '';
    } else if (_operators.contains(key)) {
      if (start > 0 && input[start - 1] == '.') start--;
      if (start > 0 && isOperatorAt(start - 1)) start--;
      if (start == 0 && !(widget.allowNegative && key == '-')) return null;
      if (isOperatorAt(end)) end++;
    } else if (key == '.') {
      if (widget.maxFractionDigits == 0) return null;
      if (start == 0 || isOperatorAt(start - 1)) inserted = '0.';
    } else if (start > 0 &&
        input[start - 1] == '0' &&
        (start == 1 || isOperatorAt(start - 2)) &&
        (end == length || isOperatorAt(end))) {
      // Replace a lone leading zero before continuing the operand.
      start--;
    }

    final candidate = input.replaceRange(start, end, inserted);
    for (final operand in candidate.split(_operandSeparator)) {
      final dot = operand.indexOf('.');
      if (dot >= 0 &&
          (dot != operand.lastIndexOf('.') ||
              operand.length - dot - 1 > widget.maxFractionDigits)) {
        return null;
      }
    }
    return TextEditingValue(
      text: candidate,
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
  }

  String _formatResult(double value) =>
      _formatInitialValue(value, widget.maxFractionDigits);

  static String _formatInitialValue(double value, int fractionDigits) {
    final fixed = value.toStringAsFixed(fractionDigits);
    if (!fixed.contains('.')) return fixed;
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

/// 记账时选择分类的底部弹窗。支持多级分类：父分类可展开/收起，
/// 子分类缩进显示，点选任意层级的分类（父或子）都会返回其 id。
/// [CategoryPickerSheet] 选择「移到顶级」时返回的哨兵值（区别于任何真实分类 id）。
const String categoryPickerTopLevel = '__category_picker_top_level__';

/// [CategoryPickerSheet] 选择「全部分类」时返回的哨兵值（筛选场景用）。
const String categoryPickerAll = '__category_picker_all__';

/// 分类选择弹层组件体。**勿直接实例化**——统一走 `pages/sheets.dart` 的
/// `showCategoryPickerSheet`。
class CategoryPickerSheet extends StatefulWidget {
  const CategoryPickerSheet({
    super.key,
    required this.categories,
    required this.selectedId,
    this.title,
    this.topLevelLabel,
    this.allLabel,
  });

  /// 当前类型下的全部分类（含各级子分类），由调用方按类型过滤后传入。
  final List<Category> categories;
  final String selectedId;

  /// 弹窗标题；为空时用「全部分类」。
  final String? title;

  /// 非空时在列表顶部加一个「移到顶级」选项，点选返回 [categoryPickerTopLevel]。
  final String? topLevelLabel;

  /// 非空时在列表顶部加一个「全部」选项（筛选场景），点选返回 [categoryPickerAll]；
  /// 当 [selectedId] 为 [categoryPickerAll] 时该项高亮。
  final String? allLabel;

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  late final Set<String> _collapsed;

  @override
  void initState() {
    super.initState();
    // 默认展开全部；但收起与当前选中项无关的分支，保持已选项可见。
    _collapsed = <String>{};
  }

  /// 按类型分区（支出→收入→转账）并按折叠状态前序展开：每个非空类型前插入一行
  /// 类型标题，区内根分类保持列表顺序（= 用户在分类页拖拽设置的顺序），子分类缩进。
  List<_CategoryPickerRow> _buildRows() {
    final rows = <_CategoryPickerRow>[];
    final visited = <String>{};
    void walkChildren(String parentId, int depth) {
      for (final child in widget.categories.where(
        (c) => c.parentId == parentId,
      )) {
        if (!visited.add(child.id)) {
          continue;
        }
        rows.add(
          _CategoryPickerRow.node(CategoryNode(category: child, depth: depth)),
        );
        final hasKids = widget.categories.any((c) => c.parentId == child.id);
        if (hasKids && !_collapsed.contains(child.id)) {
          walkChildren(child.id, depth + 1);
        }
      }
    }

    // 类型顺序固定为 支出→收入→转账；末尾兜底追加任何其它出现过的顶级类型（防御，
    // 正常不会有 refund 类分类）。
    final types = <EntryType>[
      for (final type in const <EntryType>[
        EntryType.expense,
        EntryType.income,
        EntryType.transfer,
      ])
        if (widget.categories.any((c) => c.parentId == null && c.type == type))
          type,
    ];
    for (final root in widget.categories.where((c) => c.parentId == null)) {
      if (!types.contains(root.type)) {
        types.add(root.type);
      }
    }

    for (final type in types) {
      rows.add(_CategoryPickerRow.header(type));
      for (final root in widget.categories.where(
        (c) => c.parentId == null && c.type == type,
      )) {
        if (!visited.add(root.id)) {
          continue;
        }
        rows.add(
          _CategoryPickerRow.node(CategoryNode(category: root, depth: 0)),
        );
        final hasKids = widget.categories.any((c) => c.parentId == root.id);
        if (hasKids && !_collapsed.contains(root.id)) {
          walkChildren(root.id, 1);
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    // 「全部」「移到顶级」等非分类的元操作项用中性主题色（深浅色自适应），不用蓝色。
    final metaIconColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.title ?? AppLocalizations.of(context).categoryAll,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (widget.allLabel != null)
            ListTile(
              minTileHeight: 48,
              dense: true,
              selected: widget.selectedId == categoryPickerAll,
              selectedTileColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(veriRadiusSm),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: VeriIconBox(
                icon: Icons.select_all,
                color: metaIconColor,
                size: 32,
              ),
              title: Text(
                widget.allLabel!,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: widget.selectedId == categoryPickerAll
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
              trailing: widget.selectedId == categoryPickerAll
                  ? Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                      size: 18,
                    )
                  : null,
              onTap: () {
                VeriHaptics.tick();
                Navigator.of(context).pop(categoryPickerAll);
              },
            ),
          if (widget.topLevelLabel != null)
            ListTile(
              minTileHeight: 48,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: VeriIconBox(
                icon: Icons.vertical_align_top,
                color: metaIconColor,
                size: 32,
              ),
              title: Text(
                widget.topLevelLabel!,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                VeriHaptics.tick();
                Navigator.of(context).pop(categoryPickerTopLevel);
              },
            ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: rows.length,
              separatorBuilder: (context, index) {
                // 类型标题行两侧不画分隔线。
                if (rows[index].isHeader || rows[index + 1].isHeader) {
                  return const SizedBox.shrink();
                }
                return Divider(
                  height: 1,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.06),
                );
              },
              itemBuilder: (context, index) {
                final row = rows[index];
                if (row.isHeader) {
                  final type = row.headerType!;
                  return Padding(
                    padding: EdgeInsets.only(
                      left: 8,
                      right: 8,
                      top: index == 0 ? 2 : 14,
                      bottom: 4,
                    ),
                    child: Text(
                      type.label(AppLocalizations.of(context)),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorForType(context, type),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  );
                }
                final node = row.node!;
                final category = node.category;
                final isSelected = category.id == widget.selectedId;
                final hasKids = widget.categories.any(
                  (c) => c.parentId == category.id,
                );
                final collapsed = _collapsed.contains(category.id);
                return Material(
                  color: isSelected
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(veriRadiusSm),
                  child: ListTile(
                    minTileHeight: 48,
                    dense: true,
                    contentPadding: EdgeInsets.only(
                      left: 8 + node.depth * 20,
                      right: 8,
                    ),
                    leading: CategoryIconBox(
                      iconCode: category.iconCode,
                      categoryName: category.label,
                      color: colorForType(context, category.type),
                      size: 32,
                    ),
                    title: Text(
                      category.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    trailing: hasKids
                        ? IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 22,
                            icon: Icon(
                              collapsed
                                  ? Icons.chevron_right
                                  : Icons.expand_more,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                            onPressed: () => setState(() {
                              if (collapsed) {
                                _collapsed.remove(category.id);
                              } else {
                                _collapsed.add(category.id);
                              }
                            }),
                          )
                        : (isSelected
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 18,
                                )
                              : null),
                    onTap: () {
                      VeriHaptics.tick();
                      Navigator.of(context).pop(category.id);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类选择弹窗的列表行：要么是一行类型标题（[headerType]），要么是一个分类节点
/// （[node]）。用于把分类按 支出/收入/转账 分区展示。
class _CategoryPickerRow {
  const _CategoryPickerRow.header(EntryType type)
    : headerType = type,
      node = null;
  const _CategoryPickerRow.node(CategoryNode this.node) : headerType = null;

  final EntryType? headerType;
  final CategoryNode? node;

  bool get isHeader => headerType != null;
}

/// 记账时给交易多选标签的底部弹窗。展示已有标签的 FilterChip 供多选，
/// 并可即时新建标签。点「完成」返回选中的标签 id 列表（取消返回 null）。
/// Lightweight action or selection used by entry metadata and its pickers.
class EntryMetadataPill extends StatelessWidget {
  const EntryMetadataPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.compact = false,
    this.selected = false,
    this.toggle = false,
  });

  final Widget label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool compact;
  final bool selected;
  final bool toggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = VeriStyleTokens.of(context);
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final ink = onTap == null ? foreground.withValues(alpha: 0.46) : foreground;
    return Material(
      color: selected ? scheme.primaryContainer : tokens.raisedSurfaceColor,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? Color.lerp(tokens.borderColor, scheme.primary, 0.38)!
              : tokens.borderColor,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        toggled: toggle ? selected : null,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 34 : 38),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 12,
                vertical: 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (icon case final glyph?) ...[
                    Icon(glyph, size: compact ? 13 : 16, color: ink),
                    SizedBox(width: compact ? 3 : 6),
                  ],
                  Flexible(
                    child: DefaultTextStyle.merge(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (compact
                                  ? theme.textTheme.labelSmall
                                  : theme.textTheme.labelMedium)
                              ?.copyWith(
                                color: ink,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                      child: label,
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

/// 标签选择弹层组件体。**勿直接实例化**——统一走 `pages/sheets.dart` 的
/// `showTagSelectorSheet`。
class TagSelectorSheet extends StatefulWidget {
  const TagSelectorSheet({
    super.key,
    required this.tags,
    required this.selectedIds,
    this.onCreateTag,
  });

  final List<Tag> tags;
  final List<String> selectedIds;

  /// 新建标签：由调用方弹出输入框、创建标签，并返回新标签（重名返回已有，取消返回 null）。
  final Future<Tag?> Function()? onCreateTag;

  @override
  State<TagSelectorSheet> createState() => _TagSelectorSheetState();
}

class _TagSelectorSheetState extends State<TagSelectorSheet> {
  late final Set<String> _selected = <String>{...widget.selectedIds};
  late List<Tag> _tags = <Tag>[...widget.tags];

  Future<void> _createTag() async {
    final tag = await widget.onCreateTag?.call();
    if (!mounted || tag == null) {
      return;
    }
    setState(() {
      if (!_tags.any((t) => t.id == tag.id)) {
        _tags = <Tag>[..._tags, tag];
      }
      _selected.add(tag.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                AppLocalizations.of(context).tagPickerTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(_selected.toList()),
                child: Text(AppLocalizations.of(context).commonDone),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final tag in _tags)
                    EntryMetadataPill(
                      label: Text(tag.label),
                      selected: _selected.contains(tag.id),
                      toggle: true,
                      onTap: () {
                        VeriHaptics.tap();
                        setState(() {
                          if (!_selected.remove(tag.id)) {
                            _selected.add(tag.id);
                          }
                        });
                      },
                    ),
                  if (widget.onCreateTag != null)
                    EntryMetadataPill(
                      icon: Icons.add,
                      label: Text(AppLocalizations.of(context).tagCreateTitle),
                      onTap: _createTag,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
