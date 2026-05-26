import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

const String kAppVersion = 'v9.0';
const String kInitialUrl = 'https://futemax.bot/';

const bool kDiagnosticMode = false;

// BLACKLIST de hosts/fragmentos: navegação top-level que contenha um
// destes é bloqueada. Pega ad networks, cloaks de redirecionamento
// e bookmakers brasileiros. Players legítimos (streamtape, vidsrc,
// embed.*) continuam funcionando.
const List<String> kBlockedHostFragments = <String>[
  // === TLD brasileiro de apostas regularizadas ===
  '.bet.br',
  // === Bookmakers / cassinos ===
  'estrelabet',
  'novibet',
  'betano',
  'bet365',
  'sportingbet',
  'betfair',
  'pixbet',
  'kto.com',
  'bet7k',
  'galera.bet',
  'blaze.com',
  'esportesdasorte',
  'esportes-da-sorte',
  'esportedasorte',
  'vaidebet',
  'br4bet',
  'betesporte',
  'betnacional',
  'hiperbet',
  'lebron',
  'jogaomega',
  'mc.games',
  'betpix',
  'super7bet',
  'brazinobet',
  '7games',
  'betsul',
  'betvip',
  'bullsbet',
  'cbet.gg',
  'betcris',
  'betway',
  'parimatch',
  'unibet',
  'leovegas',
  'rivalo',
  'mrjack',
  'pin-up',
  '1xbet',
  '888sport',
  'betclic',
  'realsbet',
  'aposta',
  'cassino',
  '/casino',
  // === Cloaks / Affiliate networks ===
  'catlinesallicts',
  'catlines',
  'kg-br.com',
  '.partners/',
  'novibet.partners',
  'incomeaccess',
  'trackofa',
  'clickdealer',
  'offerwall',
  'affilae',
  'linkbucks',
  'redirect.appsflyer',
  'tracking.',
  // === Ad networks ===
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'popcash',
  'propellerads',
  'exoclick',
  'adsterra',
  'popads',
  'onclickads',
  'revcontent',
  'taboola',
  'outbrain',
  'mgid.com',
  'adnxs.com',
  'rubiconproject',
  'criteo',
  'smartadserver',
  'clickadu',
  'popunder',
  'juicyads',
  'trafficstars',
  'adskeeper',
  'smartyads',
  // Popunders / iclick / chains observados no Futemax
  'rkv1.com',
  'ladidappl.com',
  'adsrv.eacdn',
  'eacdn.com',
  'iclick',
  'whos.amung.us',
  'wlsuperbet',
  'aff.estrelabetpartners',
  'estrelabetpartners',
  'go.aff.',
  'adservice.google',
  // Sequestro de janela observado: adjumpa->tracksummer->s.shopee
  'adjumpa.com',
  'tracksummer',
  's.shopee.com.br',
  'shopee.com.br/affiliate',
];

