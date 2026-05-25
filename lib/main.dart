import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

const String kAppVersion = 'v3.0';

// Em true, mostra painel diagnóstico embaixo e DESATIVA o JS de limpeza.
// Quando o site estiver carregando OK, vire false e bumpa kAppVersion.
const bool kDiagnosticMode = true;

const String kInitialUrl = 'https://futemax.bot/';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const FutemaxCleanApp());
}

class FutemaxCleanApp extends StatelessWidget {
  const FutemaxCleanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Futemax Clean',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const PlayerPage(initialUrl: kInitialUrl),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final String initialUrl;
  const PlayerPage({super.key, required this.initialUrl});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  int _loadProgress = 0;
  String _currentUrl = '';
  String _status = 'starting';
  final List<String> _logs = <String>[];

  static const String _cleanupScript = r"""
    (function () {
      try {
        const adHostFragments = [
          'doubleclick.net','googlesyndication.com','googleadservices.com',
          'adservice.google','popcash','propellerads','exoclick',
          'adsterra','popads','onclickads','revcontent','taboola',
          'outbrain.com','mgid.com','adnxs.com','rubiconproject',
          'criteo.com','smartadserver','contentabc','clickadu',
          'adsterra.com','popunder','popms.','poprclma','dmpxs.com'
        ];
        function isExternal(href) {
          try {
            const u = new URL(href, location.href);
            return u.host && u.host !== location.host;
          } catch (e) { return false; }
        }
        const _origOpen = window.open;
        window.open = function (url) {
          try { if (url && isExternal(url)) return null; } catch (e) {}
          return _origOpen ? _origOpen.apply(window, arguments) : null;
        };
        document.addEventListener('click', function (e) {
          try {
            const a = e.target && e.target.closest ? e.target.closest('a') : null;
            if (!a) return;
            const isBlank = a.getAttribute('target') === '_blank';
            const ext = isExternal(a.href);
            if (ext && isBlank) { e.preventDefault(); e.stopPropagation(); }
            else if (isBlank) { a.setAttribute('target', '_self'); }
          } catch (err) {}
        }, true);
        function hideAdNetworkIframes() {
          document.querySelectorAll('iframe').forEach(function (el) {
            const src = (el.src || el.getAttribute('data-src') || '').toLowerCase();
            if (!src) return;
            if (adHostFragments.some(function (h) { return src.indexOf(h) !== -1; })) {
              el.style.setProperty('display', 'none', 'important');
            }
          });
          document.querySelectorAll('ins.adsbygoogle').forEach(function (el) {
            el.style.setProperty('display', 'none', 'important');
          });
        }
        hideAdNetworkIframes();
        new MutationObserver(hideAdNetworkIframes)
          .observe(document.documentElement, { childList: true, subtree: true });
      } catch (err) {}
    })();
  """;

  static const String _diagnosticPing = r"""
    (function () {
      try {
        console.log('[diag] href=' + location.href);
        console.log('[diag] title=' + document.title);
        console.log('[diag] body.children=' + (document.body ? document.body.children.length : 'no-body'));
        console.log('[diag] readyState=' + document.readyState);
        console.log('[diag] ua=' + navigator.userAgent.substring(0, 80));
      } catch (e) { console.log('[diag] err ' + e.message); }
    })();
  """;

  void _addLog(String s) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, s);
      if (_logs.length > 30) _logs.removeRange(30, _logs.length);
    });
  }

  @override
  void initState() {
    super.initState();

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    late final WebViewController controller;
    controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setOnConsoleMessage((JavaScriptConsoleMessage msg) {
        _addLog('[js:${msg.level.name}] ${msg.message}');
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            setState(() => _loadProgress = progress);
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
              _status = 'loading';
            });
            _addLog('-> started: $url');
            if (!kDiagnosticMode) {
              controller.runJavaScript(_cleanupScript);
            }
          },
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
              _status = 'finished';
            });
            _addLog('-> finished: $url');
            if (!kDiagnosticMode) {
              controller.runJavaScript(_cleanupScript);
            }
            controller.runJavaScript(_diagnosticPing);
          },
          onWebResourceError: (error) {
            setState(() => _status = 'error');
            _addLog(
              '!! webError(${error.errorCode}) ${error.errorType?.name}: '
              '${error.description}',
            );
          },
          onHttpError: (error) {
            _addLog(
              '!! httpError ${error.response?.statusCode} on '
              '${error.request?.uri}',
            );
          },
          onNavigationRequest: (request) {
            if (kDiagnosticMode) {
              _addLog('navReq: ${request.url}');
              return NavigationDecision.navigate;
            }
            final url = request.url.toLowerCase();
            const adHosts = [
              'doubleclick.net', 'googlesyndication', 'googleadservices',
              'adservice.google', 'popcash', 'propellerads', 'exoclick',
              'adsterra', 'popads', 'onclickads', 'revcontent', 'taboola',
              'outbrain', 'mgid'
            ];
            if (adHosts.any((h) => url.contains(h))) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    controller.loadRequest(Uri.parse(widget.initialUrl));
    _controller = controller;
  }

  Future<void> _openInSafari() async {
    final uri = Uri.parse(_currentUrl.isNotEmpty ? _currentUrl : kInitialUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    _addLog('openSafari($uri) -> $ok');
  }

  Future<void> _copyLogs() async {
    final text = _logs.reversed.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copiados')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('Futemax Clean'),
            const SizedBox(width: 8),
            Text(
              kAppVersion + (kDiagnosticMode ? ' DIAG' : ''),
              style: TextStyle(
                fontSize: 12,
                color: kDiagnosticMode
                    ? Colors.amberAccent
                    : Colors.greenAccent[400],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Abrir no Safari',
            onPressed: _openInSafari,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isLoading)
              LinearProgressIndicator(value: _loadProgress / 100.0),
            Expanded(child: WebViewWidget(controller: _controller)),
            if (kDiagnosticMode)
              Container(
                color: Colors.grey[900],
                constraints: const BoxConstraints(maxHeight: 240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      color: Colors.black,
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'status: $_status • progress: $_loadProgress%',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.cyanAccent,
                                  ),
                                ),
                                Text(
                                  'url: $_currentUrl',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.copy, color: Colors.white70),
                            tooltip: 'Copiar logs',
                            onPressed: _copyLogs,
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(6),
                        itemCount: _logs.length,
                        itemBuilder: (context, i) {
                          final line = _logs[i];
                          Color color = Colors.white70;
                          if (line.startsWith('!!')) color = Colors.redAccent;
                          if (line.startsWith('->')) color = Colors.greenAccent;
                          if (line.startsWith('[js:')) color = Colors.amberAccent;
                          return Text(
                            line,
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontFamily: 'monospace',
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
