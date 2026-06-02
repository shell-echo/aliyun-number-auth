## 0.1.0

### 新增功能

**API 扩展**
* `getMobileToken` 支持内联回调参数：`onPrivacyLinkTap`、`onSuspendedDismiss`、`onLoginButtonTap`，回调在调用结束后自动注销，无需手动管理生命周期
* 新增 `onLoginButtonTap(bool isChecked)` — 每次用户点击登录按钮时触发，`isChecked` 为 `false` 时可配合 `animateCheckbox()` / `animatePrivacyText()` 引导用户
* 新增 `onCheckboxToggle(bool isChecked)` — 用户切换协议 checkbox 时触发，参数为切换之后的新状态；适合做埋点或更新授权页外部 UI（SDK 自身的登录按钮无法在 Flutter 侧动态禁用/改色）
* 新增 `onAuthPageShown()` — 授权页成功显示后触发一次，可用于关闭入口按钮 loading 或做埋点
* 新增 `setCheckboxChecked(bool)` — 运行时修改隐私复选框勾选状态
* 新增 `isCheckboxChecked()` — 查询当前复选框勾选状态
* 新增 `hideLoginLoading()` — 手动隐藏登录 loading（配合 `autoHideLoginLoading: false` 使用）
* 新增 `animatePrivacyText()` — 触发隐私文本动画，引导用户阅读协议
* 新增 `animateCheckbox()` — 触发复选框动画，引导用户勾选协议
* 新增 `closePrivacyAlertDialog()` — 关闭二次隐私确认弹窗
* 新增 **`AliyunAuthController`**（`ChangeNotifier`）：暴露 `status` (`AliyunAuthStatus` 枚举) / `canLogin` / `lastError`，提供 `checkEnv()` / `login(...)` / `dismissLoginPage()` / `dispose()` 方法。可与 `ListenableBuilder` / `Provider` / `Riverpod` 等标准状态管理方案集成
* `AliyunAuthWidget` 重构为 `AliyunAuthController` 的轻量便利封装：支持外部传入 `controller`，builder 参数从 `bool available` 升级为 `AliyunAuthStatus status`（细分 5 个状态）
* `AliyunAuthWidget` 新增 `onLoginButtonTap` 参数
* `AliyunAuthController.login` / `AliyunAuthWidget` 新增 `autoDismissOnSuccess` 参数:配合 `uiConfig.suspendDisMissVC: true` 使用,登录成功后等 iOS 授权页 dismiss 动画跑完再 resolve Future / 触发 `onSuccess`,避免 `onSuccess` 里立即 `Navigator.push` 跟正在消失的授权页视觉重叠。`suspendDisMissVC: false` 时该参数被忽略(SDK 自身会关闭授权页)
* `AliyunNumberAuth.dismissLoginPage` / `AliyunAuthController.dismissLoginPage` 新增 `waitForCompletion` 参数(iOS only):`true` 时 Future 等到 SDK 的 dismiss 动画完成才 resolve(带 1s 安全超时);默认 `false` 保持 Round 6 的 eager-return 兼容性(SDK completion 是 `_Nullable`,无授权页时不一定触发,等待可能挂起)

**`AliyunAuthUIConfig` 扩展**
* 新增 `AliyunAuthPresentDirection` 枚举（`bottom`/`right`/`top`/`left`），控制全屏模式进入方向（iOS）
* 新增状态栏、导航栏完整配置（`statusBarHidden`、`navColor`、`navTitle` 等）
* 新增 Slogan / 手机号码颜色字号配置
* 新增登录按钮文字颜色、字号配置
* 新增切换按钮颜色配置
* 新增复选框更多选项：`checkBoxHidden`、`expandCheckboxTapScope`、`checkBoxInnerPadding`、`checkBoxVerticalCenter`
* 新增协议每条独立颜色覆盖：`privacyOperatorColor`、`privacyOneColor`、`privacyTwoColor`、`privacyThreeColor`
* 新增 `privacyOperatorUnderline`、`privacyConectTexts` 协议连接词配置
* 新增弹窗标题栏选项（iOS）：`alertBarVisible`、`alertTitle`、`alertTitleBarColor`、`alertTitleColor`、`alertCloseButtonHidden`、`alertAvoidsKeyboard`
* 新增全屏背景图：`backgroundImageData`
* 新增 `autoHideLoginLoading`、`showLoginLoading`
* `logoImageData` 类型从 `List<int>?` 修正为 `Uint8List?`（修复 logo 无法显示的 bug）
* `AliyunAuthUIConfig.copyWith()` 支持所有字段
* `AliyunAuthCode` 新增 `loginButtonTapped`、`pageDealloced`、`preloadInAuthPage` 常量

