import 'models.dart';

const List<AccountGroup> defaultAccountGroups = <AccountGroup>[];

const List<Account> defaultAccounts = <Account>[];

const UserProfile defaultUserProfile = UserProfile(
  nickname: defaultProfileNickname,
  bio: '完全免费 · 数据自主',
  avatarDataUrl: '',
);

/// 按语言取默认个人资料（首启动/初始化播种用；中文为兼容基准）。
UserProfile defaultUserProfileFor({required bool english}) => english
    ? const UserProfile(
        nickname: defaultProfileNickname,
        bio: 'Completely free · Own your data',
        avatarDataUrl: '',
      )
    : defaultUserProfile;

final List<LedgerBook> defaultLedgerBooks = <LedgerBook>[
  LedgerBook(
    id: defaultLedgerBookId,
    name: '日常账本',
    createdAt: DateTime(2026),
    isDefault: true,
  ),
];

/// 按语言取默认账本（账本名是数据，播种后随用户编辑）。
List<LedgerBook> defaultLedgerBooksFor({required bool english}) => <LedgerBook>[
  LedgerBook(
    id: defaultLedgerBookId,
    name: english ? 'Daily Ledger' : '日常账本',
    createdAt: DateTime(2026),
    isDefault: true,
  ),
];

/// 一条默认分类的定义：语义键 + 展示文案。分类 id 一律随机生成、不承载语义，
/// 所以「这是什么分类」只认 [key]（见 lib/app/models/category_keys.dart）。
class CategorySeed {
  const CategorySeed({
    required this.key,
    required this.label,
    required this.type,
    required this.iconCode,
  });

  final String key;
  final String label;
  final EntryType type;
  final String iconCode;

  /// 实例化到某个账本下；[id] 由调用方生成（随机、全局唯一）。
  Category build({required String id, required String bookId}) => Category(
    id: id,
    bookId: bookId,
    key: key,
    label: label,
    type: type,
    iconCode: iconCode,
  );
}

/// 默认分类：每个新建账本播种一份。系统分类（余额调整）也是默认集的一员，
/// 每个账本各有一条。
const List<CategorySeed> defaultCategorySeeds = <CategorySeed>[
  CategorySeed(
    key: 'dining',
    label: '餐饮',
    type: EntryType.expense,
    iconCode: 'dining',
  ),
  CategorySeed(
    key: 'transport',
    label: '交通',
    type: EntryType.expense,
    iconCode: 'transport',
  ),
  CategorySeed(
    key: 'shopping',
    label: '购物',
    type: EntryType.expense,
    iconCode: 'shopping',
  ),
  CategorySeed(
    key: 'housing',
    label: '居住',
    type: EntryType.expense,
    iconCode: 'housing',
  ),
  CategorySeed(
    key: 'entertainment',
    label: '娱乐',
    type: EntryType.expense,
    iconCode: 'entertainment',
  ),
  CategorySeed(
    key: 'medical',
    label: '医疗',
    type: EntryType.expense,
    iconCode: 'medical',
  ),
  CategorySeed(
    key: balanceAdjustExpenseKey,
    label: '余额调整',
    type: EntryType.expense,
    iconCode: 'adjust',
  ),
  CategorySeed(
    key: 'salary',
    label: '工资',
    type: EntryType.income,
    iconCode: 'salary',
  ),
  CategorySeed(
    key: 'living',
    label: '生活费',
    type: EntryType.income,
    iconCode: 'savings',
  ),
  CategorySeed(
    key: 'interest',
    label: '利息',
    type: EntryType.income,
    iconCode: 'interest',
  ),
  CategorySeed(
    key: 'investment',
    label: '投资',
    type: EntryType.income,
    iconCode: 'investment',
  ),
  CategorySeed(
    key: 'bonus',
    label: '奖金',
    type: EntryType.income,
    iconCode: 'bonus',
  ),
  CategorySeed(
    key: 'part_time',
    label: '兼职',
    type: EntryType.income,
    iconCode: 'work',
  ),
  CategorySeed(
    key: balanceAdjustIncomeKey,
    label: '余额调整',
    type: EntryType.income,
    iconCode: 'adjust',
  ),
  CategorySeed(
    key: 'transfer_out',
    label: '转出',
    type: EntryType.transfer,
    iconCode: 'transfer_out',
  ),
  CategorySeed(
    key: 'transfer_in',
    label: '转入',
    type: EntryType.transfer,
    iconCode: 'transfer_in',
  ),
  CategorySeed(
    key: 'repayment',
    label: '还款',
    type: EntryType.transfer,
    iconCode: 'repayment',
  ),
];

