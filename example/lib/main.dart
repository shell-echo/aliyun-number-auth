import 'package:aliyun_number_auth/aliyun_number_auth.dart';
import 'package:flutter/material.dart';

const _androidSk = 'YOUR_ANDROID_SK';
const _iosSk = 'YOUR_IOS_SK';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Initializing…';
  bool _verifyEnvAvailable = false;
  bool _loginEnvAvailable = false;
  String? _verifyToken;
  String? _mobileToken;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    // 1. Init — must be called once before any other method.
    try {
      await AliyunNumberAuth.init(_androidSk, _iosSk);
    } on AliyunNumberAuthException catch (e) {
      _updateStatus('Init failed: ${e.code}');
      return;
    }

    // 2. Check environments sequentially — checkEnvAvailable holds an
    //    exclusive lock and cannot run concurrently with itself.
    final verifyAvailable = await AliyunNumberAuth.checkEnvAvailable(
      type: AliyunAuthType.verifyToken,
    );
    final loginAvailable = await AliyunNumberAuth.checkEnvAvailable(
      type: AliyunAuthType.loginToken,
    );

    if (!mounted) return;

    // 3. Pre-warm each flow that is available (fire-and-forget).
    if (verifyAvailable) AliyunNumberAuth.preload();
    if (loginAvailable) AliyunNumberAuth.preloadLogin();

    setState(() {
      _verifyEnvAvailable = verifyAvailable;
      _loginEnvAvailable = loginAvailable;
      _status = 'Ready';
    });
  }

  // ── Verify token flow ──────────────────────────────────────────────────────

  Future<void> _fetchVerifyToken() async {
    _updateStatus('Fetching verify token…');
    try {
      final token = await AliyunNumberAuth.getVerifyToken();
      if (!mounted) return;
      setState(() {
        _verifyToken = token;
        _status = 'Verify token received';
      });
    } on AliyunNumberAuthException catch (e) {
      _updateStatus('Error: ${e.code} ${e.message ?? ''}');
    }
  }

  // ── Login token flow ───────────────────────────────────────────────────────

  Future<void> _fetchMobileToken() async {
    _updateStatus('Opening auth page…');
    try {
      final token = await AliyunNumberAuth.getMobileToken();
      if (!mounted) return;
      setState(() {
        _mobileToken = token;
        _status = 'Mobile token received';
      });
    } on AliyunNumberAuthException catch (e) {
      // 700000 — user cancelled (tapped back button)
      // 700001 — user chose other login method
      _updateStatus('${e.code}: ${e.message ?? ''}');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _updateStatus(String s) {
    if (!mounted) return;
    setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('aliyun_number_auth example')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              // Verify token (本机号码校验)
              ElevatedButton(
                onPressed: _verifyEnvAvailable ? _fetchVerifyToken : null,
                child: const Text('Get Verify Token（号码校验）'),
              ),
              if (_verifyToken != null) ...[
                const SizedBox(height: 12),
                SelectableText(_verifyToken!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              // Login token (一键登录)
              ElevatedButton(
                onPressed: _loginEnvAvailable ? _fetchMobileToken : null,
                child: const Text('Get Mobile Token（一键登录）'),
              ),
              if (_mobileToken != null) ...[
                const SizedBox(height: 12),
                SelectableText(_mobileToken!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
