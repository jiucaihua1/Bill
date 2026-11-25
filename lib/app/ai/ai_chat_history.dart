import 'dart:convert';

import '../models.dart';
import 'ai_agent_event.dart';
import 'ai_agent_step.dart';
import 'ai_answer_provenance.dart';
import 'ai_chat_session_controller.dart';
import 'ai_query_tool.dart';

/// 设备本地聊天记录格式。按完整问答保留最近历史，并限制偏好存储大小。
abstract final class AiChatHistory {
  static const int _maxTurns = 24;
  static const int _maxBytes = 512 * 1024;

  static String encode(List<AiChatMessage> messages) {
    final turns = <String>[];
    var size = 2; // 外层数组的方括号。
    for (var end = messages.length; end >= 2 && turns.length < _maxTurns;) {
      final answer = messages[--end];
      final question = messages[--end];
      String encodeTurn({required bool includeDetails}) => jsonEncode([
        _encodeMessage(question, includeDetails: false),
        _encodeMessage(answer, includeDetails: includeDetails),
      ]);
      var turn = encodeTurn(includeDetails: true);
      var turnSize = utf8.encode(turn).length;
      if (turns.isEmpty && turnSize > _maxBytes - size) {
        // 极长工具结果让位给这轮问答正文，仍保留来源和重试信息。
        turn = encodeTurn(includeDetails: false);
        turnSize = utf8.encode(turn).length;
      }
      if (size + turnSize + (turns.isEmpty ? 0 : 1) > _maxBytes) break;
      size += turnSize + (turns.isEmpty ? 0 : 1);
      turns.add(turn);
    }
    return '[${turns.reversed.join(',')}]';
  }