/// 英文种子分类：键/图标与中文版一一对应，仅名称不同。
const List<CategorySeed> _defaultCategorySeedsEn = <CategorySeed>[
  CategorySeed(
    key: 'dining',
    label: 'Dining',
    type: EntryType.expense,
    iconCode: 'dining',
  ),
  CategorySeed(
    key: 'transport',
    label: 'Transport',
    type: EntryType.expense,
    iconCode: 'transport',
  ),
  CategorySeed(
    key: 'shopping',
    label: 'Shopping',
    type: EntryType.expense,
    iconCode: 'shopping',
  ),
  CategorySeed(
    key: 'housing',
    label: 'Housing',
    type: EntryType.expense,
    iconCode: 'housing',
  ),
  CategorySeed(
    key: 'entertainment',
    label: 'Entertainment',
    type: EntryType.expense,
    iconCode: 'entertainment',
  ),
  CategorySeed(
    key: 'medical',
    label: 'Medical',
    type: EntryType.expense,
    iconCode: 'medical',
  ),
  CategorySeed(
    key: balanceAdjustExpenseKey,
    label: 'Balance adjustment',
    type: EntryType.expense,
    iconCode: 'adjust',
  ),
  CategorySeed(
    key: 'salary',
    label: 'Salary',
    type: EntryType.income,
    iconCode: 'salary',
  ),
  CategorySeed(
    key: 'living',
    label: 'Allowance',
    type: EntryType.income,
    iconCode: 'savings',
  ),
  CategorySeed(
    key: 'interest',
    label: 'Interest',
    type: EntryType.income,
    iconCode: 'interest',
  ),
  CategorySeed(
    key: 'investment',
    label: 'Investment',
    type: EntryType.income,
    iconCode: 'investment',
  ),
  CategorySeed(
    key: 'bonus',
    label: 'Bonus',
    type: EntryType.income,
    iconCode: 'bonus',
  ),
  CategorySeed(
    key: 'part_time',
    label: 'Part-time',
    type: EntryType.income,
    iconCode: 'work',
  ),
  CategorySeed(
    key: balanceAdjustIncomeKey,
    label: 'Balance adjustment',
    type: EntryType.income,
    iconCode: 'adjust',
  ),
  CategorySeed(
    key: 'transfer_out',
    label: 'Transfer out',
    type: EntryType.transfer,
    iconCode: 'transfer_out',
  ),
  CategorySeed(
    key: 'transfer_in',
    label: 'Transfer in',
    type: EntryType.transfer,
    iconCode: 'transfer_in',
  ),
  CategorySeed(
    key: 'repayment',
    label: 'Repayment',
    type: EntryType.transfer,
    iconCode: 'repayment',
  ),
];

/// 按语言取默认分类的种子定义。
List<CategorySeed> categorySeedsFor({required bool english}) =>
    english ? _defaultCategorySeedsEn : defaultCategorySeeds;

// New Chinese books start with the user's Yimu taxonomy. Only labels are
// included here. Entries, balances, account names and notes come from import.
const _personalExpenses = <String, List<String>>{
  '食品餐饮': ['早餐', '午餐', '晚餐', '饮料酒水', '休闲零食', '水果', '生鲜食品', '请客吃饭', '粮油调味'],
  '购物消费': ['日常家居', '服饰运动', '手机数码', '个护美妆', '配饰腕表', '虚拟充值', '生活电器', '装修装饰'],
  '出行交通': ['公共交通', '地铁', '打车', '共享单车', '火车', '酒店', '保养修车'],
  '休闲娱乐': ['游戏', '运动健身', '旅游度假'],
  '居家生活': ['话费宽带', '个人清洁', '电费', '水费', '水电煤', '家政清洁', '空调', '校园卡'],
  '文化教育': ['学费', '培训考试', '书报杂志'],
  '送礼人情': ['红包', '礼物', '打赏', '孝敬长辈', '借出'],
  '健康医疗': ['买药', '医院'],
  '其他': ['无'],
};
const _personalIncome = [
  '生活费',
  '收红包',
  '二手闲置',
  '研究生低保',
  '奖金',
  '其他',
  '收入',
  '助学贷款',
  '工资',
  '兼职外快',
  '礼金人情',
  '无',
];

List<Category> _newBookCategories(
  String bookId,
  bool english,
  String Function() nextId,
) {
  if (english) {
    return [
      for (final seed in _defaultCategorySeedsEn)
        seed.build(id: nextId(), bookId: bookId),
    ];
  }
  const expenseKeys = {
    '食品餐饮': 'dining',
    '出行交通': 'transport',
    '购物消费': 'shopping',
    '居家生活': 'housing',
    '休闲娱乐': 'entertainment',
    '健康医疗': 'medical',
  };
  const incomeKeys = {
    '工资': 'salary',
    '生活费': 'living',
    '奖金': 'bonus',
    '兼职外快': 'part_time',
  };
  final result = <Category>[];
  for (final group in {..._personalExpenses, '收入': _personalIncome}.entries) {
    final isIncome = group.key == '收入';
    final type = isIncome ? EntryType.income : EntryType.expense;
    final parentKey = expenseKeys[group.key];
    final parent = Category(
      id: nextId(),
      bookId: bookId,
      label: group.key,
      type: type,
      key: parentKey,
      iconCode: parentKey ?? (isIncome ? 'salary' : 'category'),
    );
    result.add(parent);
    for (final label in group.value) {
      result.add(
        Category(
          id: nextId(),
          bookId: bookId,
          label: label,
          type: type,
          parentId: parent.id,
          key: isIncome ? incomeKeys[label] : null,
          iconCode: parent.iconCode,
        ),
      );
    }
  }
  for (final seed in defaultCategorySeeds) {
    if (seed.type == EntryType.transfer ||
        seed.key == balanceAdjustExpenseKey ||
        seed.key == balanceAdjustIncomeKey) {
      result.add(seed.build(id: nextId(), bookId: bookId));
    }
  }
  return result;
}

/// 给**还没有任何分类**的账本补一份默认分类，返回新列表（首启动、新建账本、
/// 导入缺分类的备份与载入自愈共用同一入口，避免到处手写「分类为空才播种」）。
/// [nextId] 由调用方提供，保证新分类的 id 与其它实体同源地随机生成。
List<Category> withSeededBookCategories(
  List<Category> categories, {
  required Iterable<String> bookIds,
  required bool english,
  required String Function() nextId,
}) {
  final result = List<Category>.of(categories);
  final booksWithCategories = <String>{
    for (final category in result) category.bookId,
  };
  for (final bookId in bookIds) {
    if (!booksWithCategories.add(bookId)) {
      continue;
    }
    result.addAll(_newBookCategories(bookId, english, nextId));
  }
  return result;
}
