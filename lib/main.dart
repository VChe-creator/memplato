import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'termux_bridge.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(const MemPlatoApp());
}

class MemPlatoApp extends StatelessWidget {
  const MemPlatoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MemPlato',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF01696F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale?.languageCode == 'uk') return const Locale('uk');
        return const Locale('en');
      },
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _checkingSystem = false;
  bool _termuxInstalled = false;
  bool _hasPermission = false;
  bool _allowExternalApps = false;
  bool _waitingForTermuxRestart = false;
  bool _serverOnline = false;
  bool _checkingServer = false;
  bool _installing = false;
  bool _batteryNotifSent = false;
  String _serverUrl = '';
  String _statusText = '';
  String _installLog = '';
  String _relayUrl = '';
  String _userId = '';
  Timer? _timer;
  Timer? _permissionCheckTimer;


  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = _serverUrl;
    _checkNotificationsEnabled();

    // СТАЛО:
    _loadUserId().then((uid) async {
      if (uid.isNotEmpty && mounted) {
        // Навіть якщо userId є — перевіряємо чи Termux реально встановлений
        final installed = await TermuxBridge.isTermuxInstalled();
        if (!installed) {
          // Termux видалено — скидаємо все і показуємо екран встановлення
          await _clearUserId(); // очищаємо збережений userId
          if (mounted) _checkSystem();
          return;
        }
        // Termux є — підключаємось як раніше
        setState(() {
          _checkingSystem = false;
          _userId = uid;
          _serverUrl = 'https://relay.memplato.com/u/$uid/status';
          _relayUrl = 'https://relay.memplato.com/u/$uid/mcp';
          _urlController.text = _relayUrl;
          _termuxInstalled = true;
          _hasPermission = true;
          _allowExternalApps = true;
        });
        _startServerChecking();
      } else {
        if (mounted) _checkSystem();
      }
    });
  }

  Future<void> _checkNotificationsEnabled() async {
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    final enabled = await TermuxBridge.areNotificationsEnabled();
    if (!enabled) {
      _showEnableNotificationsDialog();
    }
  }

  void _showEnableNotificationsDialog() {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1B19),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l.notifDialogTitle,
          style: const TextStyle(color: Color(0xFFCDCCCA), fontSize: 18),
        ),
        content: Text(
          l.notifDialogDesc,
          style: const TextStyle(color: Color(0xFF797876), fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l.btnLater,
              style: const TextStyle(color: Color(0xFF797876)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await TermuxBridge.openNotificationSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF01696F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(l.btnEnableNotif),
          ),
        ],
      ),
    );
  }

  Future<void> _checkSystem() async {
    setState(() => _checkingSystem = true);
    final installed = await TermuxBridge.isTermuxInstalled();
    final permission =
    installed ? await TermuxBridge.hasRunCommandPermission() : false;
    setState(() {
      _termuxInstalled = installed;
      _hasPermission = permission;
      _checkingSystem = false;
    });
    if (installed && permission) _startServerChecking();
  }

  void _startServerChecking() {
    _timer?.cancel();
    _checkServer();
    _timer =
        Timer.periodic(const Duration(seconds: 15), (_) => _checkServer());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _permissionCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkServer() async {
    if (_serverUrl.isEmpty) return;

    setState(() => _checkingServer = true);
    try {
      String checkUrl;
      if (_userId.isNotEmpty) {
        checkUrl = 'https://relay.memplato.com/u/$_userId/health';
      } else if (_serverUrl.contains('/mcp')) {
        // Захист: якщо в _serverUrl потрапив SSE endpoint — беремо status
        final base = _serverUrl.replaceAll('/mcp', '');
        checkUrl = '$base/status';
      } else {
        checkUrl = _serverUrl.endsWith('/') ? _serverUrl : '$_serverUrl/';
      }

      final uri = Uri.parse(checkUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Якщо є userId — перевіряємо поле online
        final isOnline = _userId.isNotEmpty
            ? (data['server'] == true)
            : true;
        setState(() {
          _serverOnline = isOnline;
          _statusText = isOnline
              ? AppLocalizations.of(context)!.statusOnline
              : AppLocalizations.of(context)!.statusOffline;
          _checkingServer = false;
        });
      } else {
        _setOffline();
      }
    } catch (_) {
      _setOffline();
    }
  }

  void _setOffline() {
    setState(() {
      _serverOnline = false;
      _statusText = AppLocalizations.of(context)!.statusOffline;
      _checkingServer = false;
    });
  }

  Future<void> _saveUserId(String uid) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/user_id.txt');
    await file.writeAsString(uid);
  }

    Future<String> _loadUserId() async {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/user_id.txt');
        if (await file.exists()) return (await file.readAsString()).trim();
      } catch (_) {}
      return '';
    }

