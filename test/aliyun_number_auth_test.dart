import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aliyun_number_auth/aliyun_number_auth.dart';
import 'package:aliyun_number_auth/aliyun_number_auth_platform_interface.dart';
import 'package:aliyun_number_auth/aliyun_number_auth_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAliyunNumberAuthPlatform
    with MockPlatformInterfaceMixin
    implements AliyunNumberAuthPlatform {
  /// Counts checkEnvAvailable calls — used by the dedupe-concurrent-checkEnv test.
  int checkEnvCallCount = 0;

  /// Counts dismissLoginPage calls — used by the autoDismissOnSuccess tests.
  int dismissLoginPageCallCount = 0;
  bool? lastDismissWaitForCompletion;

  /// If set, dismissLoginPage throws this exception (used to verify that
  /// dismiss failures don't swallow the login token).
  AliyunNumberAuthException? dismissError;

  /// Captures the uiConfig map last passed to getMobileToken — used by the
  /// autoDismissOnSuccess tests to verify the suspendDisMissVC flag flows
  /// through correctly.
  Map<String, dynamic>? lastGetMobileTokenUiConfig;

  @override
  Future<void> init(String androidSk, String iosSk) => Future.value();

  @override
  Future<bool> checkEnvAvailable({AliyunAuthType type = AliyunAuthType.loginToken}) {
    checkEnvCallCount++;
    return Future.value(true);
  }

  @override
  Future<void> preload({Duration timeout = const Duration(seconds: 3)}) => Future.value();

  @override
  Future<void> preloadLogin({Duration timeout = const Duration(seconds: 3)}) => Future.value();

  @override
  Future<String> getVerifyToken({Duration timeout = const Duration(seconds: 10)}) {
    return Future.value('mock_verify_token');
  }

  @override
  Future<String> getMobileToken({
    Duration timeout = const Duration(seconds: 10),
    Map<String, dynamic>? uiConfig,
  }) {
    lastGetMobileTokenUiConfig = uiConfig;
    return Future.value('mock_mobile_token');
  }

  @override
  void setPrivacyLinkCallback(void Function(String url, String name)? callback) {}

  @override
  void setSuspendedDismissCallback(void Function()? callback) {}

  @override
  void setLoginButtonTapCallback(void Function(bool isChecked)? callback) {}

  @override
  void setCheckboxToggleCallback(void Function(bool isChecked)? callback) {}

  @override
  void setAuthPageShownCallback(void Function()? callback) {}

  @override
  Future<void> dismissLoginPage({
    bool animated = true,
    bool waitForCompletion = false,
  }) {
    dismissLoginPageCallCount++;
    lastDismissWaitForCompletion = waitForCompletion;
    final err = dismissError;
    if (err != null) return Future.error(err);
    return Future.value();
  }

  @override
  Future<void> setCheckboxChecked(bool checked) => Future.value();

  @override
  Future<bool> isCheckboxChecked() => Future.value(true);

  @override
  Future<void> hideLoginLoading() => Future.value();

  @override
  Future<void> closePrivacyAlertDialog() => Future.value();

  @override
  Future<void> animatePrivacyText() => Future.value();

  @override
  Future<void> animateCheckbox() => Future.value();

  @override
  Future<String> getSDKVersion() => Future.value('0.0.0-mock');
}

