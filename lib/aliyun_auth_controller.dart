import 'dart:async';

import 'package:flutter/foundation.dart';

import 'aliyun_number_auth.dart';

/// Lifecycle state of an [AliyunAuthController].
///
/// Transitions:
/// ```
///   uninitialized ──checkEnv()──► checking ──┬─► available
///                                             └─► unavailable
///
///   {uninitialized, available, unavailable}
///       │
///       └──login()──► busy ──┬─► available   (login succeeded — env proven OK)
///                             └─► <prev>      (login failed/cancelled — env
///                                              presumed unchanged; check
///                                              `lastError` for the code)
/// ```
///
/// `login()` can be called from any non-`busy` state — a successful login
/// itself proves the environment is available, so no prior [checkEnv] is
/// required (though calling one first lets you render a meaningful initial UI).
enum AliyunAuthStatus {
  /// [AliyunAuthController.checkEnv] has not run yet.
  uninitialized,

  /// Environment check in flight.
  checking,

  /// One-key login is supported on this device/network.
  available,

  /// One-key login is not supported (no SIM, cellular off, unsupported carrier, etc.).
  unavailable,

  /// A login attempt is in flight (auth page is shown / token request pending).
  busy,
}

/// Controller for the Aliyun one-key login flow.
///
/// Holds [status] and [lastError], notifies listeners on change. The
/// recommended way to build login UIs that need to react to availability or
/// progress without nesting inside a builder widget.
///
/// Typical use with `ListenableBuilder`:
///
/// ```dart
/// final controller = AliyunAuthController();
///
/// ListenableBuilder(
///   listenable: controller,
///   builder: (_, __) => ElevatedButton(
///     onPressed: controller.status == AliyunAuthStatus.available
///       ? () async {
///           try {
///             final token = await controller.login();
///             await myBackend.exchange(token);
///           } on AliyunNumberAuthException catch (e) {
///             if (e.code != AliyunAuthCode.userCancelled) showError(e);
///           }
///         }
///       : null,
///     child: Text(switch (controller.status) {
///       AliyunAuthStatus.checking => '检测中…',
///       AliyunAuthStatus.available => '一键登录',
///       AliyunAuthStatus.busy => '登录中…',
///       _ => '短信登录',
///     }),
///   ),
/// );
/// ```
class AliyunAuthController extends ChangeNotifier {
  AliyunAuthController({
    this.uiConfig = const AliyunAuthUIConfig(),
    this.timeout = const Duration(seconds: 10),
    bool autoCheck = true,
  }) {
    if (autoCheck) {
      // Defer so listeners attached right after construction still see the
      // checking → available transition.
      Future.microtask(checkEnv);
    }
  }

  /// Default UI configuration used by [login] when no override is passed.
  /// Mutate freely; the next [login] call picks up the new value.
  AliyunAuthUIConfig uiConfig;

  /// Default timeout used by [login] when no override is passed.
  /// Mutate freely; the next [login] call picks up the new value.
  Duration timeout;

  AliyunAuthStatus _status = AliyunAuthStatus.uninitialized;

  /// Current lifecycle state. Listen for changes via [addListener].
  AliyunAuthStatus get status => _status;

  AliyunNumberAuthException? _lastError;

  /// The most recent error from [checkEnv] or [login], or `null` if either:
  /// - no operation has run yet, or
  /// - the most recent successful operation cleared it, or
  /// - a new operation is currently in flight (cleared atomically at start)
  ///
  /// Always read together with [status] for a coherent snapshot — listeners
  /// are notified once for both fields together.
  AliyunNumberAuthException? get lastError => _lastError;

  bool _disposed = false;
  Future<void>? _pendingCheckEnv;

  /// Whether a login attempt can be started right now.
  ///
  /// Equivalent to `status == AliyunAuthStatus.available`. Convenience for
  /// wiring directly to `onPressed`.
  bool get canLogin => _status == AliyunAuthStatus.available;