// ↓ СЮДИ ВСТАВЛЯЙ ↓
    Future<void> _clearUserId() async {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/user_id.txt');
      if (await file.exists()) await file.delete();
    }

  // КРОК 1 — пояснення + GitHub
  Future<void> _downloadTermux() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (context) => const _DownloadTermuxDialog(),
    );
  }

  // КРОК 2 — дати дозвіл
  Future<void> _givePermission() async {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1B19),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF393836)),
        ),
        title: Text(
          l.permDialogTitle,
          style: const TextStyle(color: Color(0xFFCDCCCA), fontSize: 18),
        ),
        content: Text(
          l.permDialogDesc,
          style: const TextStyle(
            color: Color(0xFF797876),
            height: 1.6,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l.btnCancel,
              style: const TextStyle(color: Color(0xFF797876)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await TermuxBridge.openAppSettings();
            },
            child: Text(
              l.btnOpenSettings,
              style: const TextStyle(
                color: Color(0xFF4F98A3),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await _checkSystem();
  }

  // КРОК 2.5 — allow-external-apps
  Future<void> _showAllowExternalAppsDialog() async {
    if (!mounted) return;
    const command =
        'mkdir -p ~/.termux && echo "allow-external-apps=true" >> ~/.termux/termux.properties';

    final l = AppLocalizations.of(context)!;
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1B19),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF393836)),
        ),
        title: Text(
          l.termuxSetupTitle,
          style: const TextStyle(color: Color(0xFFCDCCCA), fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.termuxSetupDesc,
              style: const TextStyle(color: Color(0xFF797876), height: 1.6, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4F98A3)),
              ),
              child: const Text(
                command,
                style: TextStyle(
                  color: Color(0xFF4F98A3),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.termuxExitNote,
              style: const TextStyle(color: Color(0xFF797876), height: 1.5, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.commandCopied),
                  duration: const Duration(seconds: 2),
                  backgroundColor: const Color(0xFF01696F),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16, color: Color(0xFF4F98A3)),
            label: Text(l.btnCopyCommand,
                style: const TextStyle(color: Color(0xFF4F98A3))),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await TermuxBridge.openTermux();
            },
            icon: const Icon(Icons.terminal, size: 16, color: Colors.white),
            label: Text(l.btnOpenTermux,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    // Після закриття діалогу — показуємо кнопку "Перезапустити Termux"
    if (mounted) {
      setState(() => _waitingForTermuxRestart = true);
    }
  }

  // Перезапуск Termux + автоперевірка дозволу
  Future<void> _restartTermux() async {
    // Крок 1 — відкриваємо Termux (щоб закрити через шторку)
    await TermuxBridge.openTermux();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.exitTermuxHint),
        duration: const Duration(seconds: 6),
        backgroundColor: const Color(0xFF393836),
      ),
    );
  }

  Future<void> _launchTermuxAndWait() async {
    // Запускаємо Termux
    await TermuxBridge.openTermux();

    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _waitingForTermuxRestart = false;
      _installLog = l.logWaitingTermux;
      _installing = true;
    });

    // Чекаємо 3 секунди щоб Termux встиг запуститись
    await Future.delayed(const Duration(seconds: 3));

    // Починаємо перевіряти дозвіл кожні 3 секунди
    _permissionCheckTimer?.cancel();
    _permissionCheckTimer = Timer.periodic(
      const Duration(seconds: 3),
          (timer) async {
        final hasPermission = await TermuxBridge.hasRunCommandPermission();
        if (hasPermission && mounted) {
          timer.cancel();
          setState(() {
            _allowExternalApps = true;
            _waitingForTermuxRestart = false;
            _installing = false;
            _installLog = '';
          });
        }
      },
    );
  }

  // ── ЦЕЙ МЕТОД ДОДАЄШ ТУТ, ПЕРЕД _installAndStart() ──
  Future<void> _copyAssetToTermux(String assetPath, String termuxDest) async {
    final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
    const chunkSize = 50000; // ~150 KB — безпечно для Intent
    final totalChunks = (bytes.length / chunkSize).ceil();

    // Очищаємо файл перед записом
    await TermuxBridge.runCommand('rm -f $termuxDest && touch $termuxDest');
    await Future.delayed(const Duration(milliseconds: 500));

    for (int i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(start, end);
      final b64 = base64Encode(chunk);
      // >> додає до файлу (append)
      await TermuxBridge.runCommand('echo "$b64" | base64 -d >> $termuxDest');
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // КРОК 3 — встановити і запустити
  Future<void> _installAndStart() async {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _installing = true;
      _installLog = l.logStarting;
    });
    _batteryNotifSent = false;  // ← ДОДАЙ ЦЕЙ РЯДОК

    try {
      // Слухач broadcast від bash-скрипта
      TermuxBridge.channel.setMethodCallHandler((call) async {
        if (call.method == 'onInstallStatus') {
          final args = call.arguments as Map? ?? {};
          final step = args['step'] as String? ?? '';
          if (!mounted) return;

          String log = _installLog;
          if (step == 'STEP:pkg') {
            log = l.logStep1pkg;
            if (!_batteryNotifSent) {
              _batteryNotifSent = true;
              await TermuxBridge.sendBatteryNotification();
            }
          } else if (step == 'STEP:wheels') {
            log = l.logStep2wheels;
          } else if (step == 'STEP:pip') {
            log = l.logStep2pip;
          } else if (step == 'PIP:OK') {
            log = l.logPipOk;
          } else if (step == 'MCP:OK') {
            log = l.logMcpOk;
          } else if (step == 'STEP:copy') {
            log = l.logStep3copy;
          } else if (step == 'STEP:model') {
            log = l.logStep3model;
          } else if (step == 'STEP:start') {
            log = l.logStep4start;
          } else if (step == 'STEP:tunnel') {
            log = l.logStepTunnel;
          } else if (step == 'TUNNEL:started') {
            final uid = args['uid'] as String? ?? '';
            if (uid.isNotEmpty) {
              final relayBase = 'https://relay.memplato.com/u/$uid';
              setState(() {
                _userId = uid;
                _relayUrl = '$relayBase/mcp';
                _serverUrl = '$relayBase/health';
                _urlController.text = '$relayBase/mcp';
              });
              await _saveUserId(uid);
            }
            log = l.logTunnelStarted;
          } else if (step == 'ERROR:no_python') {
            await TermuxBridge.stopInstallService();
            setState(() {
              _installLog = l.logErrorNoPython;
              _installing = false;
            });
            return;
          } else if (step == 'ERROR:server_failed') {
            await TermuxBridge.stopInstallService();
            setState(() {
              _installLog = l.logErrorServerFailed;
              _installing = false;
            });
            return;
          } else if (step == 'DONE') {
            await TermuxBridge.stopInstallService();
            setState(() {
              _installLog = _relayUrl.isNotEmpty
                  ? l.logDoneWithUrl(_relayUrl)
                  : l.logDoneNoUrl;
              _installing = false;
            });
            return;
          }

          setState(() => _installLog = log);
        }
      });

      // ── 1. Читаємо server.py з assets ──
      setState(() => _installLog = l.logPreparingServer);
      final serverCode = await rootBundle.loadString('assets/memplato_server.py');
      final base64Code = base64Encode(utf8.encode(serverCode));

      // ── 2. Копіюємо wheels з APK в Termux ──
      setState(() => _installLog = l.logCopyingLibs);
      await TermuxBridge.runCommand('mkdir -p ~/wheels');
      await Future.delayed(const Duration(seconds: 1));

      final wheelFiles = [
        // Android-specific (cp313-android)
        'cffi-2.0.0-cp313-cp313-android_24_arm64_v8a.whl',
        'cryptography-48.0.0-cp313-cp313-android_24_arm64_v8a.whl',
        'httptools-0.7.1-cp313-cp313-android_24_arm64_v8a.whl',
        'pydantic_core-2.46.4-cp313-cp313-android_24_arm64_v8a.whl',
        'pyyaml-6.0.3-cp313-cp313-android_24_arm64_v8a.whl',
        'rpds_py-0.30.0-cp313-cp313-android_24_arm64_v8a.whl',
        'uvloop-0.22.1-cp313-cp313-android_24_arm64_v8a.whl',
        'watchfiles-1.1.1-cp313-cp313-android_24_arm64_v8a.whl',
        // Pure Python (py3-none-any)
        'fastapi-0.136.1-py3-none-any.whl',
        'uvicorn-0.47.0-py3-none-any.whl',
        'mcp-1.27.1-py3-none-any.whl',
        'starlette-1.0.0-py3-none-any.whl',
        'pydantic-2.13.4-py3-none-any.whl',
        'pydantic_settings-2.14.1-py3-none-any.whl',
        'anyio-4.13.0-py3-none-any.whl',
        'httpx-0.28.1-py3-none-any.whl',
        'httpcore-1.0.9-py3-none-any.whl',
        'httpx_sse-0.4.3-py3-none-any.whl',
        'h11-0.16.0-py3-none-any.whl',
        'click-8.4.0-py3-none-any.whl',
        'annotated_types-0.7.0-py3-none-any.whl',
        'annotated_doc-0.0.4-py3-none-any.whl',
        'typing_extensions-4.15.0-py3-none-any.whl',
        'typing_inspection-0.4.2-py3-none-any.whl',
        'pyjwt-2.12.1-py3-none-any.whl',
        'jsonschema-4.26.0-py3-none-any.whl',
        'jsonschema_specifications-2025.9.1-py3-none-any.whl',
        'attrs-26.1.0-py3-none-any.whl',
        'referencing-0.37.0-py3-none-any.whl',
        'sse_starlette-3.4.4-py3-none-any.whl',
        'python_dotenv-1.2.2-py3-none-any.whl',
        'python_multipart-0.0.29-py3-none-any.whl',
        'idna-3.15-py3-none-any.whl',
        'certifi-2026.4.22-py3-none-any.whl',
        'pycparser-3.0-py3-none-any.whl',
      ];

      for (final whl in wheelFiles) {
        setState(() => _installLog = l.logCopyingFile(whl.split('-').first));
        await _copyAssetToTermux('assets/wheels/$whl', '~/wheels/$whl');
      }

      // ── 2б. Python залежності з APK ──
      setState(() => _installLog = l.logCopyingDeps);

      final pythonDepFiles = [
        // Базові системні бібліотеки
        'abseil-cpp_20250814.1_aarch64.deb',
        'gdbm_1.26-1_aarch64.deb',
        'glib_2.88.1_aarch64.deb',
        'libandroid-posix-semaphore_0.1-4_aarch64.deb',
        'libandroid-spawn_0.3_aarch64.deb',
        'libcompiler-rt_21.1.8-2_aarch64.deb',
        'libcrypt_0.2-6_aarch64.deb',
        'libexpat_2.8.1_aarch64.deb',
        'libffi_3.4.7-1_aarch64.deb',
        'libicu_78.3_aarch64.deb',
        'libllvm_21.1.8-2_aarch64.deb',
        'libopenblas_0.3.33_aarch64.deb',
        'libprotobuf_2%3a33.1-1_aarch64.deb',
        'libre2_2025-11-05-1_aarch64.deb',
        'libsqlite_3.53.1_aarch64.deb',
        'libxml2_2.15.3_aarch64.deb',
        'ncurses_6.6.20260307+really6.5.20250830_aarch64.deb',
        'ncurses-ui-libs_6.6.20260307+really6.5.20250830_aarch64.deb',
        // Інструменти збірки
        'binutils_2.46.0-3_aarch64.deb',
        'clang_21.1.8-2_aarch64.deb',
        'lld_21.1.8-2_aarch64.deb',
        'llvm_21.1.8-2_aarch64.deb',
        'make_4.4.1-1_aarch64.deb',
        'ndk-sysroot_29-2_aarch64.deb',
        'ninja_1.13.2_aarch64.deb',
        'patchelf_0.18.0-1_aarch64.deb',
        'pkg-config_0.29.2-3_aarch64.deb',
        // ONNX Runtime
        'onnxruntime_1.26.0_aarch64.deb',
        'protobuf_2%3a33.1-1_aarch64.deb',
        // SSH
        'autossh_1.4g-4_aarch64.deb',
        'openssh_10.3p1-1_aarch64.deb',
        'krb5_1.22.2_aarch64.deb',           // НОВЕ
        'ldns_1.8.4-1_aarch64.deb',          // НОВЕ
        'libdb_18.1.40-5_aarch64.deb',       // НОВЕ
        'libedit_20240517-3.1-1_aarch64.deb', // НОВЕ
        'libresolv-wrapper_1.1.7-6_aarch64.deb', // НОВЕ
        'openssh-sftp-server_10.3p1-1_aarch64.deb', // НОВЕ
        'termux-auth_1.5.0-1_aarch64.deb',   // НОВЕ
        // Python пакети
        'python-ensurepip-wheels_3.13.13-1_all.deb',
        'python-numpy_2.4.4_aarch64.deb',
        'python-onnxruntime_1.26.0_aarch64.deb',
        'python-pip_26.1.1_all.deb',
        // pip
        'get-pip.py',
        'pip-26.1.1-py3-none-any.whl',
      ];

      for (final dep in pythonDepFiles) {
        setState(() => _installLog = l.logCopyingFile(dep));
        await _copyAssetToTermux('assets/python_deps/$dep', dep);
      }

      // Python 3.13 — окремо (головний пакет)
      setState(() => _installLog = l.logCopyingPython);
      await _copyAssetToTermux(
        'assets/python_deps/python_3.13.13-1_aarch64.deb',
        'python_3.13.13-1_aarch64.deb',
      );

      // ── 3. Копіюємо модель і токенізатори з APK ──
      setState(() => _installLog = l.logCopyingModel);
      await TermuxBridge.runCommand('mkdir -p ~/.memplato_mobile/models/onnx');

      final modelAssets = [
        ('assets/model.onnx',            '~/.memplato_mobile/models/onnx/model.onnx'),
        ('assets/tokenizer.json',        '~/.memplato_mobile/models/onnx/tokenizer.json'),
        ('assets/tokenizer_config.json', '~/.memplato_mobile/models/onnx/tokenizer_config.json'),
        ('assets/vocab.txt',             '~/.memplato_mobile/models/onnx/vocab.txt'),
      ];

      for (final (asset, dest) in modelAssets) {
        setState(() => _installLog = l.logCopyingFile(asset.split('/').last));
        await _copyAssetToTermux(asset, dest);
      }

      // ── 3б. Копіюємо server.py з APК ──
      setState(() => _installLog = l.logCopyingServer);
      await _copyAssetToTermux('assets/memplato_server.py', '~/memplato_server.py');

      // ── 4. Пишемо bash-скрипт і запускаємо ──
      setState(() => _installLog = l.logPreparingScript);

      final scriptLines = [
        '#!/data/data/com.termux/files/usr/bin/bash',
        'export PATH=/data/data/com.termux/files/usr/bin:\$PATH',
        'am broadcast -a com.memplato.STATUS --es step "STEP:pkg" 2>/dev/null || true',

        // ── Базові системні бібліотеки ──
        'dpkg --force-all -i ~/libandroid-posix-semaphore_0.1-4_aarch64.deb ~/libandroid-spawn_0.3_aarch64.deb ~/libcrypt_0.2-6_aarch64.deb ~/libexpat_2.8.1_aarch64.deb ~/libffi_3.4.7-1_aarch64.deb ~/libsqlite_3.53.1_aarch64.deb ~/gdbm_1.26-1_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/ncurses_6.6.20260307+really6.5.20250830_aarch64.deb ~/ncurses-ui-libs_6.6.20260307+really6.5.20250830_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/libicu_78.3_aarch64.deb ~/libxml2_2.15.3_aarch64.deb ~/glib_2.88.1_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/abseil-cpp_20250814.1_aarch64.deb ~/libprotobuf_2%3a33.1-1_aarch64.deb ~/libre2_2025-11-05-1_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/libllvm_21.1.8-2_aarch64.deb ~/libcompiler-rt_21.1.8-2_aarch64.deb >> ~/install_log.txt 2>&1 || true',

        // ── Python 3.13 ──
        'dpkg --force-all -i ~/python-ensurepip-wheels_3.13.13-1_all.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/python_3.13.13-1_aarch64.deb >> ~/install_log.txt 2>&1 || true',

        // ── pip bootstrap ──
        'python3.13 ~/get-pip.py --no-index --find-links=~/ >> ~/install_log.txt 2>&1',
        'am broadcast -a com.memplato.STATUS --es step "PIP:BOOTSTRAP_OK" 2>/dev/null || true',

        // ── Інструменти збірки ──
        'dpkg --force-all -i ~/binutils_2.46.0-3_aarch64.deb ~/make_4.4.1-1_aarch64.deb ~/ninja_1.13.2_aarch64.deb ~/patchelf_0.18.0-1_aarch64.deb ~/pkg-config_0.29.2-3_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/ndk-sysroot_29-2_aarch64.deb ~/clang_21.1.8-2_aarch64.deb ~/lld_21.1.8-2_aarch64.deb ~/llvm_21.1.8-2_aarch64.deb >> ~/install_log.txt 2>&1 || true',

        // ── ONNX Runtime ──
        'dpkg --force-all -i ~/libopenblas_0.3.33_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/onnxruntime_1.26.0_aarch64.deb ~/protobuf_2%3a33.1-1_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/python-numpy_2.4.4_aarch64.deb ~/python-onnxruntime_1.26.0_aarch64.deb >> ~/install_log.txt 2>&1 || true',

        // ── SSH ──
        'dpkg --force-all -i ~/libresolv-wrapper_1.1.7-6_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/libdb_18.1.40-5_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/libedit_20240517-3.1-1_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/ldns_1.8.4-1_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/krb5_1.22.2_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/termux-auth_1.5.0-1_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/openssh-sftp-server_10.3p1-1_aarch64.deb >> ~/install_log.txt 2>&1 || true',
        'dpkg --force-all -i ~/openssh_10.3p1-1_aarch64.deb ~/autossh_1.4g-4_aarch64.deb >> ~/install_log.txt 2>&1 || true',

        // ── pip (оновлення) ──
        'dpkg --force-all -i ~/python-pip_26.1.1_all.deb >> ~/install_log.txt 2>&1 || true',

        'echo "python hold" | dpkg --set-selections 2>/dev/null || true',

        // ── Перевірка Python ──
        'if ! command -v python3.13 &>/dev/null; then',
        '  am broadcast -a com.memplato.STATUS --es step "ERROR:no_python" 2>/dev/null || true',
        '  exit 1',
        'fi',

        // ── Встановлення wheels ──
        'am broadcast -a com.memplato.STATUS --es step "STEP:wheels" 2>/dev/null || true',

        // Android-specific wheels (з --no-deps бо залежності вже є)
        'python3.13 -m pip install --quiet --no-deps ~/wheels/cffi-2.0.0-cp313-cp313-android_24_arm64_v8a.whl >> ~/install_log.txt 2>&1',
        'python3.13 -m pip install --quiet --no-deps ~/wheels/cryptography-48.0.0-cp313-cp313-android_24_arm64_v8a.whl >> ~/install_log.txt 2>&1',
        'python3.13 -m pip install --quiet --no-deps ~/wheels/httptools-0.7.1-cp313-cp313-android_24_arm64_v8a.whl >> ~/install_log.txt 2>&1',
        'python3.13 -m pip install --quiet --no-deps ~/wheels/pydantic_core-2.46.4-cp313-cp313-android_24_arm64_v8a.whl >> ~/install_log.txt 2>&1',
        'python3.13 -m pip install --quiet --no-deps ~/wheels/pyyaml-6.0.3-cp313-cp313-android_24_arm64_v8a.whl >> ~/install_log.txt 2>&1',
        'python3.13 -m pip install --quiet --no-deps ~/wheels/rpds_py-0.30.0-cp313-cp313-android_24_arm64_v8a.whl >> ~/install_log.txt 2>&1',
        'python3.13 -m pip install --quiet --no-deps ~/wheels/uvloop-0.22.1-cp313-cp313-android_24_arm64_v8a.whl >> ~/install_log.txt 2>&1',
        'python3.13 -m pip install --quiet --no-deps ~/wheels/watchfiles-1.1.1-cp313-cp313-android_24_arm64_v8a.whl >> ~/install_log.txt 2>&1',

        // Pure Python wheels — всі разом з --no-index --find-links
        'python3.13 -m pip install --quiet --no-index --find-links=~/wheels fastapi uvicorn mcp >> ~/install_log.txt 2>&1',

        // ── patchelf для нативних бібліотек ──
        'SITE=/data/data/com.termux/files/usr/lib/python3.13/site-packages',
        'patchelf --add-needed libpython3.13.so \$SITE/pydantic_core/_pydantic_core.cpython-313-aarch64-linux-android.so 2>/dev/null || true',
        'patchelf --add-needed libpython3.13.so \$SITE/rpds/rpds.cpython-313-aarch64-linux-android.so 2>/dev/null || true',
        'patchelf --add-needed libpython3.13.so \$SITE/watchfiles/_rust_notify.cpython-313-aarch64-linux-android.so 2>/dev/null || true',
        'patchelf --add-needed libpython3.13.so \$SITE/cryptography/hazmat/bindings/_rust.cpython-313-aarch64-linux-android.so 2>/dev/null || true',

        'am broadcast -a com.memplato.STATUS --es step "PIP:OK" 2>/dev/null || true',
        'am broadcast -a com.memplato.STATUS --es step "MCP:OK" 2>/dev/null || true',

        // ── Запуск сервера ──
        'am broadcast -a com.memplato.STATUS --es step "STEP:start" 2>/dev/null || true',
        'pkill -f memplato_server.py 2>/dev/null || true',
        'nohup python3.13 ~/memplato_server.py > ~/server.log 2>&1 &',
        'sleep 3',
        'if ! pgrep -f memplato_server.py > /dev/null; then',
        '  am broadcast -a com.memplato.STATUS --es step "ERROR:server_failed" 2>/dev/null || true',
        '  exit 1',
        'fi',

        // ── Тунель ──
        'am broadcast -a com.memplato.STATUS --es step "STEP:tunnel" 2>/dev/null || true',
        '[ -f ~/.ssh/memplato_key ] || ssh-keygen -t rsa -b 2048 -f ~/.ssh/memplato_key -N "" >> ~/install_log.txt 2>&1',
        'PUBKEY=\$(cat ~/.ssh/memplato_key.pub)',
        'RESPONSE=\$(curl -s -X POST https://relay.memplato.com/register -H "Content-Type: application/json" --data-raw "{\\"public_key\\":\\"\$PUBKEY\\"}")',
        'USER_ID=\$(echo "\$RESPONSE" | python3.13 -c "import sys,json; d=json.load(sys.stdin); print(d.get(\\"user_id\\",\\"\\"))" 2>/dev/null || echo "")',
        'TUNNEL_PORT=\$(echo "\$RESPONSE" | python3.13 -c "import sys,json; d=json.load(sys.stdin); print(d.get(\\"tunnel_port\\",7333))" 2>/dev/null || echo "7333")',
        'echo "\$USER_ID" > ~/.memplato_user_id',
        'echo "\$TUNNEL_PORT" > ~/.memplato_port',
        'am broadcast -a com.memplato.STATUS --es step "TUNNEL:registering" 2>/dev/null || true',

// ── Зупиняємо старі процеси ──
        'pkill -f autossh 2>/dev/null || true',
        'pkill -f tunnel_watchdog 2>/dev/null || true',
        'sleep 1',

// ── Запускаємо autossh перший раз ──
        'autossh -M 0 -f -N -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -i ~/.ssh/memplato_key -R \$TUNNEL_PORT:localhost:7333 root@relay.memplato.com >> ~/autossh.log 2>&1',

// ── Пишемо watchdog скрипт ──
        'rm -f ~/tunnel_watchdog.sh',
        r'echo "#!/data/data/com.termux/files/usr/bin/bash" > ~/tunnel_watchdog.sh',
        r'echo "while true; do" >> ~/tunnel_watchdog.sh',
        r'echo "  PORT=\$(cat ~/.memplato_port 2>/dev/null || echo 7333)" >> ~/tunnel_watchdog.sh',
        r'echo "  USER_ID=\$(cat ~/.memplato_user_id 2>/dev/null || echo unknown)" >> ~/tunnel_watchdog.sh',
        r'echo "  ALIVE=\$(curl -s --max-time 5 https://relay.memplato.com/u/\$USER_ID/health | grep -o \"\\\"server\\\":true\")" >> ~/tunnel_watchdog.sh',
        r'echo "  if [ -z \"\$ALIVE\" ]; then" >> ~/tunnel_watchdog.sh',
        r'echo "    echo \"[watchdog \$(date)] tunnel dead, restarting...\" >> ~/autossh.log" >> ~/tunnel_watchdog.sh',
        r'echo "    pkill -f autossh 2>/dev/null; sleep 2" >> ~/tunnel_watchdog.sh',
        r'echo "    autossh -M 0 -f -N -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -i ~/.ssh/memplato_key -R \$PORT:localhost:7333 root@relay.memplato.com >> ~/autossh.log 2>&1" >> ~/tunnel_watchdog.sh',
        r'echo "  fi" >> ~/tunnel_watchdog.sh',
        r'echo "  sleep 30" >> ~/tunnel_watchdog.sh',
        r'echo "done" >> ~/tunnel_watchdog.sh',
        'chmod +x ~/tunnel_watchdog.sh',

// ── Запускаємо watchdog у фоні ──
        'nohup bash ~/tunnel_watchdog.sh >> ~/autossh.log 2>&1 &',

        'sleep 2',
        'am broadcast -a com.memplato.STATUS --es step "TUNNEL:started" --es uid "\$USER_ID" 2>/dev/null || true',
        'am broadcast -a com.memplato.STATUS --es step "DONE" 2>/dev/null || true',
      ];

      // Пишемо скрипт рядок за рядком — кожен рядок окремий Intent (~100-200 символів)
      // НЕ через base64 — він роздувався до ~2700 символів і Intent обрізав → файл 0 байт
      await TermuxBridge.runCommand('rm -f ~/memplato_install.sh');
      await Future.delayed(const Duration(milliseconds: 200));

      for (final line in scriptLines) {
        final escaped = line.replaceAll("'", "'\\''");
        await TermuxBridge.runCommand("echo '$escaped' >> ~/memplato_install.sh");
        await Future.delayed(const Duration(milliseconds: 150));
      }

      await TermuxBridge.runCommand('chmod +x ~/memplato_install.sh');
      await Future.delayed(const Duration(seconds: 1));
      await TermuxBridge.startInstallService();
      await Future.delayed(const Duration(milliseconds: 500));
      await TermuxBridge.runCommand(
        'nohup bash ~/memplato_install.sh > ~/install_run.log 2>&1 &',
      );

    } catch (e) {
      setState(() {
        _installLog = l.logErrorGeneric(e.toString());
        _installing = false;
      });
    }
  }

  void _addLog(String text) {
    setState(() => _installLog += '\n$text');
  }



  Future<void> _startServer() async {
    if (!mounted) return;
    setState(() {
      _installing = true;
      _installLog = 'Starting server...';
    });
    await TermuxBridge.runCommand(
        'cd ~ && nohup python3.13 memplato_server.py >> server.log 2>&1 &'
    );
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    setState(() {
      _installing = false;
      _installLog = '';
    });
    await _checkServer();
  }

  Future<void> _stopServer() async {
    await TermuxBridge.runCommand(
        'pkill -f memplato_server.py 2>/dev/null; pkill -f autossh 2>/dev/null; pkill -f tunnel_watchdog.sh 2>/dev/null; true'
    );
    if (!mounted) return;
    setState(() {
      _serverOnline = false;
      _statusText = AppLocalizations.of(context)!.statusOffline;
    });
  }

  void _copyUrl() {
    if (!mounted) return;
    final urlToCopy = _relayUrl.isNotEmpty ? _relayUrl : _serverUrl;
    if (urlToCopy.isEmpty) return;
    Clipboard.setData(ClipboardData(text: urlToCopy));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.urlCopied),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF01696F),
      ),
    );
  }

  void _applyUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() => _serverUrl = url);
    _startServerChecking();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF171614),
      body: SafeArea(
        child: _checkingSystem
            ? _buildLoading()
            : !_termuxInstalled
            ? _buildStep1()
            : !_hasPermission
            ? _buildStep2()
            : _buildStep3(),
      ),
    );
  }

  Widget _buildLoading() {
    final l = AppLocalizations.of(context)!;
    return Center(                          // ← без const
      child: Column(                        // ← без const
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏛️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: Color(0xFF4F98A3)),
          const SizedBox(height: 16),
          Text(                             // ← без const (бо l.checkingSystem)
            l.checkingSystem,
            style: const TextStyle(color: Color(0xFF797876), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏛️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text(
            'MemPlato',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4F98A3),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1B19),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF393836)),
            ),
            child: Column(
              children: [
                const Text('⚙️', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  l.step1of3,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4F98A3),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.step1title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFCDCCCA),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l.step1desc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF797876),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _downloadTermux,
              icon: const Icon(Icons.download),
              label: Text(
                l.btnDownloadTermux,
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF01696F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _checkSystem,
              icon: const Icon(Icons.refresh),
              label: Text(
                l.btnCheckAgain,
                style: const TextStyle(fontSize: 15),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4F98A3),
                side: const BorderSide(color: Color(0xFF4F98A3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏛️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text(
            'MemPlato',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4F98A3),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1B19),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF393836)),
            ),
            child: Column(
              children: [
                const Text('🔐', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  l.step2of3,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4F98A3),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.step2title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFCDCCCA),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l.step2desc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF797876),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _givePermission,
              icon: const Icon(Icons.lock_open),
              label: Text(
                l.btnGivePermission,
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF01696F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _checkSystem,
              icon: const Icon(Icons.refresh),
              label: Text(
                l.btnCheckAgain,
                style: const TextStyle(fontSize: 15),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4F98A3),
                side: const BorderSide(color: Color(0xFF4F98A3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const Text('🏛️', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 8),
          const Text(
            'MemPlato',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4F98A3),
              letterSpacing: 2,
            ),
          ),
          Text(
            l.mobileServer,
            style: const TextStyle(fontSize: 14, color: Color(0xFF797876)),
          ),
          const SizedBox(height: 40),
          _checkingServer
              ? const CircularProgressIndicator(color: Color(0xFF4F98A3))
              : Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _serverOnline
                  ? const Color(0xFF6DAA45)
                  : const Color(0xFFDD6974),
              boxShadow: [
                BoxShadow(
                  color: (_serverOnline
                      ? const Color(0xFF6DAA45)
                      : const Color(0xFFDD6974))
                      .withOpacity(0.5),
                  blurRadius: 12,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _statusText,
            style: TextStyle(
              fontSize: 16,
              color: _serverOnline
                  ? const Color(0xFF6DAA45)
                  : const Color(0xFFDD6974),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          if (!_allowExternalApps && !_serverOnline) ...[

            if (!_waitingForTermuxRestart && !_installing) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _showAllowExternalAppsDialog,
                  icon: const Icon(Icons.terminal),
                  label: Text(
                    l.btnConfigureTermux,
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF393836),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],

            // Крок 2 — після діалогу: перезапустити і запустити Termux
            if (_waitingForTermuxRestart && !_installing) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF171614),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF393836)),
                ),
                child: Text(
                  l.exitTermuxHint,
                  style: const TextStyle(
                    color: Color(0xFF797876),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _restartTermux,
                  icon: const Icon(Icons.power_settings_new),
                  label: Text(
                    l.btnRestartTermux,
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF393836),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _launchTermuxAndWait,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    l.btnLaunchTermux,
                    style: const TextStyle(fontSize: 15),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4F98A3),
                    side: const BorderSide(color: Color(0xFF4F98A3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],

            // Крок 3 — очікування дозволу
            if (_installing && !_allowExternalApps) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF171614),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF393836)),
                ),
                child: Text(
                  _installLog,
                  style: const TextStyle(
                    color: Color(0xFF4F98A3),
                    fontSize: 13,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                backgroundColor: Color(0xFF393836),
                color: Color(0xFF4F98A3),
              ),
            ],

          ] else if (!_serverOnline && _userId.isEmpty) ...[

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _installing ? null : _installAndStart,
                icon: _installing
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
                    : const Icon(Icons.rocket_launch),
                label: Text(
                  _installing ? l.installing : l.btnInstallServer,
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF01696F),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF393836),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          ],
          if (_installLog.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1B19),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF393836)),
              ),
              child: Text(
                _installLog,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4F98A3),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Color(0xFFCDCCCA), fontSize: 13),
            decoration: InputDecoration(
              labelText: l.installLogLabel,
              labelStyle: const TextStyle(color: Color(0xFF797876)),
              hintText: l.urlHint,
              hintStyle: const TextStyle(color: Color(0xFF5A5957)),
              filled: true,
              fillColor: const Color(0xFF1C1B19),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF393836))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF393836))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4F98A3))),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check, color: Color(0xFF4F98A3)),
                onPressed: _applyUrl,
              ),
            ),
            onSubmitted: (_) => _applyUrl(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: _serverOnline
                      ? ElevatedButton.icon(
                    onPressed: _stopServer,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(l.btnStopServer),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDD6974),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                      : OutlinedButton.icon(
                    onPressed: _serverUrl.isNotEmpty ? _startServer : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l.btnStartServer),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4F98A3),
                      side: const BorderSide(color: Color(0xFF4F98A3)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed:
                    (_relayUrl.isNotEmpty || _serverUrl.isNotEmpty) ? _copyUrl : null,
                    icon: const Icon(Icons.copy),
                    label: Text(l.btnCopyUrl),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF01696F),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF393836),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            l.autoCheckNote,
            style: const TextStyle(fontSize: 12, color: Color(0xFF797876)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Діалог завантаження Termux ────────────────────────────
class _DownloadTermuxDialog extends StatefulWidget {
  const _DownloadTermuxDialog();

  @override
  State<_DownloadTermuxDialog> createState() => _DownloadTermuxDialogState();
}

class _DownloadTermuxDialogState extends State<_DownloadTermuxDialog> {
  bool _agreed = false;

  Future<void> _openTerms() async {
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _TermsDialog(
        onAccepted: () {
          setState(() => _agreed = true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: const Color(0xFF1C1B19),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF393836)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.downloadTermuxTitle,
                      style: const TextStyle(
                        color: Color(0xFFCDCCCA),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: Color(0xFF797876),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF393836), height: 1),

            // Прокручуваний текст + чекбокс + кнопки
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.downloadWhyTitle,
                      style: const TextStyle(
                        color: Color(0xFFCDCCCA),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.downloadWhyDesc,
                      style: const TextStyle(
                        color: Color(0xFF797876),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF4F98A3)),
                      ),
                      child: Text(
                        l.downloadFileName,
                        style: const TextStyle(
                          color: Color(0xFF4F98A3),
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l.downloadSourceLabel,
                      style: const TextStyle(
                        color: Color(0xFF4F98A3),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Перше попередження
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171614),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF393836)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.downloadWarningTitle,
                            style: const TextStyle(
                              color: Color(0xFFCDCCCA),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.downloadWarningDesc,
                            style: const TextStyle(
                              color: Color(0xFF797876),
                              fontSize: 13,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Друге попередження
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171614),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF393836)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.downloadSecurityTitle,
                            style: const TextStyle(
                              color: Color(0xFFCDCCCA),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.downloadSecurityDesc,
                            style: const TextStyle(
                              color: Color(0xFF797876),
                              fontSize: 13,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Divider(color: Color(0xFF393836)),
                    const SizedBox(height: 16),

                    // Чекбокс з посиланням на умови
                    GestureDetector(
                      onTap: () => setState(() => _agreed = !_agreed),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _agreed,
                              onChanged: (v) =>
                                  setState(() => _agreed = v ?? false),
                              activeColor: const Color(0xFF01696F),
                              side: const BorderSide(
                                  color: Color(0xFF4F98A3), width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: _openTerms,
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    color: Color(0xFF797876),
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                  children: [
                                    TextSpan(text: l.agreeLabel),
                                    TextSpan(
                                      text: l.termsLink,
                                      style: const TextStyle(
                                        color: Color(0xFF4F98A3),
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Кнопки
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF797876),
                                side: const BorderSide(
                                    color: Color(0xFF393836)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(l.btnCancel),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _agreed
                                  ? () async {
                                Navigator.of(context).pop();
                                await TermuxBridge.openUrl(
                                  'https://github.com/termux/termux-app/releases/latest',
                                );
                              }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF01696F),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                const Color(0xFF2A2A2A),
                                disabledForegroundColor:
                                const Color(0xFF555555),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(
                                l.btnDownload,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Діалог умов використання ──────────────────────────────
class _TermsDialog extends StatefulWidget {
  final VoidCallback onAccepted;

  const _TermsDialog({required this.onAccepted});

  @override
  State<_TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<_TermsDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: const Color(0xFF1C1B19),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF393836)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.termsTitle,
                      style: const TextStyle(
                        color: Color(0xFFCDCCCA),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Color(0xFF797876)),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF393836), height: 1),

            // Текст умов
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.termsText,
                      style: const TextStyle(
                        color: Color(0xFF797876),
                        fontSize: 14,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Divider(color: Color(0xFF393836)),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _accepted = !_accepted),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _accepted,
                              onChanged: (v) =>
                                  setState(() => _accepted = v ?? false),
                              activeColor: const Color(0xFF01696F),
                              side: const BorderSide(
                                  color: Color(0xFF4F98A3), width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l.agreeCheckbox,
                              style: const TextStyle(
                                color: Color(0xFF797876),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Кнопка прийняти
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _accepted
                            ? () {
                          widget.onAccepted();
                          Navigator.of(context).pop();
                        }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF01696F),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFF2A2A2A),
                          disabledForegroundColor: const Color(0xFF555555),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          l.btnAccept,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}