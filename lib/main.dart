import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

const String kAppVersion = 'v4.0';
const String kInitialUrl = 'https://futemax.bot/';

// Quando true, mostra painel de logs embaixo (não desativa nada — só observa).
// Vire false depois que tudo estiver redondo e a interface fica limpa.
const bool kDiagnosticMode = true;

// Domínios cujo TOP-LEVEL navigation é permitido. Tudo fora dessa lista é
// bloqueado (popups de aposta, cloak ads, etc.). Recursos do site
// (imagens, CSS, JS, iframes) NÃO passam por essa lista — só navegações
// reais do frame principal.
const List<String> kAllowedNavHosts = <String>[
  'futemax.bot',
];

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
  int _blockedCount = 0;
  String _currentUrl = '';
  String _status = 'starting';
  final List<String> _logs = <String>[];

  // Anti-popup / anti-redirect agressivo, mas sem mexer no layout do site.
  static const String _cleanupScript = r"""
    (function () {
      try {
        const SAFE_HOST = location.host.replace(/^www\./, '');
        function isSameSite(href) {
          try {
            const u = new URL(href, location.href);
            const h = u.host.replace(/^www\./, '');
            return h === SAFE_HOST || h.endsWith('.' + SAFE_HOST);
          } catch (e) { return false; }
        }

        const _origOpen = window.open;
        window.open = function (url) {
          try { if (!url || !isSameSite(url)) return null; } catch (e) {}
          return _origOpen ? _origOpen.apply(window, arguments) : null;
        };

        document.addEventListener('click', function (e) {
          try {
            const a = e.target && e.target.closest ? e.target.closest('a') : null;
            if (!a) return;
            const href = a.getAttribute('href') || '';
            if (!href) return;
            const ext = !isSameSite(a.href);
            if (ext) {
              e.preventDefault();
              e.stopPropagation();
            } else if (a.getAttribute('target') === '_blank') {
              a.setAttribute('target', '_self');
            }
          } catch (err) {}
        }, true);

        try {
          const _replace = window.location.replace.bind(window.location);
          window.location.replace = function (url) {
            if (url && !isSameSite(url)) return;
            return _replace(url);
          };
          const _assign = window.location.assign.bind(window.location);
          window.location.assign = function (url) {
            if (url && !isSameSite(url)) return;
            return _assign(url);
          };
        } catch (e) {}

        const adHostFragments = [
          'doubleclick.net','googlesyndication.com','googleadservices.com',
          'adservice.google','popcash','propellerads','exoclick',
          'adsterra','popads','onclickads','revcontent','taboola',
          'outbrain.com','mgid.com','adnxs.com','rubiconproject',
          'criteo.com','smartadserver','contentabc','clickadu',
          'adsterra.com','popunder','popms.','poprclma','dmpxs.com',
          'catlinesallicts','kg-br.com','betano','bet365','sportingbet',
          'incomeaccess','revenue.','clickfunnel','linkbucks',
          'adskeeper','smartyads','mediavenus','onelink','trackofa',
          'trafficstars','juicyads','affilae','clickdealer','offerwall'
        ];
        function nukeAds() {
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
          document
            .querySelectorAll('a[href*="catlinesallicts"], a[href*="kg-br.com"], a[href*="betano"]')
            .forEach(function (el) {
              el.removeAttribute('href');
              el.style.setProperty('pointer-events', 'none', 'important');
            });
        }
        nukeAds();
        new MutationObserver(nukeAds).observe(
          document.documentElement, { childList: true, subtree: true }
        );

        window.onbeforeunload = null;
      } catch (err) { /* silencioso */ }
    })();
  """;

  static const String _diagnosticPing = r"""
    (function () {
      try {
        console.log('[diag] href=' + location.href);
        console.log('[diag] body.children=' + (document.body ? document.body.children.length : 'no-body'));
      } catch (e) { console.log('[diag] err ' + e.message); }
    })();
  """;

  void _addLog(String s) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, s);
      if (_logs.length > 40) _logs.removeRange(40, _logs.length);
    });
  }

  bool _isAllowedHost(String urlString) {
    if (urlString.isEmpty || urlString == 'about:blank') return false;
    Uri uri;
    try {
      uri = Uri.parse(urlString);
    } catch (_) {
      return false;
    }
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    if (host.isEmpty) return false;
    return kAllowedNavHosts.any((h) => host == h || host.endsWith('.$h'));
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
            controller.runJavaScript(_cleanupScript);
          },
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
              _status = 'finished';
            });
            _addLog('-> finished: $url');
            controller.runJavaScript(_cleanupScript);
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
            if (_isAllowedHost(request.url)) {
              _addLog('navReq OK: ${request.url}');
              return NavigationDecision.navigate;
            }
            // Bloqueia popup/cloak/redirect de aposta e about:blank
            setState(() => _blockedCount++);
            _addLog('BLOCKED: ${request.url}');
            return NavigationDecision.prevent;
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
    String urlStr = kInitialUrl;
    try {
      urlStr = await _controller.currentUrl() ?? kInitialUrl;
    } catch (_) {}
    final uri = Uri.parse(urlStr);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    _addLog('openSafari($uri) -> $ok');
  }

  Future<void> _goHome() async {
    await _controller.loadRequest(Uri.parse(kInitialUrl));
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
            if (_blockedCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red[700],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_blockedCount blk',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Início',
            onPressed: _goHome,
          ),
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
                constraints: const BoxConstraints(maxHeight: 200),
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
                                  'status: $_status • $_loadProgress% • blocked: $_blockedCount',
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
                          IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white70,
                            ),
                            tooltip: 'Limpar logs',
                            onPressed: () => setState(_logs.clear),
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
                          if (line.startsWith('-> ')) color = Colors.greenAccent;
                          if (line.startsWith('[js:')) color = Colors.amberAccent;
                          if (line.startsWith('BLOCKED')) {
                            color = Colors.orangeAccent;
                          }
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