// Padrões genéricos de URLs de afiliação. Se a URL bate em qualquer
// um destes (em qualquer parte), é bloqueada como redirect spam.
final List<RegExp> kBlockedUrlPatterns = <RegExp>[
  RegExp(r'/click\?'), // adjumpa, etc.
  RegExp(r'/aff_c\?'), // tracksummer, hasoffers
  RegExp(r'[?&]aff(id|iliate_?id|_sub\d?)='),
  RegExp(r'[?&]btag='),
  RegExp(r'[?&]tracking_id='),
  RegExp(r'[?&]offer_id='),
  RegExp(r'[?&]campaign_id=.*affiliate'),
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

  // Anti-popup / anti-redirect inteligente:
  // - bloqueia abertura de popups de spam (ad networks, apostas)
  // - permite player externo legítimo (streamtape, vidsrc, etc.)
  //   redirecionando-o para a janela principal em vez de popup
  static const String _cleanupScript = r"""
    (function () {
      try {
        const SPAM_FRAGMENTS = [
          // TLDs / bookmakers BR
          '.bet.br','estrelabet','novibet','betano','bet365','sportingbet',
          'betfair','pixbet','kto.com','bet7k','galera.bet','blaze.com',
          'esportesdasorte','esportes-da-sorte','esportedasorte',
          'vaidebet','br4bet','betesporte','betnacional','hiperbet',
          'lebron','jogaomega','mc.games','betpix','super7bet','brazinobet',
          '7games','betsul','betvip','bullsbet','cbet.gg','betcris',
          'betway','parimatch','unibet','leovegas','rivalo','mrjack',
          'pin-up','1xbet','888sport','betclic','realsbet',
          'aposta','cassino','/casino',
          // Cloaks / affiliate
          'catlinesallicts','catlines','kg-br','.partners/','novibet.partners',
          'incomeaccess','trackofa','clickdealer','offerwall','affilae',
          'linkbucks','redirect.appsflyer','tracking.',
          // Ad networks
          'doubleclick.net','googlesyndication.com','googleadservices.com',
          'popcash','propellerads','exoclick','adsterra','popads',
          'onclickads','revcontent','taboola','outbrain','mgid.com',
          'adnxs.com','rubiconproject','criteo','smartadserver',
          'clickadu','popunder','juicyads','trafficstars','adskeeper',
          // Popunders / iclick / chains observados
          'rkv1.com','ladidappl.com','adsrv.eacdn','eacdn.com','iclick',
          'whos.amung.us','wlsuperbet','aff.estrelabetpartners',
          'estrelabetpartners','go.aff.','adservice.google'
        ];
        function isSpam(url) {
          if (!url) return false;
          const u = String(url).toLowerCase();
          return SPAM_FRAGMENTS.some(function (f) { return u.indexOf(f) !== -1; });
        }

        // 1) window.open:
        //    - mesmo host → deixa abrir normal
        //    - cross-origin → BLOQUEIA SEMPRE (popunder ads)
        //    Nunca redirecionar janela principal: isso quebra player.
        const _origOpen = window.open;
        window.open = function (url) {
          try {
            if (!url) return null;
            if (isSpam(url)) {
              console.log('[clean] popup blocked (spam): ' + url);
              return null;
            }
            try {
              const u = new URL(url, location.href);
              if (u.host === location.host) {
                return _origOpen ? _origOpen.apply(window, arguments) : null;
              }
            } catch (e) {}
            console.log('[clean] popup blocked (cross-origin): ' + url);
            return null;
          } catch (e) {
            return null;
          }
        };

        // 2) Cliques em <a target="_blank"> spam: bloqueia
        //    Cliques em <a target="_blank"> player: força mesma janela
        document.addEventListener('click', function (e) {
          try {
            const a = e.target && e.target.closest ? e.target.closest('a') : null;
            if (!a) return;
            const href = a.href || a.getAttribute('href') || '';
            if (!href) return;
            if (isSpam(href)) {
              console.log('[clean] click blocked: ' + href);
              e.preventDefault();
              e.stopPropagation();
              return;
            }
            if (a.getAttribute('target') === '_blank') {
              a.setAttribute('target', '_self');
            }
          } catch (err) {}
        }, true);

        // 3) location.replace / location.assign para spam: bloqueia
        try {
          const _replace = window.location.replace.bind(window.location);
          window.location.replace = function (url) {
            if (isSpam(url)) {
              console.log('[clean] replace blocked: ' + url);
              return;
            }
            return _replace(url);
          };
          const _assign = window.location.assign.bind(window.location);
          window.location.assign = function (url) {
            if (isSpam(url)) {
              console.log('[clean] assign blocked: ' + url);
              return;
            }
            return _assign(url);
          };
        } catch (e) {}

        // 4) Esconde iframes de ad-networks e remove links de afiliação
        function nukeAds() {
          document.querySelectorAll('iframe').forEach(function (el) {
            const src = (el.src || el.getAttribute('data-src') || '').toLowerCase();
            if (src && isSpam(src)) {
              el.style.setProperty('display', 'none', 'important');
            }
          });
          document.querySelectorAll('ins.adsbygoogle').forEach(function (el) {
            el.style.setProperty('display', 'none', 'important');
          });
          document.querySelectorAll('a').forEach(function (el) {
            const href = el.getAttribute('href') || '';
            if (isSpam(href)) {
              el.removeAttribute('href');
              el.style.setProperty('pointer-events', 'none', 'important');
            }
          });
        }
        nukeAds();
        new MutationObserver(nukeAds).observe(
          document.documentElement, { childList: true, subtree: true }
        );

        // 5) Mata onbeforeunload (alguns sites usam pra forçar popup)
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
    if (!kDiagnosticMode || !mounted) return;
    setState(() {
      _logs.insert(0, s);
      if (_logs.length > 40) _logs.removeRange(40, _logs.length);
    });
  }

  bool _isBlockedHost(String urlString) {
    if (urlString.isEmpty) return false;
    if (urlString == 'about:blank') return true;
    final lower = urlString.toLowerCase();
    if (kBlockedHostFragments.any((f) => lower.contains(f))) return true;
    if (kBlockedUrlPatterns.any((p) => p.hasMatch(lower))) return true;
    return false;
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
      // User Agent de Safari iOS real (com Version/ e Safari/) pra
      // burlar cloak systems que detectam WKWebView e servem só ad.
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/18.0 Mobile/15E148 Safari/604.1',
      );
    if (kDiagnosticMode) {
      controller.setOnConsoleMessage((JavaScriptConsoleMessage msg) {
        _addLog('[js:${msg.level.name}] ${msg.message}');
      });
    }
    controller
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
            if (kDiagnosticMode) {
              controller.runJavaScript(_diagnosticPing);
            }
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
            if (_isBlockedHost(request.url)) {
              if (kDiagnosticMode) {
                setState(() => _blockedCount++);
              }
              _addLog('BLOCKED: ${request.url}');
              return NavigationDecision.prevent;
            }
            _addLog('navReq OK: ${request.url}');
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
            if (kDiagnosticMode && _blockedCount > 0) ...[
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
