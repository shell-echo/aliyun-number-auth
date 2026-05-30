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
  bool _envAvailable = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> _setup() async {
    try {
      await AliyunNumberAuth.init(_androidSk, _iosSk);
    } on AliyunNumberAuthException catch (e) {
      // Platform messages may fail, so we use a try/catch AliyunNumberAuthException.
      _updateStatus('Init failed: ${e.code}');
      return;
    }

    final available = await AliyunNumberAuth.checkEnvAvailable();

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    if (available) AliyunNumberAuth.preload();

    setState(() {
      _envAvailable = available;
      _status = available ? 'Ready' : 'Cellular network not supported';
    });
  }

  Future<void> _fetchToken() async {
    _updateStatus('Fetching token…');
    try {
      final token = await AliyunNumberAuth.getVerifyToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        _status = 'Token received';
      });
    } on AliyunNumberAuthException catch (e) {
      _updateStatus('Error: ${e.code} ${e.message ?? ''}');
    }
  }

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
              ElevatedButton(
                onPressed: _envAvailable ? _fetchToken : null,
                child: const Text('Get Verify Token'),
              ),
              if (_token != null) ...[
                const SizedBox(height: 24),
                SelectableText(_token!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
