# 小禾记账（Bill）

小禾记账是一款本地优先的 Android 记账应用。无需注册，账本保存在手机上，可随时导出或备份到自己配置的 WebDAV。截图先在手机上识别文字，使用 AI 时由你指定服务。

[下载 APK](https://github.com/jiucaihua1/Bill/releases/latest) · [问题反馈](https://github.com/jiucaihua1/Bill/issues) · [产品文档](docs/product/product.md)

下文介绍仓库中的功能。已发布安装包的变化见各版本的发布说明。

## 使用方式

| 入口 | 可以做什么 |
| --- | --- |
| 首页 | 记一笔，看今天和往前六天的收支、近期交易与预算进度 |
| 看板 | 按自然周、月、年查看收支、分类和标签排行。进入分类明细后可自选起止日期 |
| 资产 | 管理账户、信用账户与净资产，可使用多币种账户和离线汇率 |
| 我的 | 管理账本、分类和桌面小组件，分析订阅支出，导入、导出和恢复备份 |

- **订阅支出**根据备注识别会员或订阅，也可从已有支出手动选入。周期按月数设置，例如季付填 3。点「今日日均花费」可查看当天仍在分摊的项目。
- **截图记账**可从相册选图或通过系统分享送入。应用根据付款方式匹配账本中的账户，生成草稿后由你确认。
- **数据管理**支持本地与加密备份、账单导入、CSV 导出和重复导入检查。用坚果云时，点「使用坚果云」，填注册邮箱和第三方应用密码。连接测试会尝试创建缺失的备份目录。

[查看产品功能与统计口径](docs/product/product.md) · [查看截图示例](docs/screenshots/README.md)

## 安装与更新

1. 从 [Bill Releases](https://github.com/jiucaihua1/Bill/releases/latest) 下载 `.apk` 附件。当前发布渠道为 GitHub，安装包面向 arm64 Android 设备。
2. 已安装的用户可以在「我的 → 设置 → 更多 → 检查更新」找到新版。点「前往」打开浏览器，到对应 Release 下载 APK。
3. 更新前可在「我的 → 数据管理」导出备份。安装时直接覆盖现有应用，保留应用数据。

## 开发与发布

本项目使用 Flutter 3.47.2、JDK 17 和 Android SDK，CI 验证格式、静态分析、测试和 Android 调试构建。

```bash
flutter pub get
flutter analyze
flutter test
```

本地调试和正式签名 APK 使用相同的个人版包名。请用专门的模拟器或测试设备运行调试构建。正式发布需要同签名的 APK、递增的版本号和 Bill 仓库的正式 Release。完整命令和核对步骤见 [Android 开发与发版](docs/dev/android-development.md)。

| 文档 | 内容 |
| --- | --- |
| [架构导览](docs/dev/architecture.md) | 应用分层、数据和源码入口 |
| [验收清单](docs/product/acceptance-checklist.md) | 记账、备份、分析与 Android 验收 |
| [设计规范](docs/design/design-system.md) | 页面布局、材质与导航 |
| [组件注册表](docs/design/components.md) | 可复用组件和计算逻辑 |
| [贡献指南](CONTRIBUTING.md) | Bug、功能反馈与仓库维护 |

## 项目来源与许可证

本项目基于 [LumiDesk/verifin](https://github.com/LumiDesk/verifin) 二次开发。感谢原作者和贡献者。

源码按 [GPL-3.0-or-later](LICENSE) 分发。第三方组件保留各自的许可证与署名。
