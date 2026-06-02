import 'package:flutter/widgets.dart';

import 'aliyun_number_auth.dart';

/// Builder callback for [AliyunAuthWidget].
///
/// Parameters:
/// - [status] — current controller status. See [AliyunAuthStatus] for the
///   full lifecycle. Use this to render distinct UI for `checking`,
///   `available`, `unavailable`, and `busy`.
/// - [login] — non-null only when `status == AliyunAuthStatus.available`.
///   Pass to a button's `onPressed`; pressing it triggers the one-key login
///   flow and `onSuccess` / `onError` will fire on completion.
typedef AliyunAuthBuilder = Widget Function(
  BuildContext context,
  AliyunAuthStatus status,
  VoidCallback? login,
);

/// A convenience widget that wires an [AliyunAuthController] into a builder.
///
/// For simple cases (one login button on a page) this widget owns its own
/// controller and there's nothing else to manage. For more complex cases —
/// triggering login from outside the builder, sharing state across multiple
/// surfaces, reacting to availability changes from elsewhere in the tree —
/// pass an external [controller] you create and dispose yourself, or skip
/// this widget entirely and use [AliyunAuthController] directly with a
/// [ListenableBuilder].
///
/// Example:
///
/// ```dart
/// AliyunAuthWidget(
///   onSuccess: (token) => myBackend.exchange(token),
///   onError: (e) {
///     if (e.code == AliyunAuthCode.userCancelled) return;
///     showError(e.message);
///   },
///   builder: (context, status, login) => ElevatedButton(
///     onPressed: login,
///     child: Text(switch (status) {
///       AliyunAuthStatus.checking => '检测中…',
///       AliyunAuthStatus.available => '一键登录',
///       AliyunAuthStatus.busy => '登录中…',
///       _ => '短信登录',
///     }),
///   ),
/// );
/// ```
class AliyunAuthWidget extends StatefulWidget {
  const AliyunAuthWidget({
    super.key,
    required this.builder,
    required this.onSuccess,
    this.onError,
    this.controller,
    this.uiConfig = const AliyunAuthUIConfig(),
    this.timeout = const Duration(seconds: 10),
    this.onPrivacyLinkTap,
    this.onSuspendedDismiss,
    this.onLoginButtonTap,
    this.onCheckboxToggle,
    this.onAuthPageShown,
  });

  final AliyunAuthBuilder builder;

  /// Called with the login token after a successful [AliyunAuthController.login].
  final ValueChanged<String> onSuccess;

  /// Called when login fails or the user cancels.
  final ValueChanged<AliyunNumberAuthException>? onError;

  /// External controller. If `null`, the widget creates and disposes an
  /// internal one.
  ///
  /// **Hot-swap is not supported** — changing this field after the widget is
  /// mounted has no effect. If you need to swap, give the widget a new [Key].
  final AliyunAuthController? controller;

  /// Default UI config — only used when [controller] is `null` (i.e. the
  /// widget owns the controller). Otherwise the external controller's
  /// `uiConfig` is used.
  final AliyunAuthUIConfig uiConfig;

  /// Default timeout — only used when [controller] is `null`.
  final Duration timeout;

  // ── Per-login event callbacks (forwarded to AliyunAuthController.login) ──

  /// Called when the user taps a protocol link and
  /// [AliyunAuthUIConfig.privacyVCIsCustomized] is `true`.
  final void Function(String url, String name)? onPrivacyLinkTap;

  /// Called when the user taps back while
  /// [AliyunAuthUIConfig.suspendDisMissVC] is `true`. Call
  /// [AliyunNumberAuth.dismissLoginPage()] to close the page.
  final VoidCallback? onSuspendedDismiss;

  /// Called every time the user taps the one-key-login button. [isChecked]
  /// reflects the checkbox state at the moment of the tap; when `false` the
  /// SDK does not fetch a token and the page stays open.
  final void Function(bool isChecked)? onLoginButtonTap;

  /// Called when the user toggles the privacy checkbox. [isChecked] is the
  /// **new** state. The SDK's own login button cannot be dynamically
  /// restyled / disabled from Flutter.
  final void Function(bool isChecked)? onCheckboxToggle;

  /// Called once when the SDK authorization page is successfully shown.
  /// Useful for dismissing your own loading indicator.
  final VoidCallback? onAuthPageShown;

  @override
  State<AliyunAuthWidget> createState() => _AliyunAuthWidgetState();
}

class _AliyunAuthWidgetState extends State<AliyunAuthWidget> {
  late final AliyunAuthController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = AliyunAuthController(
        uiConfig: widget.uiConfig,
        timeout: widget.timeout,
      );
      _ownsController = true;
    }
    _controller.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AliyunAuthWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Hot-swap of `controller` is intentionally unsupported (see the
    // doc on the field). In debug mode, fail loudly so devs catch the
    // mistake rather than silently using the old controller forever.
    assert(
      widget.controller == oldWidget.controller,
      'AliyunAuthWidget does not support hot-swapping the controller. '
      'If you need to switch controllers, give the widget a new Key so it '
      'rebuilds from scratch.',
    );
    // For a widget-owned controller, mirror uiConfig/timeout from the
    // current widget so a parent setState with new defaults takes effect on
    // the next login() call. AliyunAuthUIConfig implements value-equality, so
    // assigning an equal instance is harmless; this assignment only matters
    // when the parent actually changed the config.
    if (_ownsController) {
      _controller.uiConfig = widget.uiConfig;
      _controller.timeout = widget.timeout;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    try {
      final token = await _controller.login(
        onPrivacyLinkTap: widget.onPrivacyLinkTap,
        onSuspendedDismiss: widget.onSuspendedDismiss,
        onLoginButtonTap: widget.onLoginButtonTap,
        onCheckboxToggle: widget.onCheckboxToggle,
        onAuthPageShown: widget.onAuthPageShown,
      );
      if (!mounted) return;
      widget.onSuccess(token);
    } on AliyunNumberAuthException catch (e) {
      if (!mounted) return;
      widget.onError?.call(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      _controller.status,
      _controller.canLogin ? _login : null,
    );
  }
}
