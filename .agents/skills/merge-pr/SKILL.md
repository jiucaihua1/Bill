---
name: merge-pr
description: Use when the maintainer authorizes merging a pull request into Bill.
---

# 合并 Bill 的 PR

先确认 PR 属于 `jiucaihua1/Bill`，目标是 `main`。阅读改动、核对 CI，解决冲突并验证受影响功能后，按仓库当前允许的合并方式处理。

```bash
gh pr view <n> --repo jiucaihua1/Bill
gh pr diff <n> --repo jiucaihua1/Bill
gh pr checks <n> --repo jiucaihua1/Bill --watch
```

用户授权合并后执行，并回读目标提交和 CI 状态。出现回归时，从 Bill 的 `main` 创建修复分支，用 `git revert` 生成回滚提交。
