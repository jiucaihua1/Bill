import 'package:flutter/material.dart';

import '../app/ai/ai_agent_step.dart';
import '../app/ai/ai_tool_presentation.dart';
import '../app/app_theme.dart';
import '../l10n/app_localizations.dart';

/// 一轮有多条工具步骤时，先显示一行摘要，展开后复用原有的步骤卡。
class AiAgentStepsView extends StatefulWidget {
  const AiAgentStepsView({super.key, required this.steps});

  final List<AiAgentStep> steps;

  @override
  State<AiAgentStepsView> createState() => _AiAgentStepsViewState();
}

class _AiAgentStepsViewState extends State<AiAgentStepsView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    if (steps.length == 1) return AiAgentStepView(step: steps.single);

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final active = steps.any(
      (step) =>
          step.status == AiAgentStepStatus.running ||
          step.status == AiAgentStepStatus.retrying,
    );
    final failed = steps.any((step) => step.status == AiAgentStepStatus.failed);
    final color = active
        ? theme.colorScheme.primary
        : failed
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final summary = active
        ? l10n.aiChatStepsRunning(steps.length)
        : l10n.aiChatStepsSummary(steps.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(veriRadiusMd),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Semantics(
              expanded: _expanded,
              child: InkWell(
                borderRadius: BorderRadius.circular(veriRadiusMd),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      if (active)
                        SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        )
                      else
                        Icon(
                          failed
                              ? Icons.error_outline
                              : Icons.list_alt_outlined,
                          size: 17,
                          color: color,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: color,
                          ),
                        ),
                      ),
                      if (!active && failed)
                        Text(
                          l10n.aiStepFailed,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                          ),
                        ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 17,
                        color: color,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_expanded)
          for (final step in steps)
            AiAgentStepView(key: ValueKey<String>(step.id), step: step),
      ],
    );
  }
}

/// 聊天消息中的 Agent 操作步骤。完成步骤默认折叠，点按可查看查询范围与结果摘要。
class AiAgentStepView extends StatefulWidget {
  const AiAgentStepView({super.key, required this.step});

  final AiAgentStep step;

  @override
  State<AiAgentStepView> createState() => _AiAgentStepViewState();
}

class _AiAgentStepViewState extends State<AiAgentStepView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final step = widget.step;
    final presentation = presentAiAgentStep(l10n, step);
    final resultSummary = step.toolName == 'agentRetry' ? '' : step.summary;
    final isRunning =
        step.status == AiAgentStepStatus.running ||
        step.status == AiAgentStepStatus.retrying;
    final isFailed = step.status == AiAgentStepStatus.failed;
    final color = isFailed
        ? theme.colorScheme.error
        : isRunning
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final status = switch (step.status) {
      AiAgentStepStatus.running => l10n.aiStepRunning,
      AiAgentStepStatus.succeeded => l10n.aiStepSucceeded,
      AiAgentStepStatus.failed => l10n.aiStepFailed,
      AiAgentStepStatus.retrying => l10n.aiStepRetrying,
    };
    final hasDetail =
        presentation.detail.isNotEmpty || resultSummary.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(veriRadiusMd),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(veriRadiusMd),
          onTap: hasDetail && !isRunning
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (isRunning)
                      SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    else
                      Icon(
                        isFailed
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        size: 17,
                        color: color,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        presentation.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      status,
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                    if (hasDetail && !isRunning) ...<Widget>[
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 17,
                        color: color,
                      ),
                    ],
                  ],
                ),
                if (isRunning && presentation.detail.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 5),
                  Text(
                    presentation.detail,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ],
                if (_expanded && hasDetail) ...<Widget>[
                  const SizedBox(height: 6),
                  if (presentation.detail.isNotEmpty)
                    Text(
                      presentation.detail,
                      style: theme.textTheme.bodySmall?.copyWith(color: color),
                    ),
                  if (resultSummary.isNotEmpty)
                    Text(
                      resultSummary,
                      style: theme.textTheme.bodySmall?.copyWith(color: color),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
