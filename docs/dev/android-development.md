# Android 本地开发与真机验收

小禾记账只维护 Android 应用；电脑上的单元/widget/ffi 测试保留。
设计评审直接使用正式 `lib/main.dart`，不复制页面。公共规范由 `AGENTS.md` 和 docs 维护，
`CLAUDE.md` 只链接 AGENTS。

## 环境检测与自动补齐

每次 Android 任务先检查工作树、`flutter --version`、`flutter doctor -v`、
`adb devices -l`、Java 和 `android/local.properties`。Flutter 版本以 `.github/workflows/ci.yml`
的 `flutter-version` 为准，当前 **3.47.2**。不要静默升级到其他 stable 版本。

上述检查已收进 `dart run scripts/doctor.dart`（加 `--devices` 附带 adb 设备列表）：
它会比对 PATH 上的 Flutter 版本与 CI 固定版本、核对 Android SDK 是否真的装了
platforms/build-tools、检查 JDK/adb/gh，并在失败项上给出对应的修复入口。

**工具缺失时先定位并说明官方安装步骤；能复用现有安装就不要改动环境。** 涉及系统级改动
（JDK/SDK/PATH/注册表）或权限、设备授权时先取得用户同意，不能只以“没有 Android 环境”结束。
优先复用现有安装，不覆盖其他项目的 SDK、不改签名，不把管理员机器的固定路径写进已提交配置。
只在下载/权限/设备授权确实阻塞时说明具体原因。

Windows 安装顺序：

1. 用 `Get-Command flutter,java,adb,git,gh`、`JAVA_HOME`、`ANDROID_HOME` 和
   `android/local.properties` 找现有工具，不要假设固定安装路径。
2. 缺 Git/JDK 时优先使用系统包管理器，例如 winget 的 `Git.Git`、
   `EclipseAdoptium.Temurin.17.JDK`。CI 使用 Java 17；本地可用 17 或更高版本，
   但要以 `flutter doctor` 与实际 Gradle 构建为准，不要静默改变 CI 固定版本。
   重新定位可执行文件，不假定新安装立即刷新了当前进程 PATH。
