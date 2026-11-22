# Bill 仓库约定

项目级工程规则见 [AGENTS.md](../AGENTS.md)。

## 分支与合并

- 推送前核对目标仓库为 `jiucaihua1/Bill`。维护者可以在分支规则允许时快进推送 `main`，也可以通过 PR 合并。
- 保留主分支历史。出现回归时，通过 `git revert` 生成修复提交。
- 依赖更新核对变更范围以及 CI 结果。涉及 Android 构建、签名或数据迁移时，按对应文档验证。

## 文档分层

| 位置 | 内容 |
| --- | --- |
| [README](../README.md) | 用户入口、项目署名与安装更新 |
| [docs](../docs) | 当前产品、设计、开发和验收说明 |
| [决策记录](notes/README.md) | 已讨论方案的背景与历史 |
| [Android 开发](../docs/dev/android-development.md) | 本地工具链、真机验收与发版 |

推送、合并远端 PR、打标签及发布 Release 需要用户明确授权。改动完成后说明实际验证结果与未验证项。