/// Mock platform whose [checkEnvAvailable] always throws — used to seed a
/// real [AliyunAuthController.lastError] in regression tests.
class _ThrowingMockPlatform
    with MockPlatformInterfaceMixin
    implements AliyunNumberAuthPlatform {
  @override
  Future<bool> checkEnvAvailable({AliyunAuthType type = AliyunAuthType.loginToken}) {
    throw const AliyunNumberAuthException('600009', 'mock unknown carrier');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Mock platform whose checkEnv succeeds but getMobileToken fails — used to
/// verify the login-error notification path.
class _LoginErrorMockPlatform
    with MockPlatformInterfaceMixin
    implements AliyunNumberAuthPlatform {
  @override
  Future<bool> checkEnvAvailable({AliyunAuthType type = AliyunAuthType.loginToken}) =>
      Future.value(true);

  @override
  Future<String> getMobileToken({
    Duration timeout = const Duration(seconds: 10),
    Map<String, dynamic>? uiConfig,
  }) {
    throw const AliyunNumberAuthException('700000', 'mock user cancelled');
  }

  @override
  void setPrivacyLinkCallback(void Function(String url, String name)? callback) {}
  @override
  void setSuspendedDismissCallback(void Function()? callback) {}
  @override
  void setLoginButtonTapCallback(void Function(bool isChecked)? callback) {}
  @override
  void setCheckboxToggleCallback(void Function(bool isChecked)? callback) {}
  @override
  void setAuthPageShownCallback(void Function()? callback) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final AliyunNumberAuthPlatform initialPlatform = AliyunNumberAuthPlatform.instance;

  test('$MethodChannelAliyunNumberAuth is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAliyunNumberAuth>());
  });

  group('with mock platform', () {
    late MockAliyunNumberAuthPlatform fakePlatform;

    setUp(() {
      fakePlatform = MockAliyunNumberAuthPlatform();
      AliyunNumberAuthPlatform.instance = fakePlatform;
    });

    tearDown(() {
      AliyunNumberAuthPlatform.instance = initialPlatform;
    });

    test('init completes without error', () async {
      await expectLater(AliyunNumberAuth.init('android_sk', 'ios_sk'), completes);
    });

    test('checkEnvAvailable (loginToken — default)', () async {
      expect(await AliyunNumberAuth.checkEnvAvailable(), true);
    });

    test('checkEnvAvailable (verifyToken)', () async {
      expect(
          await AliyunNumberAuth.checkEnvAvailable(type: AliyunAuthType.verifyToken), true);
    });

    test('preload completes without error', () async {
      await expectLater(AliyunNumberAuth.preload(), completes);
    });

    test('preloadLogin completes without error', () async {
      await expectLater(AliyunNumberAuth.preloadLogin(), completes);
    });

    test('getVerifyToken', () async {
      expect(await AliyunNumberAuth.getVerifyToken(), 'mock_verify_token');
    });

    test('getMobileToken (bare)', () async {
      expect(await AliyunNumberAuth.getMobileToken(), 'mock_mobile_token');
    });

    test('getMobileToken with uiConfig and inline callbacks', () async {
      bool privacyFired = false;
      bool suspendFired = false;
      bool loginBtnFired = false;
      bool checkboxFired = false;
      bool authPageShownFired = false;
      const config = AliyunAuthUIConfig(loginBtnText: '立即登录', checkBoxChecked: true);
      final token = await AliyunNumberAuth.getMobileToken(
        uiConfig: config,
        onPrivacyLinkTap: (_, _) => privacyFired = true,
        onSuspendedDismiss: () => suspendFired = true,
        onLoginButtonTap: (_) => loginBtnFired = true,
        onCheckboxToggle: (_) => checkboxFired = true,
        onAuthPageShown: () => authPageShownFired = true,
      );
      expect(token, 'mock_mobile_token');
      expect(privacyFired, false);
      expect(suspendFired, false);
      expect(loginBtnFired, false);
      expect(checkboxFired, false);
      expect(authPageShownFired, false);
    });

    test('dismissLoginPage completes without error', () async {
      await expectLater(AliyunNumberAuth.dismissLoginPage(), completes);
    });

    test('setCheckboxChecked completes without error', () async {
      await expectLater(AliyunNumberAuth.setCheckboxChecked(true), completes);
    });

    test('isCheckboxChecked returns bool', () async {
      expect(await AliyunNumberAuth.isCheckboxChecked(), isA<bool>());
    });

    test('hideLoginLoading completes without error', () async {
      await expectLater(AliyunNumberAuth.hideLoginLoading(), completes);
    });

    test('closePrivacyAlertDialog completes without error', () async {
      await expectLater(AliyunNumberAuth.closePrivacyAlertDialog(), completes);
    });

    test('animatePrivacyText completes without error', () async {
      await expectLater(AliyunNumberAuth.animatePrivacyText(), completes);
    });

    test('animateCheckbox completes without error', () async {
      await expectLater(AliyunNumberAuth.animateCheckbox(), completes);
    });

    test('getSDKVersion returns string', () async {
      expect(await AliyunNumberAuth.getSDKVersion(), isA<String>());
    });

    group('AliyunAuthUIConfig', () {
      test('toMap excludes null fields', () {
        const cfg = AliyunAuthUIConfig();
        final map = cfg.toMap();
        expect(map.containsKey('backgroundColor'), false);
        expect(map.containsKey('navColor'), false);
        expect(map.containsKey('loginBtnBgColor'), false);
        expect(map.containsKey('privacyOne'), false);
        expect(map.containsKey('backgroundImageData'), false);
        expect(map.containsKey('privacyOperatorColor'), false);
        // Non-nullable defaults always present
        expect(map['dialogMode'], true);
        expect(map['loginBtnText'], '本机号码一键登录');
        expect(map['presentDirection'], 'bottom');
        expect(map['alertBarVisible'], false);
        expect(map['expandCheckboxTapScope'], false);
        expect(map['privacyOperatorUnderline'], false);
      });

      test('toMap includes nullable fields when set', () {
        const cfg = AliyunAuthUIConfig(
          loginBtnText: '测试',
          showLoginLoading: false,
          autoHideLoginLoading: false,
          privacyConectTexts: ['及', '、', '和'],
          privacyOperatorIndex: 1,
          alertBarVisible: true,
          alertTitle: '请确认',
          expandCheckboxTapScope: true,
          privacyOperatorUnderline: true,
          presentDirection: AliyunAuthPresentDirection.right,
        );
        final map = cfg.toMap();
        expect(map['loginBtnText'], '测试');
        expect(map['showLoginLoading'], false);
        expect(map['autoHideLoginLoading'], false);
        expect(map['privacyConectTexts'], ['及', '、', '和']);
        expect(map['privacyOperatorIndex'], 1);
        expect(map['alertBarVisible'], true);
        expect(map['alertTitle'], '请确认');
        expect(map['expandCheckboxTapScope'], true);
        expect(map['privacyOperatorUnderline'], true);
        expect(map['presentDirection'], 'right');
      });

      test('copyWith overrides specified fields', () {
        const base = AliyunAuthUIConfig(loginBtnText: 'A', checkBoxChecked: false);
        final updated = base.copyWith(
          loginBtnText: 'B',
          checkBoxChecked: true,
          presentDirection: AliyunAuthPresentDirection.left,
        );
        expect(updated.loginBtnText, 'B');
        expect(updated.checkBoxChecked, true);
        expect(updated.presentDirection, AliyunAuthPresentDirection.left);
        // Other fields unchanged
        expect(updated.dialogMode, base.dialogMode);
        expect(updated.cornerRadius, base.cornerRadius);
      });

      test('copyWith with no args returns equivalent config', () {
        const base = AliyunAuthUIConfig(dialogHeight: 400, loginBtnText: 'X');
        final copy = base.copyWith();
        expect(copy.dialogHeight, 400);
        expect(copy.loginBtnText, 'X');
      });

      test('copyWith can reset nullable fields back to null', () {
        // Regression: copyWith used to use `field ?? this.field`, which made
        // it impossible to clear a previously-set nullable field. Now each
        // nullable parameter defaults to a private sentinel, so passing the
        // literal `null` actually clears the field.
        const base = AliyunAuthUIConfig(
          sloganText: 'foo',
          privacyOperatorIndex: 2,
        );
        expect(base.sloganText, 'foo');
        final cleared = base.copyWith(sloganText: null);
        expect(cleared.sloganText, isNull);
        // Non-nullable fields with no override still preserved.
        expect(cleared.privacyOperatorIndex, 2);
      });

      test('numberFontSize < 16 trips an assert in debug', () {
        // Regression: iOS SDK silently ignores numberFontSize < 16, so we
        // surface it as an assertion failure in debug to catch the mistake
        // before it hits a device.
        expect(
          () => const AliyunAuthUIConfig(numberFontSize: 14).toMap(),
          throwsA(isA<AssertionError>()),
        );
        // >= 16 is fine.
        expect(
          const AliyunAuthUIConfig(numberFontSize: 16).toMap()['numberFontSize'],
          16,
        );
        // null is also fine.
        expect(
          const AliyunAuthUIConfig().toMap().containsKey('numberFontSize'),
          false,
        );
      });

      test('== and hashCode: identical configs are equal', () {
        const a = AliyunAuthUIConfig(
          loginBtnText: 'A',
          checkBoxChecked: true,
          privacyOne: ['Service', 'https://example.com/s'],
        );
        const b = AliyunAuthUIConfig(
          loginBtnText: 'A',
          checkBoxChecked: true,
          privacyOne: ['Service', 'https://example.com/s'],
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('== detects differing scalar field', () {
        const a = AliyunAuthUIConfig(loginBtnText: 'A');
        const b = AliyunAuthUIConfig(loginBtnText: 'B');
        expect(a, isNot(b));
      });

      test('== detects differing list field', () {
        const a = AliyunAuthUIConfig(privacyOne: ['x', 'http://x']);
        const b = AliyunAuthUIConfig(privacyOne: ['y', 'http://y']);
        expect(a, isNot(b));
      });

      test('== compares Uint8List by content, not reference', () {
        // Regression: Uint8List.== is identity-based by default; our custom
        // == must compare bytes so two equivalent images aren't treated as
        // different configs (which would cause needless rebuilds).
        final bytesA = Uint8List.fromList([1, 2, 3, 4]);
        final bytesB = Uint8List.fromList([1, 2, 3, 4]);
        expect(identical(bytesA, bytesB), false,
            reason: 'precondition: distinct instances');
        final cfgA = AliyunAuthUIConfig(logoImageData: bytesA);
        final cfgB = AliyunAuthUIConfig(logoImageData: bytesB);
        expect(cfgA, cfgB);
        // Differing content → not equal
        final bytesC = Uint8List.fromList([1, 2, 3, 5]);
        final cfgC = AliyunAuthUIConfig(logoImageData: bytesC);
        expect(cfgA, isNot(cfgC));
      });

      test('AliyunAuthPresentDirection enum values are serialised correctly', () {
        expect(AliyunAuthPresentDirection.bottom.name, 'bottom');
        expect(AliyunAuthPresentDirection.right.name, 'right');
        expect(AliyunAuthPresentDirection.top.name, 'top');
        expect(AliyunAuthPresentDirection.left.name, 'left');
      });
    });

    test('AliyunAuthCode constants are non-empty strings', () {
      expect(AliyunAuthCode.success, isNotEmpty);
      expect(AliyunAuthCode.userCancelled, isNotEmpty);
      expect(AliyunAuthCode.notInitialized, isNotEmpty);
      expect(AliyunAuthCode.busy, isNotEmpty);
      // Newly added codes
      expect(AliyunAuthCode.loginButtonTapped, '700002');
      expect(AliyunAuthCode.pageDealloced, '700020');
      expect(AliyunAuthCode.preloadInAuthPage, '600026');
    });

    group('AliyunAuthController', () {
      test('autoCheck transitions uninitialized → checking → available', () async {
        final c = AliyunAuthController();
        // Microtask in constructor → status flips to checking on next tick.
        expect(c.status, AliyunAuthStatus.uninitialized);
        await Future<void>.delayed(Duration.zero);
        // After the env check resolves, mock returns true → available.
        await Future<void>.delayed(Duration.zero);
        expect(c.status, AliyunAuthStatus.available);
        expect(c.canLogin, true);
        expect(c.lastError, isNull);
        c.dispose();
      });

      test('autoCheck=false leaves status at uninitialized', () async {
        final c = AliyunAuthController(autoCheck: false);
        await Future<void>.delayed(Duration.zero);
        expect(c.status, AliyunAuthStatus.uninitialized);
        c.dispose();
      });

      test('manual checkEnv resolves to available with mock', () async {
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        expect(c.status, AliyunAuthStatus.available);
        c.dispose();
      });

      test('login returns mock token and notifies listeners', () async {
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        final statusLog = <AliyunAuthStatus>[];
        c.addListener(() => statusLog.add(c.status));
        final token = await c.login();
        expect(token, 'mock_mobile_token');
        // busy → available
        expect(statusLog, [AliyunAuthStatus.busy, AliyunAuthStatus.available]);
        expect(c.lastError, isNull);
        c.dispose();
      });

      test('concurrent login throws busy', () async {
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        final f1 = c.login();
        await expectLater(
          c.login(),
          throwsA(isA<AliyunNumberAuthException>()
              .having((e) => e.code, 'code', AliyunAuthCode.busy)),
        );
        await f1;
        c.dispose();
      });

      test('login from uninitialized resolves status to available on success', () async {
        // Regression: previously `resumeStatus` defaulted to unavailable when
        // the pre-login status was anything but available, so a successful
        // login from uninitialized state would leave canLogin == false.
        final c = AliyunAuthController(autoCheck: false);
        expect(c.status, AliyunAuthStatus.uninitialized);
        final token = await c.login();
        expect(token, 'mock_mobile_token');
        expect(c.status, AliyunAuthStatus.available);
        expect(c.canLogin, true);
        c.dispose();
      });

      test('beginOperation clears lastError before next attempt', () async {
        // Regression: lastError used to linger from a previous failed attempt
        // until the next success, so observers reading lastError mid-busy
        // would see a stale error.
        //
        // Setup: swap to a throwing platform to seed a real lastError, then
        // swap back to the OK mock and verify the next checkEnv synchronously
        // clears it before any awaits.
        final throwing = _ThrowingMockPlatform();
        AliyunNumberAuthPlatform.instance = throwing;
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        expect(c.lastError, isNotNull, reason: 'first call should set lastError');
        expect(c.status, AliyunAuthStatus.unavailable);

        AliyunNumberAuthPlatform.instance = fakePlatform;
        final f = c.checkEnv();
        // Right after the synchronous prelude, status flipped and error cleared.
        expect(c.status, AliyunAuthStatus.checking);
        expect(c.lastError, isNull, reason: '_beginOperation should clear sync');
        await f;
        expect(c.status, AliyunAuthStatus.available);
        c.dispose();
      });

      test('login waits for in-flight checkEnv (no status flicker)', () async {
        // Regression: login() used to proceed while a checkEnv was in flight,
        // and the settling checkEnv would clobber the busy status with
        // available/unavailable mid-login — causing the UI to briefly show
        // canLogin=true while the auth page was still showing, allowing a
        // second login() to slip past the busy guard.
        final c = AliyunAuthController(autoCheck: false);
        final statusLog = <AliyunAuthStatus>[];
        c.addListener(() => statusLog.add(c.status));

        // Kick off checkEnv WITHOUT awaiting, then immediately await login.
        // The unawaited checkEnv must settle before login flips to busy.
        // ignore: unawaited_futures
        c.checkEnv();
        final token = await c.login();
        expect(token, 'mock_mobile_token');
        // Expected sequence: checking → available (from checkEnv) → busy
        // (from login's _beginOperation) → available (from login success).
        // Crucially: no `available` interleaved between busy and final
        // available — i.e., busy must not be clobbered.
        expect(statusLog, [
          AliyunAuthStatus.checking,
          AliyunAuthStatus.available,
          AliyunAuthStatus.busy,
          AliyunAuthStatus.available,
        ]);
        c.dispose();
      });

      test('login on disposed controller throws (no native call)', () async {
        // Regression: login() previously had no _disposed guard at the top,
        // so a disposed controller would still call AliyunNumberAuth.getMobileToken
        // — silently popping the auth page open for a user who had already
        // signalled they were done with the controller.
        //
        // In debug, the assert fires first (AssertionError); in release, the
        // explicit throw kicks in (AliyunNumberAuthException). Accept either.
        fakePlatform.checkEnvCallCount = 0;
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        c.dispose();
        await expectLater(
          c.login(),
          throwsA(anyOf(
            isA<AssertionError>(),
            isA<AliyunNumberAuthException>()
                .having((e) => e.code, 'code', AliyunAuthCode.cancelled),
          )),
        );
        // No additional platform call (only the prior checkEnv).
        expect(fakePlatform.checkEnvCallCount, 1);
      });

      test('dispose during in-flight login does not throw', () async {
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        final f = c.login();
        c.dispose();
        // The future still resolves; the controller just stops notifying.
        await expectLater(f, completes);
      });

      test('login error path notifies exactly twice (not thrice)', () async {
        // Regression: previously _setStatus + an explicit notifyListeners()
        // both fired on the error path, causing 3 notifications instead of
        // the expected 2 (busy begin + restore). Observers got double
        // rebuilds on every login error.
        AliyunNumberAuthPlatform.instance = _LoginErrorMockPlatform();
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        int notifyCount = 0;
        c.addListener(() => notifyCount++);
        await expectLater(c.login(), throwsA(isA<AliyunNumberAuthException>()));
        // Expected: 1 notify for available→busy + 1 for busy→prev = 2 total.
        expect(notifyCount, 2);
        AliyunNumberAuthPlatform.instance = fakePlatform;
        c.dispose();
      });

      test('lastError change notifies even when status stays the same',
          () async {
        // Regression: when checkEnv fails twice in a row, the second failure
        // would set _lastError but not notify because _status (=unavailable)
        // was unchanged from the first failure.
        AliyunNumberAuthPlatform.instance = _ThrowingMockPlatform();
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        final firstError = c.lastError;
        expect(c.status, AliyunAuthStatus.unavailable);
        expect(firstError, isNotNull);

        int notifyCount = 0;
        c.addListener(() => notifyCount++);
        await c.checkEnv();
        // Even though status stayed at unavailable, listeners must be told
        // because lastError (which observers might display) was cleared and
        // re-set during the operation.
        expect(notifyCount, greaterThanOrEqualTo(1));
        expect(c.status, AliyunAuthStatus.unavailable);
        expect(c.lastError, isNotNull);

        AliyunNumberAuthPlatform.instance = fakePlatform;
        c.dispose();
      });

      test('concurrent checkEnv calls are deduplicated', () async {
        // Regression: two simultaneous checkEnv calls used to each hit the
        // platform separately (and race the plugin BUSY retry). Now the
        // second caller awaits the in-flight Future.
        fakePlatform.checkEnvCallCount = 0;
        final c = AliyunAuthController(autoCheck: false);
        await Future.wait([c.checkEnv(), c.checkEnv(), c.checkEnv()]);
        expect(fakePlatform.checkEnvCallCount, 1,
            reason: 'three concurrent calls should result in one platform hit');
        c.dispose();
      });

      // ── autoDismissOnSuccess regression suite ──────────────────────────────
      // The feature dismisses the SDK auth page after a successful login but
      // only when the resolved config has `suspendDisMissVC: true` (without
      // it, the SDK auto-closes and an explicit dismiss would be a no-op at
      // best, double-close races at worst).

      test('autoDismissOnSuccess=true + suspendDisMissVC=true → dismisses '
           'with waitForCompletion=true', () async {
        fakePlatform.dismissLoginPageCallCount = 0;
        fakePlatform.lastDismissWaitForCompletion = null;
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        final token = await c.login(
          uiConfig: const AliyunAuthUIConfig(suspendDisMissVC: true),
          autoDismissOnSuccess: true,
        );
        expect(token, 'mock_mobile_token');
        expect(fakePlatform.dismissLoginPageCallCount, 1);
        // The whole point of auto-dismiss is letting the caller navigate
        // cleanly in onSuccess — that requires waiting for the iOS dismiss
        // animation to actually finish, not just be commanded.
        expect(fakePlatform.lastDismissWaitForCompletion, true);
        c.dispose();
      });

      test('autoDismissOnSuccess=true + suspendDisMissVC=false → does NOT '
           'dismiss (SDK auto-closes)', () async {
        // Without suspendDisMissVC the SDK closes the auth page itself.
        // Issuing an extra dismiss would race the SDK's own close.
        fakePlatform.dismissLoginPageCallCount = 0;
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        final token = await c.login(
          uiConfig: const AliyunAuthUIConfig(),  // suspendDisMissVC defaults false
          autoDismissOnSuccess: true,
        );
        expect(token, 'mock_mobile_token');
        expect(fakePlatform.dismissLoginPageCallCount, 0);
        c.dispose();
      });

      test('autoDismissOnSuccess=false (default) → never dismisses, even with '
           'suspendDisMissVC=true', () async {
        // Backward-compat path: existing callers that set suspendDisMissVC
        // and dismiss manually shouldn't get a surprise extra dismiss.
        fakePlatform.dismissLoginPageCallCount = 0;
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        final token = await c.login(
          uiConfig: const AliyunAuthUIConfig(suspendDisMissVC: true),
        );
        expect(token, 'mock_mobile_token');
        expect(fakePlatform.dismissLoginPageCallCount, 0);
        c.dispose();
      });

      test('dismiss failure during autoDismissOnSuccess does not swallow '
           'the token', () async {
        // Auth page may already be gone, plugin detaching, etc. — the
        // dismiss attempt is best-effort and must not block the token
        // from reaching the caller.
        fakePlatform.dismissLoginPageCallCount = 0;
        fakePlatform.dismissError = const AliyunNumberAuthException(
          AliyunAuthCode.failed, 'mock dismiss failed');
        final c = AliyunAuthController(autoCheck: false);
        await c.checkEnv();
        final token = await c.login(
          uiConfig: const AliyunAuthUIConfig(suspendDisMissVC: true),
          autoDismissOnSuccess: true,
        );
        expect(token, 'mock_mobile_token');
        expect(fakePlatform.dismissLoginPageCallCount, 1);
        // Reset for any subsequent tests in the group.
        fakePlatform.dismissError = null;
        c.dispose();
      });
    });

    group('AliyunAuthWidget', () {
      testWidgets('asserts when controller prop is hot-swapped', (tester) async {
        final ctrl1 = AliyunAuthController(autoCheck: false);
        final ctrl2 = AliyunAuthController(autoCheck: false);
        await tester.pumpWidget(MaterialApp(
          home: AliyunAuthWidget(
            controller: ctrl1,
            onSuccess: (_) {},
            builder: (_, _, _) => const SizedBox.shrink(),
          ),
        ));
        // Rebuild with a different controller — must trip the debug assert.
        await tester.pumpWidget(MaterialApp(
          home: AliyunAuthWidget(
            controller: ctrl2,
            onSuccess: (_) {},
            builder: (_, _, _) => const SizedBox.shrink(),
          ),
        ));
        expect(tester.takeException(), isA<AssertionError>());
        ctrl1.dispose();
        ctrl2.dispose();
      });
    });
  });
}