**Android 实现大幅补全**
* `buildAndSetAuthUIConfig` 新增对状态栏、导航栏、Logo、Slogan、手机号码、登录按钮（文字颜色/字号）、切换按钮颜色、复选框（隐藏/尺寸/自定义图像）、隐私文字（行间距/对齐/颜色/字号）、协议 WebView 导航栏样式、背景色/背景图等配置的完整实现
* 复选框图像（已选/未选）现由插件侧动态生成，与 iOS 视觉保持一致
* `setCheckboxChecked` / `isCheckboxChecked` 现调用 SDK 真实接口（`setProtocolChecked` / `queryCheckBoxIsChecked`）

### Bug 修复

* **Android 编译错误**：`pendingResult` 属性被引用但未声明；`buildAndSetAuthUIConfig` 缺少闭合 `}`（代码无法编译）
* **iOS 编译错误**：`dismissLoginPage` 调用了 ObjC 旧名 `cancelLoginVCAnimated(_:)`，新版 Swift 强制走 ObjC → Swift 自动重命名规则，已改为 `cancelLoginVC(animated:)`
* **Logo 无法显示**：`logoImageData` 类型错误导致 iOS 端收到 `NSArray` 而非 `FlutterStandardTypedData`
* **登录按钮圆角失效**：iOS 生成背景图时宽度为 1pt，退化路径导致圆角不渲染，已修正为使用足够宽度
* **Android 竞态窗口**：`onDetachedFromActivity` 使用 `mainHandler.post` 存在 tokenListener 回调抢先执行导致 `result` 被调用两次的风险，改为直接调用消除竞态
* **iOS init 重入**：`init` 被重复调用时未保护，现通过 `pendingInitResult` 防止并发
* **iOS 协议链接事件 name 始终为空**：iOS SDK 的 `resultDic` 用 key `"urlName"`（与官方 `PNSStyleSelectController` demo 对照确认），原代码读 `"name"` → `onPrivacyLinkTap` 在 iOS 上拿到的 `name` 永远是空串
* **iOS `init` 可能永久挂起**：`setAuthSDKInfo` callback 在 SDK 内部异常时可能不触发，导致 `pendingInitResult` 永不释放、之后所有 init 抛 `BUSY`。已加 15s 看门狗 + `initSeq` 计数器,避免误杀新 init
* **iOS `dismissLoginPage` 可能永久挂起**：`cancelLoginVCAnimated:complete:` 的 `complete` 是 `_Nullable`，授权页未显示时 SDK 不会触发 completion；改为先 `result(nil)` 同步返回再 fire-and-forget 调用，跟 Android `quitLoginPage` 行为对齐
* **iOS engine detach 时授权页留在屏幕上**：`detachFromEngine` 检测到登录中状态时主动 `cancelLoginVC`
* **iOS `topViewController` 无法穿透 Nav/Tab**：原实现只跟 `presentedViewController`，授权页可能 anchor 到错误的 VC；新增 `topMost(from:)` 递归解 `UINavigationController` / `UITabBarController`
* **Android 双调 `Result` 风险**：`tokenListener` 回调使用 `mainHandler.post` 派发,在 detach + reattach + 新调用三连之间到达的 runnable 可能用旧响应解决新 Future,或对已被 detach 处理的 `Result` 二次调用导致 `IllegalStateException`。改为 SDK 线程 snapshot pending 引用 + main 线程 identity-check 后再解决
* **Android `init`/`preload` 可能挂起**：`helper` 是 `by lazy`,首次访问 `PhoneNumberAuthHelper.getInstance` 若失败（资源丢失、proguard 配置错等）抛异常,而 `result.success/error` 都未触发,Dart Future 永不 resolve。已用 try-catch 包裹
* **Android `checkEnvAvailable` false-positive**：原 `tokenListener.onTokenSuccess` 的 check 分支无条件返回 `true`,未校验 `TokenRet.code == CODE_SUCCESS`,可能把中间事件误判为"环境可用"
* **Android engine detach 时单例泄漏 + 授权页留屏**：`PhoneNumberAuthHelper` 是进程级单例,持有的 `tokenListener` / `UIClickListener` 会传递性 pin 住 activity / channel / plugin 实例。`onDetachedFromEngine` 增加 `setUIClickListener(null)` + `setAuthListener(null)`,并在登录中时 `quitLoginPage()` 关闭授权页
* **Android `getMobileToken` 之间 view config 累积**：每次进 `getMobileToken` 前调一组 `removeAuthRegisterXmlConfig` / `removeAuthRegisterViewConfig` / `removePrivacyAuthRegisterViewConfig` / `removePrivacyRegisterXmlConfig`,避免宿主应用通过 `PhoneNumberAuthHelper` 单例注册的自定义 View 在多次调用间累积
* **Android 运行时方法缺 `requireInit` 守卫**：`setCheckboxChecked` / `isCheckboxChecked` / `animatePrivacyText` / `animateCheckbox` / `closePrivacyAlertDialog` / `hideLoginLoading` 之前未 init 时静默 no-op,跟 iOS 抛 `NOT_INITIALIZED` 行为不一致。统一为抛错
* **Dart `getMobileToken` 异常时 `_mobileTokenInFlight` 可能永久卡 true**：原 setter 注册在 try 外,任一 setter 抛错就泄漏。已移入 try 块
* **`AliyunAuthController.dispose` 在 busy 时不关闭授权页**：登录中 dispose 会让用户卡在一个 callback 已被销毁的授权页上,token 拿不回。dispose 检测 busy 时 fire-and-forget `dismissLoginPage()`
* **双端复选框 border 不一致**：iOS 用硬编码 1pt,Android 用 `size * 0.06` 比例。统一为 `size * 0.06`
* **iOS `RunnerTests.swift` 是 Flutter 模板留下的死代码**：调不存在的 `getPlatformVersion` 并强转 `result as! String`,任何在 Xcode 跑 RunnerTests scheme 都会 crash。替换为 3 个 self-contained 测试（unknown method → `notImplemented`、未 init → `NOT_INITIALIZED`、空 SK → `INVALID_ARGS`）

