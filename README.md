# Aliyun Number Auth

阿里云号码认证 Flutter 插件

SDK 版本
- **Android** — v2.14.23
- **iOS** — v2.14.18
---

## 安装

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  aliyun_number_auth:
    git:
      url: https://github.com/shell-echo/aliyun-number-auth.git
```

```bash
flutter pub get
```

> **iOS 需要开启 Swift Package Manager：**
> ```bash
> flutter config --enable-swift-package-manager
> ```


---

## 使用

```dart
import 'package:aliyun_number_auth/aliyun_number_auth.dart';

// 1. 初始化，App 生命周期内调一次
await AliyunNumberAuth.init('YOUR_ANDROID_SK', 'YOUR_IOS_SK');

// 2. 检查蜂窝网络是否支持取号
final available = await AliyunNumberAuth.checkEnvAvailable();
if (!available) return; // 降级到短信验证码等其他方式

// 3. 预热（可选，让 getVerifyToken 响应更快）
AliyunNumberAuth.preload();

// 4. 取 token，发给后端换手机号
try {
  final token = await AliyunNumberAuth.getVerifyToken();
  // await yourBackend.exchangeToken(token);
} on AliyunNumberAuthException catch (e) {
  print('${e.code}: ${e.message}');
}
```

### API

| 方法 | 说明 |
|---|---|
| `init(androidSk, iosSk)` | 初始化 SDK，其他方法调用前必须先调此方法 |
| `checkEnvAvailable()` | 检查蜂窝网络是否支持号码认证，返回 `bool` |
| `preload({timeout})` | 预热加速，fire-and-forget，无需 await |
| `getVerifyToken({timeout})` | 静默取 token，失败抛 `AliyunNumberAuthException` |

### AliyunNumberAuthException

```dart
class AliyunNumberAuthException implements Exception {
  final String code;     // 错误码（见下表）
  final String? message; // 错误描述
}
```

---

## 错误码

### SDK 错误码

| 错误码 | 含义 |
|---|---|
| `600000` | 成功 |
| `600004` | 获取运营商配置失败 |
| `600007` | 未检测到 SIM 卡 |
| `600008` | 蜂窝网络未开启或不稳定 |
| `600009` | 无法判断运营商 |
| `600010` | 未知异常 |
| `600011` | 获取 Token 失败（含运营商错误码，见[阿里云文档](https://help.aliyun.com/document_detail/85351.html)） |
| `600012` | 预取号失败 |
| `600013` | 运营商维护中，功能不可用 |
| `600014` | 运营商维护中，已达最大调用次数 |
| `600015` | 接口超时 |
| `600017` | SK 密钥解析失败（密钥错误或签名不匹配） |
| `600018` | 号码被运营商管控（仅联通） |
| `600021` | 运营商已切换 |
| `600025` | 终端环境检测失败 |

### 插件错误码

| 错误码 | 含义 |
|---|---|
| `INVALID_ARGS` | SK 为空 |
| `NOT_INITIALIZED` | 未调 `init()` |
| `BUSY` | 有调用正在进行中 |
| `CANCELLED` | Flutter Engine 销毁时挂起的调用被取消 |
| `NO_TOKEN` | SDK 返回成功但 token 为空（异常情况） |
| `FAILED` | SDK 响应解析失败（兜底码） |

---

## 更新 SDK

将官方最新 zip 放入 `sdk/` 目录后执行：

```bash
./script/import-sdk.sh
# 或显式指定路径
./script/import-sdk.sh <android_sdk.zip> <ios_sdk_static.zip>
```

> iOS 选 **static 版本**（文件名含 `_static`），SPM binary target 需要静态库。

---

## TODO

- ✅ 静默取号（`init` / `checkEnvAvailable` / `preload` / `getVerifyToken`）
- [ ] 一键登录（SERVICE_TYPE_LOGIN）
  - [ ] 立即模式 / 延迟模式（`accelerateLoginPage` + `getLoginToken`）
  - [ ] 关闭授权页（`cancelLoginVC` / `quitLoginPage`）
  - [ ] 授权页展示模式：全屏竖屏 / 全屏横屏 / 全屏旋转 / 弹窗竖屏 / 弹窗横屏 / 弹窗旋转 / 底部弹窗
  - [ ] 授权页 UI 定制（导航栏、logo、号码颜色、登录按钮、协议文字、checkbox）
  - [ ] 自定义背景（图片 / GIF / 视频）
  - [ ] 进场/退场动画（渐变 / 弹性 / 下坠 / 缩放）
  - [ ] 二次隐私确认弹窗
  - [ ] Android 自定义 View / XML 布局
- [ ] 设备网络工具（运营商名称 / 网络类型 / SIM 检测 / WWAN 状态）
- [ ] 功能开关（`FeatureManager`：减少网络请求 / 运营商缓存策略）
- [ ] 日志开关（`PNSReporter` / `PnsReporter`）
- [ ] 授权页 UI 调试模式（`debugLoginUI`，iOS only）