3. 缺匹配 Flutter 时，从 [官方归档](https://docs.flutter.dev/install/archive) 的
   `releases_windows.json` 找 CI 指定版本，下载对应 archive 并核对其 SHA-256，
   解压到独立版本目录。Git clone 对应标签也是官方支持的源码安装方式。
   慢网可用 [官方文档列出的 CFUG 镜像](https://docs.flutter.dev/community/china)，
   在当前终端设置 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。
4. 缺 Android SDK 时，从 [Android 官方工具页](https://developer.android.com/tools)
   下载 Windows Command-line Tools，核对官方校验值，将工具放入
   `<sdk>/cmdline-tools/latest/`；不得从不明镜像下载执行文件。
   安装 platform-tools、与 Flutter/Gradle 配置匹配的 platforms/build-tools；
   NDK 与 CMake 的版本从 Flutter Gradle 插件及构建报错读取，不能把手机 API
   版本直接当作 compileSdk。
5. 为当前终端设置 PATH/JAVA_HOME/ANDROID_HOME，运行 `flutter pub get`、
   `flutter doctor -v` 和 `adb devices -l` 复核。macOS/Linux 同样使用官方 Flutter
   归档、JDK 与对应平台 Command-line Tools，不执行 Windows 安装命令。

**当前构建前置（Flutter 3.47.2）**：Flutter 的 Gradle 插件会强制使用 NDK
`28.2.13676358`，AGP 9 默认使用 CMake `3.22.1`。`cmdline-tools` 23 起
`sdkmanager` 已弃用，Flutter 的自动 NDK 安装可能报
“Android sdkmanager did not install NDK …”；优先用 Android Studio SDK Manager
或 `android sdk install` 安装，并确认以下文件存在：

```text
<android-sdk>/ndk/28.2.13676358/source.properties
<android-sdk>/cmake/3.22.1/bin/cmake.exe
```

新版 cmdline-tools 下 `flutter doctor --android-licenses` 可能提示该选项已不再需要；
`flutter doctor` 的 “Android license status unknown” 不一定代表构建被阻断，以实际
Gradle 构建为准。不要把本机 SDK/JDK 路径写进仓库文档或提交的配置；
`android/local.properties` 由 Flutter 维护且不提交。

复核（新终端）：

```powershell
dart run scripts/doctor.dart --devices
flutter doctor -v
adb devices -l
```

遇到 Java AF_UNIX 临时目录或跨盘 Kotlin 缓存报错时，按需临时叠加（不要写进 CI 或提交的配置）：

```powershell
$javaTmp = Join-Path $env:TEMP 'verifin-java-tmp'
New-Item -ItemType Directory -Force $javaTmp | Out-Null
$env:JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$javaTmp -Djdk.net.unixdomain.tmpdir=$javaTmp -Dorg.gradle.project.kotlin.incremental=false"
```

设置 `JAVA_TOOL_OPTIONS` 后先执行 `android\gradlew.bat --stop`，否则复用的 Gradle daemon
不会带上新参数。若 Gradle 下载 Flutter 引擎产物
（`storage.googleapis.com/download.flutter.io`）时出现 `Remote host terminated the handshake`，
可在当前终端临时设置 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` 后重试，
不要改持久化配置。

仅在复现同类错误时使用上述 Java/Kotlin 绕过，不复制到 CI 全局配置。`local.properties`
由 Flutter 维护且不提交；正式 keystore 永远不替换或输出。

**不要并行执行 `input tap`。** 每次 `input` 都会在设备上启动一个 JVM；并发过高会使模拟器卡死，
表现为冷启动变慢、`NO_INPUT_CHANNEL`、点击无效或 ANR。需要时先 `adb reboot` 恢复。
连点、快速切页等压力验证使用 `flutter test` 的 widget 测试；真机/模拟器只做最终确认。

## 日常真机开发

手机开启 USB 调试并授权电脑；某些 ROM 还需允许 USB 安装。`unauthorized`、锁屏或
`INSTALL_FAILED_USER_RESTRICTED` 时请用户解锁/允许，不能绕过设备安全机制。
出现多个设备时必须显式选择 `-s <serial>` / `-d <device-id>`，不得盲装。

```powershell
flutter run -d <device-id> --flavor diagnostic
```

桌面预览导出脚本会安装 `github` flavor 的 debug 与仪器测试包，应在专用设备或模拟器执行。设备侧测试需要真机或模拟器（`testInstrumentationRunner` 是标准
`androidx.test.runner.AndroidJUnitRunner`）：

```powershell
dart run scripts/widget_previews.dart        # 桌面组件：构建+安装+跑 WidgetGlanceInstrumentationTest，
                                             # 并把选择器预览 PNG 拉回 res/（改组件视觉后必须重跑）
flutter test integration_test/ -d <device-id> --flavor diagnostic
```

`integration_test/` 的用例在真机上**只断言最终态**并打印帧耗时：live binding 的相邻帧间隔
就是设备真实帧间隔，慢设备/模拟器上一帧可能长于进场动画，逐帧动画断言会假失败——
动画连续性由 `test/anchored_menu_test.dart` 用确定性时钟覆盖。仪器测试与帧耗时采样都只做冒烟，
**不能替代**下面的真机评审。

个人版使用 `diagnostic` flavor，applicationId 是 `top.talyra42.verifin.personalledger`。debug 支持 hot reload，与个人版签名 release 使用相同包名。日常调试用专用模拟器或测试设备，使用已安装个人版的手机验收同签名的 release 包。

同一工作区的 `flutter test`、`flutter pub get` 与 Android 构建顺序执行，因为它们会更新插件注册文件和依赖元数据。最终图形、OCR 与原生插件行为须在签名 release APK 上验证。

采集日志先保存历史 crash buffer，再启动目标应用；记录 package、pid、版本、引擎和时间。
按目标 pid 保存本次 logcat，避免把其他应用日志混入结论。日志和截图放在被忽略的
`build/`，不提交账目、凭证或原始敏感内容。图形问题分离绘制路径复现。

需要持续亮屏时，先记录 `adb shell settings get global stay_on_while_plugged_in`，
可临时 `adb shell svc power stayon usb`；任务结束恢复原值，不改变用户永久息屏习惯。
若连接电脑仍自动息屏，先看 `adb shell dumpsys battery`：某些 USB-PD 连接会被识别为 AC 而不是 USB，
此时可在已获准的测试期间临时使用 `svc power stayon true`，结束后仍恢复原值。

## 验收与交付

- 本地构建即发布外观（只有一套排版参数）；widget 测试保留 393×852 和 360dp 布局检查，
  真机按其实际逻辑尺寸截图，不能把桌面测试当作原生验收。
- 材质与导航验收覆盖冷启动、首页／看板／资产／我的切换、两种底栏样式、深浅色和前后台切换。液态玻璃效果仅出现在底栏。
- 代码提交前验证格式、静态分析和现有测试。Android 改动另做真机验收，涉及数据库时检查持久化与迁移。

### 构建并发布个人版

1. 递增 `pubspec.yaml` 的版本名和构建号，同步 `lib/app/app_version.dart`、`CHANGELOG.md` 和 `docs/release-notes/vX.Y.Z.md`。明确获准发布后，将该版本的提交推送到 Bill 的 `main`。
2. 在构建环境设置 `BILL_SIGNING_STORE`、`BILL_STORE_PASSWORD`、`BILL_KEY_ALIAS` 和 `BILL_KEY_PASSWORD`。沿用现有个人版证书，构建面向 arm64 的 APK。

   ```bash
   flutter build apk --release --flavor diagnostic --target-platform android-arm64 --dart-define=UPDATE_CHECK=true
   ```

3. 用 Android SDK 的 `aapt2 dump badging` 检查包名和版本，用 `apksigner verify --print-certs` 核对证书。真机直接覆盖安装，验证账本保留、应用可启动、OCR 和提醒等原生功能可用。
4. 在 [Bill Releases](https://github.com/jiucaihua1/Bill/releases) 创建 `vX.Y.Z` 正式 Release，标签版本与 APK 一致，上传验收过的 APK 并设为 Latest。用仍运行旧版本的手机或测试设备确认「检查更新 → 前往」打开对应 Release。

推送 `main` 会运行代码质量检查和 debug 编译。正式 APK 由维护者签名构建并上传。清理测试安装前，先核对设备、包名和数据归属。