### 集成 / 构建

* **Android 声明 `androidx.appcompat:appcompat:1.7.0` 依赖**：Aliyun SDK 的 `LoginAuthActivity` / `PrivacyDialogActivity` / `AuthWebVeiwActivity` 都 `extends AppCompatActivity`,但我们用 `fileTree(libs/*.aar)` 引入 AAR → AAR 的 POM 依赖不会被 gradle 解析。宿主 App 没有 appcompat 时,`getMobileToken` 一调就 `ClassNotFoundException` 崩溃。声明依赖后由 gradle 解析传递给宿主
* **iOS 系统框架自动链接已验证**：检查 ATAuthSDK / YTXOperators / YTXMonitor 的 `LC_LINKER_OPTION` load command,发现已声明 19 个系统框架（`CoreTelephony` / `SystemConfiguration` / `Security` / `CFNetwork` / `Network` 等),`ld64` 自动处理。Package.swift 只需保留 `-ObjC` 不再需要额外 `linkerSettings`
* `script/import-sdk.sh`:
  * 升级 SDK 时先 `rm -f android/libs/*.aar` 防止旧版 AAR 残留导致重复类编译失败
  * 升级 SDK 时先 `rm -rf Frameworks/*.xcframework` 防止 `cp -r` 的 merge 行为留下旧版独有的资源（如旧版 icon 仍打进 app bundle）
  * 方法签名校验从最初的 9 个扩展到 44 个（Android 29 + iOS 15）,任何 SDK 版本升级带来的方法重命名/删除都会在 import 阶段就失败,而不是到运行时才崩
