# Aliyun Number Auth

阿里云号码认证 Flutter 插件，支持**本机号码校验**和**一键登录**两种流程。

> 🤖 本仓库在 [Claude Opus 4.7](https://www.anthropic.com/claude) 协助下完成开发与代码审查。

SDK 版本
- **Android** — v2.14.24
- **iOS** — v2.14.19（官方动态库，附带设备端 dSYM）

---

## 安装

```yaml
dependencies:
  aliyun_number_auth:
    git:
      url: https://github.com/shell-echo/aliyun-number-auth.git
      ref: main
```

```bash
flutter pub get
```

生产项目建议将 `ref` 固定为审核过的完整提交 SHA，并提交宿主的 `pubspec.lock`。本地联调时可改用 `path: ../aliyun-number-auth`，两种来源择一。

### 接入准备

先按阿里云[客户端准备工作](https://help.aliyun.com/zh/pnvs/developer-reference/the-preparatory-work-2/)及[认证方案管理](https://help.aliyun.com/zh/pnvs/user-guide/number-certification-program-management/)开通服务、创建对应平台的号码认证方案。iOS 方案的 BundleID 要与实际 App 一致；Android 方案绑定实际 applicationId 和签名。`init` 接收各平台的 **SDK 方案密钥**，服务端的 AccessKey 不传给客户端。不同 Bundle ID 的开发/生产 App 应使用各自匹配的方案。

客户端取得 token 后交给自有服务端完成认证或换取手机号；一键登录 token 与本机号码校验 token 分别走对应服务端接口。初始化失败、环境不支持或运营商取号失败时，宿主提供其他登录方式。

### iOS / Xcode 配置

本插件使用 **Swift Package Manager（SPM）**，Flutter/Dart 最低版本以 [pubspec.yaml](pubspec.yaml) 为准；本次验证环境为 Flutter 3.47.8、Xcode 27.1。Flutter 3.44 起默认启用 SPM。为让团队和 CI 配置一致，可在**宿主应用**的 `pubspec.yaml` 中明确启用：

```yaml
flutter:
  config:
    enable-swift-package-manager: true
```

旧版 Flutter 或曾关闭 SPM 的环境可执行 `flutter config --enable-swift-package-manager`。然后在宿主根目录执行：

```bash
flutter pub get
flutter build ios --config-only
open ios/Runner.xcworkspace
```

在 Xcode 中完成以下配置：

| 位置 | 操作 |
|---|---|
| Runner → Signing & Capabilities | 使用宿主自己的 Team、签名与 Bundle Identifier；Bundle ID 与阿里云 iOS 方案一致 |
| Runner → General → Minimum Deployments | 不低于当前 Flutter 和插件要求中的较高值；插件声明 iOS 13，本次示例使用 iOS 15 |
| Flutter 自动生成的 SPM 集成 | 确认 `FlutterGeneratedPluginSwiftPackage` 已加入 Runner，Scheme 有 `Run Prepare Flutter Framework Script`；自动生成失败时按 [Flutter 官方集成说明](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)修复 |
| Runner → Build Phases | 按下方说明添加一次资源复制脚本，确保 SDK 默认图片能从 App 主 bundle 加载 |
| Runner → Build Settings → User Script Sandboxing | 各构建配置使用 `No`（`ENABLE_USER_SCRIPT_SANDBOXING = NO`），与当前 Flutter 示例一致 |

**资源复制是必须的一步。** [阿里云 iOS 接入文档](https://help.aliyun.com/zh/pnvs/developer-reference/the-ios-client-access)要求将 `ATAuthSDK.bundle` 放入宿主资源。SPM 自动嵌入动态 framework，但 SDK 默认图标通过 `NSBundle.mainBundle` 查找，单独保留 framework 内的 bundle 不够。

在 Runner → Build Phases → **+ → New Run Script Phase** 中添加 `Copy Aliyun Auth Resources`，放在 Flutter 的 `Thin Binary` 后，所有构建配置都执行（不勾选仅在安装时运行）。脚本如下；example 工程已配置，可直接对照：

```sh
set -eu
source="${BUILT_PRODUCTS_DIR:?}/ATAuthSDK_D.framework/ATAuthSDK.bundle"
destination="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/ATAuthSDK.bundle"
if [ ! -d "$source" ]; then
  echo "error: ATAuthSDK.bundle missing: $source" >&2
  exit 1
fi
/bin/mkdir -p "$destination"
/usr/bin/rsync -a --delete "$source/" "$destination/"
```

在该 Run Script 中填写以下路径，让 Xcode 正确安排构建依赖；使用基于依赖分析的执行即可：

- **Input Files:** `$(BUILT_PRODUCTS_DIR)/ATAuthSDK_D.framework/ATAuthSDK.bundle`
- **Output Files:** `$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/ATAuthSDK.bundle`

此脚本依赖上表的 `User Script Sandboxing = No`。本次 Xcode 验证中，仅声明 bundle 目录仍会在沙箱开启时拒绝读取其中的文件；当前 Flutter 构建脚本的沙箱支持也有[官方跟踪问题](https://github.com/flutter/flutter/issues/181821)。

路径来自构建产物，不引用个人机器的 Pub cache。脚本同步删除已被新版 SDK 移除的旧图标。最终 `.app` 顶层应出现 `ATAuthSDK.bundle`；缺失时脚本报错并阻止构建。

`Package.swift` 已声明 `ATAuthSDK_D.xcframework`，Flutter/SPM 自动链接、嵌入、按宿主设置签名，并在归档收集配套 dSYM。宿主无需再次拖入 framework、添加 `-ObjC` / `YTXOperators` 链接标志，或手工把 dSYM 放入 Copy Bundle Resources。原来手动接入过阿里云 SDK 的项目应移除旧 SDK 的重复引用；其他插件仍使用 CocoaPods 时保留它们所需的配置。

### Flutter 调用

先完成 Flutter binding 初始化，并在宿主适当的初始化时机调用一次 `await AliyunNumberAuth.init(androidSk, iosSk)`，等待成功后再创建自动检查环境的 `AliyunAuthController` / `AliyunAuthWidget`。SDK 密钥可由宿主配置或服务端提供；不在 Xcode 中配置密钥，也不修改插件源码填入密钥。模拟器可运行不依赖运营商的测试，真实号码认证使用有效方案密钥和开启蜂窝数据的真机验证。

```dart
WidgetsFlutterBinding.ensureInitialized();
await AliyunNumberAuth.init(androidSk, iosSk);
```

插件的 Dart 并发锁只在当前 isolate 内生效。阿里云原生 SDK 是进程级单例，多 Engine 应由宿主统一路由至一个 Engine 使用，不支持并发访问。环境检测在原生 15 秒无响应后释放请求，Dart 返回不可用；本机号码校验在传入 timeout 后增加 1 秒兜底。授权页等待用户阅读、点击的时间没有总超时。

---

## 快速开始

```dart
import 'package:aliyun_number_auth/aliyun_number_auth.dart';

// 1. App 启动时初始化（只调一次）
await AliyunNumberAuth.init('YOUR_ANDROID_SK', 'YOUR_IOS_SK');

// 2. 在登录页放 Widget
AliyunAuthWidget(
  uiConfig: AliyunAuthUIConfig(
    loginBtnText: '本机号码一键登录',
    loginBtnBgColor: Color(0xFF0066FF),
    privacyOne: ['用户协议', 'https://your.app/terms'],
    privacyTwo: ['隐私政策', 'https://your.app/privacy'],
  ),
  builder: (context, status, login) {
    return ElevatedButton(
      onPressed: login,
      child: Text(status == AliyunAuthStatus.available ? '一键登录' : '短信登录'),
    );
  },
  onSuccess: (token) => myBackend.loginWithToken(token),
  onError: (e) {
    if (e.code == AliyunAuthCode.userCancelled) return;
    showError(e.message);
  },
)
```

---

## API 文档

### AliyunNumberAuth

所有方法均为静态方法。

---

#### `init(androidSk, iosSk)`

初始化 SDK。**必须在所有其他方法之前调用**，App 生命周期内只调一次。

```dart
await AliyunNumberAuth.init('YOUR_ANDROID_SK', 'YOUR_IOS_SK');
```

| 参数 | 类型 | 说明 |
|---|---|---|
| `androidSk` | `String` | Android 平台密钥 |
| `iosSk` | `String` | iOS 平台密钥 |

抛出 `AliyunNumberAuthException`（`code` 见 [错误码](#aliyunauthcode)）。

> **平台行为差异**
>
> - **iOS**：`init` 是异步的，SDK 会发起一次网络握手来验证 SK。若 SK 无效，`init` 本身即抛出 `AliyunNumberAuthException`（`code: 600017`）。
> - **Android**：`init` 立即返回成功；SK 的合法性是懒验证的，错误会推迟到首次调用 `getVerifyToken` 或 `getMobileToken` 时才暴露（同样以 `600017` 形式出现）。
>
> 建议在 `init` 调用失败时统一降级到其他登录方式，不要依赖平台差异来区分处理。

---

#### `checkEnvAvailable({type})`

检查当前设备/网络是否支持指定认证类型。

```dart
// 检查一键登录（默认）
final canLogin = await AliyunNumberAuth.checkEnvAvailable();

// 检查本机号码校验
final canVerify = await AliyunNumberAuth.checkEnvAvailable(
  type: AliyunAuthType.verifyToken,
);
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `type` | `AliyunAuthType` | `loginToken` | `loginToken` 一键登录 / `verifyToken` 号码校验 |

返回 `bool`。持有**独占锁**，不可与自身或其他取号方法并发调用。

返回 `false` 的场景：无 SIM 卡、蜂窝未开启、运营商不支持、海外号码。

---

#### `preload({timeout})`

预热**本机号码校验**流程，让后续 `getVerifyToken` 响应更快。Fire-and-forget，无需 await。

```dart
if (canVerify) AliyunNumberAuth.preload();
```

---

#### `preloadLogin({timeout})`

预热**一键登录**授权页，让后续 `getMobileToken` 弹出更快。Fire-and-forget，无需 await。

```dart
if (canLogin) AliyunNumberAuth.preloadLogin();
```

---

#### `getVerifyToken({timeout})`

**本机号码校验**流程，完全静默，不显示任何 UI。

返回一个 token，后端携带此 token 调用阿里云接口，**验证某个手机号是否与当前设备一致**（不能直接获取手机号）。

```dart
try {
  final token = await AliyunNumberAuth.getVerifyToken();
  // 发给后端：POST /api/verify-phone { token, phone }
} on AliyunNumberAuthException catch (e) {
  print('${e.code}: ${e.message}');
}
```

---

#### `getMobileToken({timeout, uiConfig, onPrivacyLinkTap, onSuspendedDismiss, onLoginButtonTap, onCheckboxToggle, onAuthPageShown})`

**一键登录**流程。弹出 SDK 授权页（底部弹出或全屏），用户点击确认后返回 token，后端携带此 token 调用阿里云接口**直接获取手机号**。

```dart
try {
  final token = await AliyunNumberAuth.getMobileToken(
    timeout: Duration(seconds: 15),
    uiConfig: AliyunAuthUIConfig(loginBtnBgColor: Color(0xFF0066FF)),
    onLoginButtonTap: (isChecked) {
      // 用户点了登录按钮，但没勾协议 → 抖动提示
      if (!isChecked) {
        AliyunNumberAuth.animateCheckbox();
        AliyunNumberAuth.animatePrivacyText();
      }
    },
    onPrivacyLinkTap: (url, name) => openWebView(url, title: name),
    onSuspendedDismiss: () async {
      if (await showExitConfirm()) AliyunNumberAuth.dismissLoginPage();
    },
  );
  // 发给后端：POST /api/one-key-login { token }
} on AliyunNumberAuthException catch (e) {
  // AliyunAuthCode.userCancelled → 用户点了返回，忽略
  // AliyunAuthCode.userSwitched  → 用户选择其他方式
  // AliyunAuthCode.timeout       → 超时
}
```

| 参数 | 类型 | 说明 |
|---|---|---|
| `timeout` | `Duration` | 取号超时，默认 10 秒 |
| `uiConfig` | `AliyunAuthUIConfig?` | 授权页样式，见 [AliyunAuthUIConfig](#aliyunauthuiconfig) |
| `onLoginButtonTap` | `void Function(bool isChecked)?` | 用户点击登录按钮时调用，`isChecked` 为 checkbox 当前状态；`false` 时 SDK 不取号，页面保持打开 |
| `onCheckboxToggle` | `void Function(bool isChecked)?` | 用户切换协议 checkbox 时调用，`isChecked` 为切换**之后**的新状态。SDK 的登录按钮无法通过 Flutter 动态禁用/改色，此回调适合做埋点或更新授权页**之外**的辅助 UI |
| `onAuthPageShown` | `VoidCallback?` | 授权页成功显示后触发一次。可用于关闭你自己的入口按钮 loading、做埋点等 |
| `onPrivacyLinkTap` | `void Function(String url, String name)?` | 用户点击协议链接时调用，需配合 `privacyVCIsCustomized: true` 使用 |
| `onSuspendedDismiss` | `VoidCallback?` | 返回键被拦截时调用，需配合 `suspendDisMissVC: true` 使用 |

所有回调在 Future 完成（无论成功/失败/取消）后自动清除，无需手动管理生命周期。

---

#### `dismissLoginPage({animated, waitForCompletion})`

**程序化关闭**授权页。**仅在授权页已显示时生效**(可以监听 `onAuthPageShown` 或自己保存"已弹出"状态确认时机);未显示时是 no-op,不会报错。

适用场景：
- `suspendDisMissVC: true` 时，在 `onSuspendedDismiss` 回调中决定是否关闭
- 需要从自定义逻辑主动关闭

```dart
await AliyunNumberAuth.dismissLoginPage();                          // 带动画(默认,iOS)
await AliyunNumberAuth.dismissLoginPage(animated: false);           // 无动画(iOS)
await AliyunNumberAuth.dismissLoginPage(waitForCompletion: true);   // 等动画跑完再 resolve
```

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `animated` | `bool` | `true` | 仅 iOS 有效;Android 始终无缝关闭,忽略该参数 |
| `waitForCompletion` | `bool` | `false` | **iOS only**。`true` 时 Future 等到 SDK 的 dismiss 动画完成才 resolve(带 1s 安全超时)。需要在关闭后立即 `Navigator.push` 才用得上,否则新路由可能跟正在消失的授权页短暂重叠。默认 `false`(eager return)是因为 SDK 的 completion block 文档标为 `_Nullable`,无授权页时不一定触发,等待可能挂起 |

关闭后，`getMobileToken` 的 Future 会以 `AliyunAuthCode.cancelled` 拒绝。

---

#### `setCheckboxChecked(bool checked)`

授权页显示期间，程序化勾选/取消勾选隐私协议 Checkbox。

On iOS calls `setCheckboxIsChecked`; on Android calls `setProtocolChecked`.

```dart
await AliyunNumberAuth.setCheckboxChecked(true);
```

---

#### `isCheckboxChecked()`

查询授权页 Checkbox 当前是否已勾选，返回 `bool`。

On iOS calls `queryCheckBoxIsChecked`; on Android calls the equivalent helper method.

```dart
final checked = await AliyunNumberAuth.isCheckboxChecked();
```

---

#### `hideLoginLoading()`

手动隐藏用户点击登录按钮后出现的转圈动画。

iOS 上仅在 `AliyunAuthUIConfig.autoHideLoginLoading = false` 时需要手动调用；Android 支持但通常不需要（SDK 会自动隐藏）。**iOS + Android 均支持。**

```dart
await AliyunNumberAuth.hideLoginLoading();
```

---

#### `animatePrivacyText()`

触发授权页协议文字的提示动画，用于在用户未同意协议直接点击登录时吸引注意力。**iOS + Android 均支持。**

```dart
// 配合 onLoginButtonTap 使用：用户点登录按钮但未勾协议时引导
await AliyunNumberAuth.animatePrivacyText();
```

---

#### `animateCheckbox()`

触发授权页 Checkbox 的提示动画，用于在用户未勾选时吸引注意力。**iOS + Android 均支持。**

```dart
await AliyunNumberAuth.animateCheckbox();
```

---

#### `closePrivacyAlertDialog()`

关闭二次隐私协议确认弹窗。iOS 调用 `closePrivactAlertView`，Android 调用 `quitPrivacyPage`。**iOS + Android 均支持。**

```dart
await AliyunNumberAuth.closePrivacyAlertDialog();
```

---

#### `getSDKVersion()`

获取 Aliyun SDK 版本字符串。

```dart
final version = await AliyunNumberAuth.getSDKVersion();
print(version); // "2.14.19"（iOS）/ "2.14.24"（Android）
```

---

### AliyunAuthController

`ChangeNotifier`-based 控制器，是一键登录的**推荐 API**。持有当前 `status` 与 `lastError`，状态变化时通知监听者。适合：
- 需要从 builder 之外触发登录（路由跳转、推送、AppBar action 等）
- 多个 UI 表面共享一份登录状态
- 想用 `ListenableBuilder` / `AnimatedBuilder` / `Provider` / `Riverpod` 等标准状态管理方案接入

```dart
final controller = AliyunAuthController();  // 默认 autoCheck: true

ListenableBuilder(
  listenable: controller,
  builder: (_, __) => ElevatedButton(
    onPressed: controller.canLogin
      ? () async {
          try {
            final token = await controller.login();
            await myBackend.exchange(token);
          } on AliyunNumberAuthException catch (e) {
            if (e.code != AliyunAuthCode.userCancelled) showError(e);
          }
        }
      : null,
    child: Text(switch (controller.status) {
      AliyunAuthStatus.checking => '检测中…',
      AliyunAuthStatus.available => '一键登录',
      AliyunAuthStatus.busy => '登录中…',
      _ => '短信登录',
    }),
  ),
)
```

#### 构造参数

| 参数 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `uiConfig` | `AliyunAuthUIConfig` | `const AliyunAuthUIConfig()` | `login()` 的默认 UI 配置（可在调用时覆盖） |
| `timeout` | `Duration` | 10 秒 | `login()` 的默认超时 |
| `autoCheck` | `bool` | `true` | 构造后通过 microtask 自动调用 `checkEnv()` |

#### 状态机

```
uninitialized ──checkEnv()──► checking ──┬─► available
                                          └─► unavailable

{uninitialized, available, unavailable}
    │
    └──login()──► busy ──┬─► available   (登录成功 — 成功本身证明环境可用)
                          └─► <prev>      (失败/取消 — 环境不变；lastError 含错误码)
```

`login()` 可以在任何**非 busy** 状态触发(包括 `uninitialized`)— 成功本身就是环境可用的证据，无需先 `checkEnv()`。如果调用时正好有 `checkEnv()` 在跑，`login()` 会先 await 它结束再进 busy(避免状态闪烁)。

| 状态 | 含义 |
|---|---|
| `uninitialized` | 还未跑过 `checkEnv()` |
| `checking` | 正在检测环境 |
| `available` | 设备支持一键登录，可以 `login()` |
| `unavailable` | 不支持（无 SIM、海外号码、运营商不支持等） |
| `busy` | 登录流程进行中 |

#### 方法

| 方法 | 说明 |
|---|---|
| `checkEnv()` | 主动触发环境检测，刷新 `status`。并发调用自动去重(返回同一 Future)；status 为 `busy` 时 no-op |
| `login({autoDismissOnSuccess, ...})` | 触发一键登录,返回 token。所有参数都可覆盖控制器默认值;并发调用抛 `BUSY`;disposed 调用抛 `CANCELLED`。`autoDismissOnSuccess: true` 配合 `uiConfig.suspendDisMissVC: true` 使用时,登录成功后会等 iOS 授权页 dismiss 动画跑完再 resolve Future(`waitForCompletion: true`),适合在 `onSuccess` 里 `Navigator.push`;不开 `suspendDisMissVC` 时该参数被忽略(SDK 自己会关) |
| `dismissLoginPage({animated, waitForCompletion})` | 程序化关闭授权页 |
| `dispose()` | 释放资源 |

#### 属性

| 属性 | 类型 | 说明 |
|---|---|---|
| `status` | `AliyunAuthStatus` | 当前状态 |
| `canLogin` | `bool` | 便利属性，等价于 `status == available` |
| `lastError` | `AliyunNumberAuthException?` | 最近一次失败的异常；**新操作开始时与 status 一起原子清空** |
| `uiConfig` / `timeout` | 同构造参数 | 可读写，下一次 `login()` 生效 |

---

### AliyunAuthWidget

`AliyunAuthController` + `builder` 的轻量便利封装。**单页单按钮**场景用它最省事；需要跨页面共享状态或外部触发请直接用 `AliyunAuthController`。

```dart
AliyunAuthWidget(
  // 必填
  builder: (context, status, login) { ... },
  onSuccess: (token) { ... },

  // 可选
  onError: (e) { ... },
  controller: myController,            // 不传则内部 own 一个
  uiConfig: AliyunAuthUIConfig(...),   // 仅 controller==null 时生效
  timeout: Duration(seconds: 10),      // 同上
  autoDismissOnSuccess: true,          // 配合 suspendDisMissVC=true 使用

  // 本次 login 的回调（透传到 controller.login）
  onPrivacyLinkTap: (url, name) { ... },
  onSuspendedDismiss: () { ... },
  onLoginButtonTap: (isChecked) { ... },
  onCheckboxToggle: (isChecked) { ... },
  onAuthPageShown: () { ... },
)
```

| 参数 | 类型 | 说明 |
|---|---|---|
| `builder` | `AliyunAuthBuilder` | 构建 UI；`status` 为 `AliyunAuthStatus`，`login` 在 `status==available` 时非 `null` |
| `onSuccess` | `ValueChanged<String>` | 内部 `login()` 成功后调用，参数为 token |
| `onError` | `ValueChanged<AliyunNumberAuthException>?` | 内部 `login()` 失败或取消时调用 |
| `controller` | `AliyunAuthController?` | 外部控制器；不传则 Widget 自己 own（dispose 时一起释放）。**不支持热替换**，debug 模式会触发 `AssertionError`；需切换请给 Widget 一个新的 `Key` |
| `uiConfig` / `timeout` | 同名 | 仅当 `controller==null` 时使用：初始化内部 controller，并在 `didUpdateWidget` 时同步到 owned controller(下一次 `login()` 生效)。传入外部 `controller` 时这两个参数被忽略 |
| `autoDismissOnSuccess` | `bool` | 默认 `false`。`true` 且解析后的 `uiConfig.suspendDisMissVC == true` 时,登录成功后等 SDK 授权页 dismiss 动画完成(`waitForCompletion: true`)再触发 `onSuccess`,这样 `onSuccess` 里 `Navigator.push` 不会跟正在消失的授权页重叠。`suspendDisMissVC == false` 时 SDK 自己会关,该参数被忽略 |
| `onPrivacyLinkTap` 等 5 个回调 | — | 透传给本次 `login()` 调用 |

**Builder 示例（推荐用 switch 表达式）：**

```dart
builder: (context, status, login) {
  return ElevatedButton(
    onPressed: login,    // login==null 时按钮自动 disabled
    child: Text(switch (status) {
      AliyunAuthStatus.checking => '检测中…',
      AliyunAuthStatus.available => '本机号码一键登录',
      AliyunAuthStatus.busy => '登录中…',
      AliyunAuthStatus.uninitialized => '准备中…',
      AliyunAuthStatus.unavailable => '短信验证码登录',
    }),
  );
},
```

---

### AliyunAuthUIConfig

授权页样式配置。所有属性可选，有合理默认值。

#### 展示模式

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `dialogMode` | `bool` | `true` | `true` = 底部弹出 sheet；`false` = 全屏 |
| `dialogHeight` | `double` | `300` | Sheet 高度（逻辑像素），仅 `dialogMode=true` |
| `tapBackgroundToClose` | `bool` | `true` | 点击蒙层关闭，仅 `dialogMode=true` |
| `cornerRadius` | `double` | `16` | Sheet 顶部两个圆角半径，仅 `dialogMode=true`，**iOS only**（Android SDK 无此 API） |
| `backgroundColor` | `Color?` | 白色 | Sheet 内容区背景色 |
| `maskColor` | `Color?` | 黑色 | 蒙层颜色，仅 `dialogMode=true` |
| `maskAlpha` | `double` | `0.5` | 蒙层透明度，仅 `dialogMode=true` |
| `presentDirection` | `AliyunAuthPresentDirection` | `bottom` | 授权页弹出方向（**iOS only**，仅全屏模式） |

`AliyunAuthPresentDirection` 枚举值：`bottom`（默认）/ `right` / `top` / `left`

#### 状态栏

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `statusBarHidden` | `bool` | `false` | 是否隐藏状态栏 |
| `statusBarDarkText` | `bool` | `true` | `true` = 深色图标（适合浅色背景） |

#### 导航栏（仅全屏模式）

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `navHidden` | `bool` | `true` | 隐藏导航栏 |
| `navColor` | `Color?` | — | 导航栏背景色 |
| `navTitle` | `String?` | — | 导航栏标题 |
| `navTitleColor` | `Color?` | — | 标题颜色 |
| `hideBackButton` | `bool` | `true` | 隐藏返回按钮 |

#### Logo

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `logoHidden` | `bool` | `true` | 隐藏 Logo |
| `logoImageData` | `Uint8List?` | — | Logo 图片字节（PNG/JPEG），iOS + Android |

```dart
logoImageData: (await rootBundle.load('assets/logo.png')).buffer.asUint8List(),
```

#### 背景图

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `backgroundImageData` | `Uint8List?` | — | Sheet / 全屏背景图字节（PNG/JPEG），iOS + Android |
| `backgroundImageContentMode` | `AliyunAuthBackgroundImageContentMode` | `cover` | 背景图填充方式：`cover` 裁切铺满 / `contain` 完整显示 / `fill` 拉伸 / `center` 居中 / `tile` 平铺 |

#### Slogan

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `sloganHidden` | `bool` | `true` | 隐藏 Slogan |
| `sloganText` | `String?` | — | Slogan 文案 |
| `sloganColor` | `Color?` | — | Slogan 颜色 |
| `sloganFontSize` | `double?` | — | Slogan 字号 |

#### 脱敏手机号

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `numberColor` | `Color?` | — | 号码文字颜色 |
| `numberFontSize` | `double?` | — | 号码字号（≥ 16 才生效） |

#### 登录按钮

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `loginBtnText` | `String` | `'本机号码一键登录'` | 按钮文案 |
| `loginBtnTextColor` | `Color?` | 白色 | 文字颜色 |
| `loginBtnFontSize` | `double?` | `17` | 字号 |
| `loginBtnBgColor` | `Color?` | `#1677FF` | 背景色 |
| `loginBtnCornerRadius` | `double` | `24` | 圆角半径 |
| `showLoginLoading` | `bool` | `true` | 用户点击登录按钮后是否显示转圈动画，iOS + Android |
| `autoHideLoginLoading` | `bool` | `true` | 成功后是否自动隐藏转圈（`false` 时须手动调 `hideLoginLoading()`），**iOS only** |

#### 切换按钮

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `switchBtnHidden` | `bool` | `false` | 隐藏「切换其他登录方式」按钮 |
| `switchBtnText` | `String?` | — | 自定义文案 |
| `switchBtnColor` | `Color?` | — | 文字颜色 |

#### Checkbox

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `checkBoxChecked` | `bool` | `false` | 默认勾选 |
| `checkBoxHidden` | `bool` | `false` | 隐藏 Checkbox |
| `checkBoxSize` | `double` | `20` | 尺寸（逻辑像素） |
| `checkBoxColor` | `Color?` | `#1677FF` | 选中填充色 / 未选中边框色 |
| `checkBoxCircle` | `bool` | `false` | `true` = 圆形；`false` = 圆角方形 |
| `checkBoxCheckColor` | `Color?` | 白色 | 选中时勾的颜色 |
| `checkBoxVerticalCenter` | `bool` | `false` | Checkbox 与协议文字垂直居中 |
| `checkBoxInnerPadding` | `double` | `3` | 勾与边框之间的内边距，iOS + Android |
| `expandCheckboxTapScope` | `bool` | `false` | 将 Checkbox 点击区域扩展到前缀文案（如「我已阅读并同意」），iOS + Android |

#### 协议文字

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `privacyOne` | `List<String>?` | — | `['协议名', 'https://...']`，必须恰好两个元素，否则 debug 模式断言失败 |
| `privacyTwo` | `List<String>?` | — | 同上，第二条协议 |
| `privacyThree` | `List<String>?` | — | 同上，第三条协议 |
| `privacyPreText` | `String?` | — | 协议前缀文案（如「我已阅读并同意」） |
| `privacySufText` | `String?` | — | 协议后缀文案 |
| `privacyOperatorPreText` | `String?` | — | 运营商协议前缀（如「《」） |
| `privacyOperatorSufText` | `String?` | — | 运营商协议后缀（如「》」） |
| `privacyConectTexts` | `List<String>?` | `['和','、','、']` | 协议之间的连接文字，**必须恰好 3 个元素**，iOS + Android |
| `privacyOperatorIndex` | `int` | `0` | 运营商协议显示位置（0=第1个，最大3），iOS + Android |
| `privacyColor` | `Color?` | — | 普通文字颜色 |
| `privacyLinkColor` | `Color?` | — | 所有可点击链接的统一颜色，以下各条可单独覆盖 |
| `privacyOperatorColor` | `Color?` | — | 运营商协议链接颜色，优先级高于 `privacyLinkColor`，iOS + Android |
| `privacyOneColor` | `Color?` | — | 第一条协议链接颜色，iOS + Android |
| `privacyTwoColor` | `Color?` | — | 第二条协议链接颜色，iOS + Android |
| `privacyThreeColor` | `Color?` | — | 第三条协议链接颜色，iOS + Android |
| `privacyFontSize` | `double?` | — | 协议文字字号 |
| `privacyLineSpacing` | `double?` | — | 协议文字行间距 |
| `privacyCenterAlign` | `bool` | `true` | 协议文字居中对齐 |
| `privacyOperatorUnderline` | `bool` | `false` | 给运营商协议文字添加下划线，iOS + Android |

#### 协议详情页（WebView）

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `privacyVCIsCustomized` | `bool` | `false` | `true` = 拦截链接点击，由 `onPrivacyLinkTap` 处理；`false` = SDK 内置 WebView |
| `privacyNavColor` | `Color?` | — | 内置 WebView 导航栏背景色 |
| `privacyNavTitleColor` | `Color?` | — | 内置 WebView 导航栏标题颜色 |
| `privacyNavBackColor` | `Color?` | 系统色 | 内置 WebView 返回箭头颜色 |

#### 对话框标题栏（仅 `dialogMode=true`，**iOS only**）

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `alertBarVisible` | `bool` | `false` | 显示 Sheet 顶部标题栏，默认隐藏 |
| `alertTitle` | `String?` | — | 标题栏文案，仅 `alertBarVisible=true` 时生效 |
| `alertTitleBarColor` | `Color?` | — | 标题栏背景色 |
| `alertTitleColor` | `Color?` | — | 标题文字颜色，**iOS only** |
| `alertCloseButtonHidden` | `bool` | `false` | 隐藏标题栏右侧关闭按钮（×） |
| `alertAvoidsKeyboard` | `bool` | `false` | 键盘弹起时 Sheet 自动上移避让，**iOS only** |

#### Drag Handle（仅 `dialogMode=true`）

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `dragHandleVisible` | `bool` | `false` | 显示 Sheet 顶部视觉拖拽手柄，不提供真实拖拽交互；Android 会将其绘入背景以保持入场动画同步 |
| `dragHandleColor` | `Color?` | `#D8D8D8` | 手柄颜色 |
| `dragHandleWidth` | `double` | `36` | 手柄宽度 |
| `dragHandleHeight` | `double` | `4` | 手柄高度 |
| `dragHandleTopOffset` | `double` | `8` | 手柄距离 Sheet 顶部的距离 |

#### 高级行为

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `suspendDisMissVC` | `bool` | `false` | `true` = 返回键不自动关闭授权页，改为触发 `onSuspendedDismiss`；需手动调 `dismissLoginPage()` |

#### 高级布局（仅 `dialogMode=true`）

当默认布局位置不满足设计需求时，可微调各元素 Y 坐标。

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `numberOffsetY` | `double?` | `28` | 脱敏号码距 sheet 顶部的 Y 坐标 |
| `loginBtnOffsetY` | `double?` | `82` | 登录按钮距 sheet 顶部的 Y 坐标 |
| `loginBtnHeight` | `double?` | `50` | 登录按钮高度 |
| `privacyAreaHeight` | `double?` | `72` | 协议区域高度（贴近 sheet 底部），**iOS only**；Android 协议控件高度由 SDK 内容决定 |
| `privacyHorizontalPadding` | `double?` | 同登录按钮左右边距 | 协议区域距 sheet 左右边缘的距离 |
| `privacyBottomOffset` | `double?` | `16` | 协议区域距 sheet 底部的距离 |

---

### AliyunAuthCode

错误码和事件码常量，用于 `AliyunNumberAuthException.code` 的判断。

```dart
onError: (e) {
  switch (e.code) {
    case AliyunAuthCode.userCancelled: return;          // 用户点了返回，忽略
    case AliyunAuthCode.userSwitched:  goSmsLogin(); return; // 切换方式
    case AliyunAuthCode.timeout:       showRetry(); return;
    case AliyunAuthCode.noSimCard:     showNoSimCard(); return;
    default:                           showError(e.message);
  }
}
```

**SDK 结果码**

| 常量 | 值 | 说明 |
|---|---|---|
| `success` | `600000` | 成功 |
| `pageShown` | `600001` | 授权页弹出成功（中间状态，非终态） |
| `pageFailed` | `600002` | 授权页弹出失败 |
| `carrierConfigFailed` | `600004` | 获取运营商配置失败 |
| `noSimCard` | `600007` | 未检测到 SIM 卡 |
| `cellularOff` | `600008` | 蜂窝网络未开启或不稳定 |
| `unknownCarrier` | `600009` | 无法判断运营商 |
| `unknownError` | `600010` | 未知异常 |
| `tokenFailed` | `600011` | 获取 token 失败 |
| `preloadFailed` | `600012` | 预取号失败 |
| `carrierMaintenance` | `600013` | 运营商维护中，功能不可用 |
| `carrierMaxCalls` | `600014` | 运营商维护中，已达最大调用次数 |
| `timeout` | `600015` | 接口超时 |
| `invalidKey` | `600017` | 密钥解析失败 |
| `numberRestricted` | `600018` | 号码被运营商管控（仅联通） |
| `carrierChanged` | `600021` | 运营商已切换 |
| `envCheckFailed` | `600025` | 终端环境检测失败 |
| `preloadInAuthPage` | `600026` | 授权页已展示时不允许调预热接口 |

**UI 交互事件码**

`userCancelled` / `userSwitched` 以 `AliyunNumberAuthException` 形式出现在 `onError` 中。其余三个（`loginButtonTapped`、`privacyLinkTapped`、`suspendedDismiss`）通过对应回调传递，**不抛出异常**。

| 常量 | 值 | 说明 |
|---|---|---|
| `userCancelled` | `700000` | 用户点击返回 / 取消 |
| `userSwitched` | `700001` | 用户点击「切换其他登录方式」 |
| `loginButtonTapped` | `700002` | 用户点击登录按钮（由 `onLoginButtonTap` 接收，不抛出异常；`isChecked` 字段反映 checkbox 状态） |
| `privacyLinkTapped` | `700004` | 用户点击协议链接（仅 `privacyVCIsCustomized=true` 时由 `onPrivacyLinkTap` 接收，不抛出异常） |
| `suspendedDismiss` | `700010` | 返回键被拦截（仅 `suspendDisMissVC=true` 时由 `onSuspendedDismiss` 接收，不抛出异常） |
| `pageDealloced` | `700020` | 授权页 VC 已销毁（iOS only，中间状态，流程已结束） |

**插件级别错误码**

| 常量 | 值 | 说明 |
|---|---|---|
| `invalidArgs` | `INVALID_ARGS` | 参数为空（如 SK） |
| `notInitialized` | `NOT_INITIALIZED` | 未调 `init()` |
| `busy` | `BUSY` | 有调用正在进行中 |
| `cancelled` | `CANCELLED` | 调用被取消（如 `dismissLoginPage()`） |
| `noToken` | `NO_TOKEN` | SDK 返回成功但 token 为空 |
| `noActivity` | `NO_ACTIVITY` | 无活跃 Activity（Android only） |
| `noViewController` | `NO_VIEW_CONTROLLER` | 无活跃 UIViewController（iOS only） |
| `failed` | `FAILED` | 兜底错误码 |

---

## 完整使用示例

### 本机号码校验流程

```dart
// App 启动
await AliyunNumberAuth.init(androidSk, iosSk);
final ok = await AliyunNumberAuth.checkEnvAvailable(type: AliyunAuthType.verifyToken);
if (ok) AliyunNumberAuth.preload();

// 登录页
try {
  final token = await AliyunNumberAuth.getVerifyToken();
  await myBackend.verifyPhone(token: token, phone: userInputPhone);
} on AliyunNumberAuthException catch (e) {
  showError(e.code);
}
```

### 一键登录流程（推荐）

```dart
AliyunAuthWidget(
  uiConfig: AliyunAuthUIConfig(
    dialogMode: true,
    dialogHeight: 320,
    backgroundColor: Color(0xFFFFFFFF),
    cornerRadius: 20,
    maskAlpha: 0.4,

    numberColor: Color(0xFF1A1A1A),

    loginBtnText: '一键登录',
    loginBtnBgColor: Color(0xFF0066FF),
    loginBtnTextColor: Color(0xFFFFFFFF),
    loginBtnCornerRadius: 28,

    privacyOne: ['用户协议', 'https://your.app/terms'],
    privacyTwo: ['隐私政策', 'https://your.app/privacy'],
    privacyColor: Color(0xFF999999),
    privacyLinkColor: Color(0xFF0066FF),
    checkBoxColor: Color(0xFF0066FF),
    checkBoxCircle: true,
    checkBoxVerticalCenter: true,
    switchBtnHidden: true,
  ),
  builder: (context, status, login) {
    if (status != AliyunAuthStatus.available) {
      return OutlinedButton(onPressed: goSmsLogin, child: Text('短信验证码登录'));
    }
    return FilledButton(onPressed: login, child: Text('本机号码一键登录'));
  },
  onSuccess: (token) async {
    final phone = await myBackend.getPhone(token);
    goHome(phone);
  },
  onError: (e) {
    if (e.code == AliyunAuthCode.userCancelled) return;
    if (e.code == AliyunAuthCode.userSwitched) goSmsLogin();
    else showError(e.message);
  },
)
```

### 自定义协议页

```dart
AliyunAuthWidget(
  uiConfig: AliyunAuthUIConfig(
    privacyVCIsCustomized: true,
    privacyOne: ['用户协议', 'https://your.app/terms'],
  ),
  onPrivacyLinkTap: (url, name) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebViewPage(url: url, title: name)),
    );
  },
  builder: (context, status, login) { ... },
  onSuccess: (token) { ... },
)
```

### 返回键拦截（自定义确认弹窗）

```dart
AliyunAuthWidget(
  uiConfig: AliyunAuthUIConfig(suspendDisMissVC: true),
  onSuspendedDismiss: () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('确认退出？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('继续登录')),
          TextButton(onPressed: () => Navigator.pop(context, true),  child: Text('退出')),
        ],
      ),
    );
    if (confirmed == true) AliyunNumberAuth.dismissLoginPage();
  },
  builder: (context, status, login) { ... },
  onSuccess: (token) { ... },
)
```

---

## 更新 SDK

```bash
./script/import-sdk.sh
```

在 macOS 上安装 Python 3 和 Xcode 命令行工具。将官方 Android ZIP 和 iOS **dynamic ZIP** 放入 `sdk/`；脚本按文件名版本挑选两个平台各自最新的包。

脚本先检查 Android 所需类、方法名提示及 iOS 公开头文件，再暂存完整资源、Maven 工件、Gradle 版本和 XCFramework。方法名检查不能代替编译及真实 SDK 验证。两端检查全部通过后才替换；一般失败或 HUP/INT/TERM 中断会回滚。进程强杀或断电后需检查 `sdk/.import-sdk.*` 备份和 `.import-sdk.lock`，恢复一致状态后再重试。未知或重复 Android 依赖会阻止导入，需先审查新 SDK 的依赖要求。

动态 SDK 合并提供 `ATAuthSDK_D`，无需单独引入旧 `ATAuthSDK`、`YTXMonitor`、`YTXOperators`。脚本为所有 slice 补齐 Swift module map，将官方设备 dSYM 与设备二进制逐架构核对 UUID，并通过 XCFramework 的 `DebugSymbolsPath` 分发。缺少或不匹配的符号会阻止更新；不会制造空 dSYM，也不会把符号作为 App 资源打包。

官方模拟器 framework 的 ad-hoc 资源签名在补齐 module map 后重新签名并严格核验，不使用证书或凭据。带真实签名身份的 framework 或签名 XCFramework 会拒绝改写，需单独审查分发方式。当前官方设备二进制及其 DWARF 保持原字节。

### iOS 符号与归档

旧静态版的 SDK 代码和可用调试信息链接进 Runner。Xcode 为承载资源生成空动态占位文件时，可能报 `ATAuthSDK`、`YTXMonitor`、`YTXOperators` 缺失 dSYM。当前使用官方动态版及其配套符号解决这条分发链路。SPM 本身支持静态和动态 binary target。

检查**新生成**的 `.xcarchive`：`Products/Applications/<App>.app/Frameworks/ATAuthSDK_D.framework/ATAuthSDK_D` 与 `dSYMs/ATAuthSDK_D.framework.dSYM` 的 `xcrun dwarfdump --uuid` 结果必须匹配。此修复不覆盖其他插件（例如 fluwx 的 `WechatOpenSDK`）的符号告警；旧归档也不会自动改变。

本地检查：`python3 -m unittest discover -s script -p 'test_*.py' -v`、`flutter analyze`、`flutter test`。iOS 原生可控回调测试位于 example 的 `RunnerTests`；它们不调用真实运营商认证。

---

## 功能状态

| 状态 | 功能 | iOS | Android |
|:---:|---|:---:|:---:|
| ✅ | 本机号码校验（`init` / `checkEnvAvailable` / `preload` / `getVerifyToken`） | ✅ | ✅ |
| ✅ | 一键登录（`getMobileToken` / `dismissLoginPage` / `preloadLogin`） | ✅ | ✅ |
| ✅ | 授权页 UI 定制（颜色 / 字体 / 按钮 / Checkbox / 协议 / 布局） | ✅ | ✅ |
| ✅ | Sheet / 全屏背景图（`backgroundImageData`） | ✅ | ✅ |
| ✅ | 各协议独立颜色（`privacyOperatorColor` / `privacyOneColor` 等） | ✅ | ✅ |
| ✅ | 协议文字细节（连接文字 / 运营商排序 / 下划线 / 行间距） | ✅ | ✅ |
| ✅ | 登录按钮点击事件 + checkbox 状态（`onLoginButtonTap`） | ✅ | ✅ |
| ✅ | 自定义协议详情页（`privacyVCIsCustomized` + `onPrivacyLinkTap`） | ✅ | ✅ |
| ✅ | 返回键拦截（`suspendDisMissVC` + `onSuspendedDismiss`） | ✅ | ✅ |
| ✅ | 运行时 Checkbox 控制（`setCheckboxChecked` / `isCheckboxChecked`） | ✅ | ✅ |
| ✅ | 登录 Loading 控制（`showLoginLoading` / `hideLoginLoading`） | ✅ | ✅ |
| ✅ | 授权页动画触发（`animatePrivacyText` / `animateCheckbox`） | ✅ | ✅ |
| ✅ | 二次弹窗关闭（`closePrivacyAlertDialog`） | ✅ | ✅ |
| ✅ | 错误码常量（`AliyunAuthCode`） | ✅ | ✅ |
| ✅ | 弹出方向（`presentDirection`） | ✅ | — |
| ✅ | 对话框标题栏（`alertBarVisible` / `alertTitle` 等） | ✅ | — |
| ✅ | 对话框圆角（`cornerRadius`） | ✅ | 部分（配置背景色或背景图时生效） |
| ✅ | 自动隐藏 Loading（`autoHideLoginLoading`） | ✅ | — |
| ✅ | Checkbox 垂直居中（`checkBoxVerticalCenter`） | ✅ | — |
| ✅ | 对话框键盘避让（`alertAvoidsKeyboard`） | ✅ | — |
| ✅ | 对话框元素布局偏移（`numberOffsetY` 等） | ✅ | 部分（不含 `privacyAreaHeight`） |
| 🚧 | 二次隐私确认弹窗完整配置（`privacyAlertIsNeedShow` 等属性） | 🚧 | 🚧 |
| 🚧 | 授权页自定义 View 注入（需原生桥接） | 🚧 | 🚧 |
| 🚧 | 自定义进场/退场动画（需原生桥接） | 🚧 | 🚧 |
| 🚧 | 功能开关（`FeatureManager`）/ 日志控制（`PNSReporter`） | 🚧 | 🚧 |
| 🚧 | 授权页 UI 调试模式（`debugLoginUI`） | 🚧 | — |
