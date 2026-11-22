import 'package:flutter/material.dart';

import '../app/common_widgets.dart';
import '../app/credits.dart';
import '../app/credits_avatar.dart';
import '../l10n/app_localizations.dart';

/// 展示原项目署名和随包发布的支持者名单。
class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key, this.supporters = creditsSupporters});

  /// 名单；默认取包内常量。测试或画廊可传子集。
  final List<CreditsSupporter> supporters;

  /// 头像墙列数：与「我的」宫格一致的四列，393dp 下每格约 77dp。
  static const int _columns = 4;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: VeriPage(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
            children: <Widget>[
              VeriHeader(title: l10n.creditsTitle, showBack: true),
              const SizedBox(height: 10),
              VeriCard(
                child: Text(
                  l10n.creditsIntro,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.82),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final group in creditsGroups(supporters: supporters)) ...[
                // 组标题为空表示默认组；有分组时（如「特别鸣谢」）才渲染标题，
                // 所以空分组不会在界面上留下孤零零的一行标题。
                if (group.title != null) ...[
                  SectionTitle(title: group.title!),
                  const SizedBox(height: 8),
                ],
                VeriCard(
                  child: _SupporterWall(
                    supporters: group.members,
                    columns: _columns,
                    gap: _gap,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 头像墙：固定列数的等宽网格 + 头像下方的常显称呼。
///
/// 用 `Wrap` 而不是 `GridView`：这里只需要「按行排布的固定宽度块」，`Wrap` 没有
/// 自己的滚动与 padding 语义，不会和页面 `ListView` 的滚动/内边距互相干扰。
class _SupporterWall extends StatelessWidget {
  const _SupporterWall({
    required this.supporters,
    required this.columns,
    required this.gap,
  });

  final List<CreditsSupporter> supporters;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap + 4,
          children: <Widget>[
            for (final supporter in supporters)
              SizedBox(
                width: itemWidth,
                child: _SupporterTile(supporter: supporter),
              ),
          ],
        );
      },
    );
  }
}

class _SupporterTile extends StatelessWidget {
  const _SupporterTile({required this.supporter});

  final CreditsSupporter supporter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handle = supporter.handle;
    // 合并成一条语义：读屏按「称呼 + 附注」念一次，不会把头像和文字拆成两个节点。
    return MergeSemantics(
      child: Column(
        children: <Widget>[
          CreditsAvatar(
            seed: supporter.avatarSeed,
            imageAsset: supporter.avatarAsset,
          ),
          const SizedBox(height: 6),
          Text(
            supporter.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (handle != null)
            Text(
              handle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }
}