* `example/pubspec.yaml` Dart SDK 下限从 `^3.12.0` 拉齐插件的 `^3.7.0`,否则用 Flutter 3.28-3.31 的用户能装插件但跑不了 demo,demo 形同虚设
* `pubspec.yaml` 补 `homepage` / `repository` / `issue_tracker`

### 稳健性 / 质量

* `AliyunAuthUIConfig` 实现 `==` 与 `hashCode`(全部 77 个字段,Python 脚本程序化校验覆盖率;`Uint8List` 按字节比较;hashCode 中 byte-array 只取长度避免 1MB 图片 hash 每帧卡顿)
* `AliyunAuthUIConfig.copyWith` 改用私有 sentinel 模式,**支持把 nullable 字段重置回 `null`**(原模式 `field ?? this.field` 无法清空)
* `AliyunAuthUIConfig.toMap` 加 `numberFontSize >= 16` debug assert,捕获 iOS SDK 静默忽略 < 16 的字号
* Android `pendingCheckResult` / `pendingResult` / `pendingLoginResult` 加 `@Volatile`,把 SDK 后台线程读 + main 线程写的跨线程可见性从隐式变显式
* `AliyunNumberAuth._mobileTokenInFlight` 跨 engine 注释说明（与原生 SDK 进程单例语义一致）
* `AliyunAuthUIConfig.suspendDisMissVC` docstring 详细说明 Android `userControlAuthPageCancel()` 一次性开启不可逆的限制及 workaround
* 测试:50 个 Dart 单元测试 + 2 个 example widget 测试 + 3 个 iOS XCTest + 1 个 Android JUnit,新增 5 个回归测试覆盖 `==` / `copyWith` reset / `numberFontSize` assert / Uint8List byte 比较

### 破坏性变更

* **`AliyunAuthWidget` builder 签名变更**：第二个参数从 `bool available` 改为 `AliyunAuthStatus status`（5 个状态：`uninitialized` / `checking` / `available` / `unavailable` / `busy`），原先无法区分"检测中"与"不可用"的问题修复。迁移示例见 [README](README.md#aliyunauthwidget)
* 新增 **`AliyunAuthController`**（`ChangeNotifier`）作为推荐 API，可在 builder 之外触发登录、跨表面共享状态、与 `ListenableBuilder`/`Provider` 等集成。Widget 现为其轻量便利封装
* `AliyunNumberAuth.setPrivacyLinkCallback` / `setSuspendedDismissCallback` 已从公开 API 移除，改为 `getMobileToken` 的内联参数
* `setCheckboxIsChecked({required bool checked})` 重命名为 `setCheckboxChecked(bool)`
* `queryCheckBoxIsChecked()` 重命名为 `isCheckboxChecked()`
* `AliyunAuthUIConfig` 新增必选校验：`privacyConectTexts` 必须恰好包含 3 个元素（SDK 要求）
* 最低 Flutter 版本要求从 `>=3.3.0` 提升至 `>=3.28.0`（`Color.toARGB32()` 与 Dart 3.7 的 unbound `_` wildcard 需要）
* `getSDKVersion()` 在原生 SDK 调用失败时改为抛出 `AliyunNumberAuthException`（原行为：吞错并返回空字符串）；正常情况下仍返回 SDK 真实版本号

---

## 0.0.1

* 本机号码校验流程：`init` / `checkEnvAvailable` / `preload` / `getVerifyToken`
* 一键登录流程：`checkEnvAvailable` / `preloadLogin` / `getMobileToken`
* `AliyunAuthType` 枚举区分两种认证类型（`verifyToken` / `loginToken`）
* Android SDK v2.14.23，iOS SDK v2.14.18