  static List<AiChatMessage> decode(String? data, String bookId) {
    if (data == null || utf8.encode(data).length > _maxBytes) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return const [];
    }
    if (decoded is! List<Object?>) return const [];
    final messages = <AiChatMessage>[];
    for (final turn in decoded.reversed.take(_maxTurns).toList().reversed) {
      if (turn is! List<Object?> || turn.length != 2) continue;
      try {
        final question = _decodeMessage(_map(turn.first), bookId);
        final answer = _decodeMessage(_map(turn.last), bookId);
        if (question.role != AiChatRole.user ||
            answer.role != AiChatRole.assistant) {
          continue;
        }
        messages.addAll([question, answer]);
      } on TypeError {
        continue;
      } on ArgumentError {
        continue;
      } on FormatException {
        continue;
      }
    }
    return messages;
  }

  static Map<String, Object?> _encodeMessage(
    AiChatMessage message, {
    required bool includeDetails,
  }) => {
    'role': message.role.name,
    'bookName': message.bookName,
    'currency': message.baseCurrencyCode,
    'moneyDisplay': message.moneyCodeDisplay.name,
    'text': message.text,
    'status': message.status.name,
    if (message.sourceUserInput.isNotEmpty) 'input': message.sourceUserInput,
    if (message.provenance case final provenance?)
      'provenance': provenance.name,
    'successfulToolCalls': message.successfulToolCalls,
    'error': ?message.errorText,
    if (includeDetails && message.steps.isNotEmpty)
      'steps': [
        for (final step in message.steps)
          {
            'id': step.id,
            'tool': step.toolName,
            'status': step.status.name,
            // 只保存步骤卡实际展示的字段，不复制协议原始参数。
            'arguments': {
              for (final key in const [
                'start',
                'end',
                'range',
                'month',
                'type',
                'keyword',
              ])
                if (step.arguments[key] case final String value) key: value,
              if (step.arguments['limit'] case final num limit
                  when limit.isFinite)
                'limit': limit,
            },
            'summary': step.summary,
            if (step.retryReason case final reason?) 'retryReason': reason.name,
          },
      ],
    if (includeDetails && message.displays.isNotEmpty)
      'displays': message.displays.map(_encodeDisplay).toList(),
  };

  static AiChatMessage _decodeMessage(
    Map<String, Object?> json,
    String bookId,
  ) => AiChatMessage(
    role: AiChatRole.values.byName(json['role'] as String),
    bookId: bookId,
    bookName: json['bookName'] as String,
    baseCurrencyCode: json['currency'] as String,
    moneyCodeDisplay: MoneyCodeDisplay.values.byName(
      json['moneyDisplay'] as String,
    ),
    text: json['text'] as String,
    status: json['status'] == AiChatMessageStatus.error.name
        ? AiChatMessageStatus.error
        : AiChatMessageStatus.done,
    sourceUserInput: json['input'] as String? ?? '',
    successfulToolCalls: json['successfulToolCalls'] as int? ?? 0,
    provenance: AiAnswerProvenance.values.asNameMap()[json['provenance']],
    errorText: json['error'] as String?,
    steps: _list(json['steps'], (step) {
      final fields = _map(step);
      return AiAgentStep(
        id: fields['id'] as String,
        toolName: fields['tool'] as String,
        status: AiAgentStepStatus.values.byName(fields['status'] as String),
        arguments: _map(fields['arguments']),
        summary: fields['summary'] as String,
        retryReason: AiAgentRetryReason.values
            .asNameMap()[fields['retryReason']],
      );
    }),
    displays: _list(
      json['displays'],
      (display) => _decodeDisplay(_map(display)),
    ),
  );

  static Map<String, Object?> _encodeDisplay(AiResultDisplay display) =>
      switch (display) {
        AiStatDisplay(:final title, :final items) => {
          'type': 'stat',
          'title': title,
          'items': [
            for (final item in items) [item.label, item.value, item.emphasize],
          ],
        },
        AiRankingDisplay(:final title, :final rows, :final isExpense) => {
          'type': 'ranking',
          'title': title,
          'isExpense': isExpense,
          'rows': [
            for (final row in rows)
              [row.label, row.amount, row.percent, row.count],
          ],
        },
        AiTrendDisplay(
          :final title,
          :final values,
          :final labels,
          :final isExpense,
        ) =>
          {
            'type': 'trend',
            'title': title,
            'values': values,
            'labels': labels,
            'isExpense': isExpense,
          },
        final AiTransactionsDisplay transactions => _encodeTransactions(
          transactions,
        ),
        AiTableDisplay(:final title, :final headers, :final rows) => {
          'type': 'table',
          'title': title,
          'headers': headers,
          'rows': rows,
        },
      };

  static Map<String, Object?> _encodeTransactions(
    AiTransactionsDisplay display,
  ) {
    final accounts = <String?>{};
    final categories = <String>{};
    final tags = <String>{};
    final categoryById = {
      for (final category in display.categories) category.id: category,
    };
    for (final entry in display.entries) {
      accounts.addAll([entry.accountId, entry.toAccountId]);
      tags.addAll(entry.tagIds);
      var category = categoryById[entry.categoryId];
      while (category != null && categories.add(category.id)) {
        category = categoryById[category.parentId];
      }
    }
    return {
      'type': 'transactions',
      'title': display.title,
      'entries': display.entries.map((entry) => entry.toJson()).toList(),
      'accounts': [
        for (final account in display.accounts)
          if (accounts.contains(account.id))
            {
              'id': account.id,
              'bookId': account.bookId,
              'name': account.name,
              'type': account.type.name,
              'iconCode': account.iconCode,
              'currencyCode': account.currencyCode,
            },
      ],
      'categories': [for (final id in categories) categoryById[id]!.toJson()],
      'tags': [
        for (final tag in display.tags)
          if (tags.contains(tag.id)) tag.toJson(),
      ],
    };
  }

  static AiResultDisplay _decodeDisplay(Map<String, Object?> json) {
    final title = json['title'] as String;
    return switch (json['type']) {
      'stat' => AiStatDisplay(
        title: title,
        items: _list(json['items'], (item) {
          final fields = item as List<Object?>;
          if (fields.length != 3) {
            throw const FormatException('Invalid stat item');
          }
          return AiStatItem(
            label: fields[0] as String,
            value: _double(fields[1]),
            emphasize: fields[2] as bool,
          );
        }),
      ),
      'ranking' => AiRankingDisplay(
        title: title,
        isExpense: json['isExpense'] as bool,
        rows: _list(json['rows'], (row) {
          final fields = row as List<Object?>;
          if (fields.length != 4) {
            throw const FormatException('Invalid ranking row');
          }
          return AiRankingRow(
            label: fields[0] as String,
            amount: _double(fields[1]),
            percent: _double(fields[2]),
            count: fields[3] as int,
          );
        }),
      ),
      'trend' => AiTrendDisplay(
        title: title,
        isExpense: json['isExpense'] as bool,
        values: _list(json['values'], _double),
        labels: _list(json['labels'], _string),
      ),
      'transactions' => AiTransactionsDisplay(
        title: title,
        entries: _list(
          json['entries'],
          (entry) => LedgerEntry.fromJson(_map(entry)),
        ),
        accounts: _list(
          json['accounts'],
          (account) => Account.fromJson(_map(account)),
        ),
        categories: _list(
          json['categories'],
          (category) => Category.fromJson(_map(category)),
        ),
        tags: _list(json['tags'], (tag) => Tag.fromJson(_map(tag))),
      ),
      'table' => AiTableDisplay(
        title: title,
        headers: _list(json['headers'], _string),
        rows: _list(json['rows'], (row) => _list(row, _string)),
      ),
      _ => throw const FormatException('Unknown AI result display'),
    };
  }

  static Map<String, Object?> _map(Object? value) =>
      value as Map<String, Object?>;

  static List<T> _list<T>(Object? value, T Function(Object?) transform) =>
      (value as List<Object?>?)?.map(transform).toList() ?? <T>[];

  static double _double(Object? value) => (value as num).toDouble();

  static String _string(Object? value) => value as String;
}