  /// Runs an environment check and updates [status] accordingly.
  ///
  /// Safe to call repeatedly. Concurrent calls are deduplicated — the second
  /// caller awaits the same in-flight check. Recovers from a transient `BUSY`
  /// race (e.g. another plugin caller also checking) by retrying once after
  /// 600ms.
  ///
  /// **No-op when [status] is [AliyunAuthStatus.busy]** — a login is in
  /// flight, and an env check while busy would race the plugin's exclusive
  /// lock. Returns immediately with the future already resolved; [status]
  /// is unchanged. Re-call after the login future settles if you need a
  /// fresh check.
  Future<void> checkEnv() {
    if (_disposed) return Future.value();
    if (_status == AliyunAuthStatus.busy) return Future.value();
    // Dedupe: if a check is already in flight, return its future.
    final inFlight = _pendingCheckEnv;
    if (inFlight != null) return inFlight;
    _beginOperation(AliyunAuthStatus.checking);
    final future = _checkEnvOnce(isRetry: false).whenComplete(() {
      _pendingCheckEnv = null;
    });
    _pendingCheckEnv = future;
    return future;
  }

  Future<void> _checkEnvOnce({required bool isRetry}) async {
    try {
      final ok = await AliyunNumberAuth.checkEnvAvailable();
      if (_disposed) return;
      _setStatusAndError(
        ok ? AliyunAuthStatus.available : AliyunAuthStatus.unavailable,
        null,
      );
    } on AliyunNumberAuthException catch (e) {
      if (_disposed) return;
      if (e.code == AliyunAuthCode.busy && !isRetry) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (_disposed) return;
        return _checkEnvOnce(isRetry: true);
      }
      _setStatusAndError(AliyunAuthStatus.unavailable, e);
    } catch (_) {
      if (_disposed) return;
      _setStatusAndError(AliyunAuthStatus.unavailable, null);
    }
  }

  /// Starts the one-key login flow. Resolves with the login token on success.
  ///
  /// Throws [AliyunNumberAuthException] on failure or user cancellation
  /// ([AliyunAuthCode.userCancelled] / [AliyunAuthCode.userSwitched] /
  /// [AliyunAuthCode.timeout] etc.).
  ///
  /// While the call is in flight, [status] is [AliyunAuthStatus.busy]. On
  /// success [status] becomes [AliyunAuthStatus.available] (the success itself
  /// proves the env is available). On error [status] is restored to whatever
  /// it was before the call — most errors are about user choice or transient
  /// state, not env loss; if you want to be certain after an error, call
  /// [checkEnv] again. Concurrent calls throw [AliyunAuthCode.busy].
  ///
  /// If an env check is in flight when `login()` is called, the call
  /// transparently awaits it before starting — letting you safely invoke
  /// login right after constructing the controller with `autoCheck: true`
  /// without racing the env check's state update.
  ///
  /// When [autoDismissOnSuccess] is `true` AND the resolved
  /// [AliyunAuthUIConfig.suspendDisMissVC] is `true`, the SDK auth page is
  /// dismissed before the returned Future resolves. Without this, callers
  /// using `suspendDisMissVC` would have to manually call
  /// [dismissLoginPage] after every successful login — easy to forget, and
  /// the native auth window can briefly cover the next route on iOS if you
  /// navigate before it's gone. Dismiss errors are swallowed; the token is
  /// always returned. Defaults to `false` for backward compatibility.
  ///
  /// All callback / config parameters override the controller's defaults for
  /// this single call.
  Future<String> login({
    AliyunAuthUIConfig? uiConfig,
    Duration? timeout,
    bool autoDismissOnSuccess = false,
    void Function(String url, String name)? onPrivacyLinkTap,
    VoidCallback? onSuspendedDismiss,
    void Function(bool isChecked)? onLoginButtonTap,
    void Function(bool isChecked)? onCheckboxToggle,
    VoidCallback? onAuthPageShown,
  }) async {
    assert(!_disposed, 'login() called on a disposed AliyunAuthController');
    if (_disposed) {
      // Prod fallback: don't show the auth page after the user has signalled
      // they're done with this controller.
      throw const AliyunNumberAuthException(
        AliyunAuthCode.cancelled,
        'controller has been disposed',
      );
    }
    // If an env check is in flight, wait for it to settle so we don't race
    // its terminal _setStatusAndError against our own. Without this, the
    // settling check would clobber `busy` with `available`/`unavailable`
    // mid-login, causing UI flicker and re-entrancy bugs.
    final pendingCheck = _pendingCheckEnv;
    if (pendingCheck != null) {
      await pendingCheck;
      if (_disposed) {
        throw const AliyunNumberAuthException(
          AliyunAuthCode.cancelled,
          'controller disposed during env check',
        );
      }
    }
    if (_status == AliyunAuthStatus.busy) {
      throw const AliyunNumberAuthException(
        AliyunAuthCode.busy,
        'login already in progress',
      );
    }
    final prevStatus = _status;
    final effectiveConfig = uiConfig ?? this.uiConfig;
    _beginOperation(AliyunAuthStatus.busy);
    try {
      final token = await AliyunNumberAuth.getMobileToken(
        timeout: timeout ?? this.timeout,
        uiConfig: effectiveConfig,
        onPrivacyLinkTap: onPrivacyLinkTap,
        onSuspendedDismiss: onSuspendedDismiss,
        onLoginButtonTap: onLoginButtonTap,
        onCheckboxToggle: onCheckboxToggle,
        onAuthPageShown: onAuthPageShown,
      );
      // Without suspendDisMissVC the SDK already auto-closes; only dismiss
      // explicitly when the caller suppressed that auto-close.
      if (autoDismissOnSuccess && effectiveConfig.suspendDisMissVC) {
        try {
          // waitForCompletion: true so the Future doesn't resolve until iOS's
          // dismiss animation finishes — the whole point of auto-dismiss is
          // to let the caller navigate cleanly in onSuccess, which means the
          // auth page must actually be gone (not just commanded to dismiss).
          await AliyunNumberAuth.dismissLoginPage(waitForCompletion: true);
        } catch (_) {
          // Auth page may already be gone, plugin detaching, etc. — swallow
          // so the token still reaches the caller.
        }
      }
      // Success proves env is available — force status regardless of prior.
      _setStatusAndError(AliyunAuthStatus.available, null);
      return token;
    } on AliyunNumberAuthException catch (e) {
      // Restore prev — cancel / switch / timeout don't imply env change.
      // Caller can re-run checkEnv() if they want certainty.
      _setStatusAndError(prevStatus, e);
      rethrow;
    } catch (_) {
      _setStatusAndError(prevStatus, null);
      rethrow;
    }
  }

  /// Programmatically dismisses the SDK authorization page.
  ///
  /// Same semantics as [AliyunNumberAuth.dismissLoginPage]. The pending
  /// [login] future will reject with [AliyunAuthCode.cancelled].
  Future<void> dismissLoginPage({
    bool animated = true,
    bool waitForCompletion = false,
  }) {
    return AliyunNumberAuth.dismissLoginPage(
      animated: animated,
      waitForCompletion: waitForCompletion,
    );
  }

  /// Transitions to [newStatus] and atomically clears [lastError], notifying
  /// listeners once if either field changed. Use at the start of operations
  /// that haven't produced a result yet (the previous error is no longer
  /// relevant).
  void _beginOperation(AliyunAuthStatus newStatus) =>
      _setStatusAndError(newStatus, null);

  /// Atomically sets [status] and [lastError] together, notifying once if
  /// either field changed. Use to avoid double notifications and to ensure
  /// listeners always see a coherent snapshot.
  void _setStatusAndError(
    AliyunAuthStatus newStatus,
    AliyunNumberAuthException? newError,
  ) {
    if (_disposed) return;
    final changed = _status != newStatus || _lastError != newError;
    _status = newStatus;
    _lastError = newError;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // If a login is in flight, the SDK auth page is currently on screen.
    // Without an explicit dismiss the user would be stuck on a page whose
    // result handler has been torn down — onSuccess/onError can never fire.
    // Fire-and-forget; we're going away regardless of the outcome.
    if (_status == AliyunAuthStatus.busy) {
      unawaited(AliyunNumberAuth.dismissLoginPage().catchError((_) {}));
    }
    super.dispose();
  }
}
