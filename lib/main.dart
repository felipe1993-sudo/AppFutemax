import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

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
      home: const PlayerPage(initialUrl: 'https://futemax.bot/'),
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

  // Script JS injetado para "limpar" a página: esconde anúncios,
  // bloqueia pop-unders e força o player a ocupar 100% da largura.
  static const String _cleanupScript = r"""
    (function () {
      try {
        // 1) Bloqueia window.open (pop-unders ao clicar no Play)
        window.open = function () { return null; };

        // 2) Bloqueia criação dinâmica de links com target=_blank
        const _origCreate = document.createElement.bind(document);
        document.createElement = function (tag) {
          const el = _origCreate(tag);
          if ((tag || '').toLowerCase() === 'a') {
            try { el.setAttribute('target', '_self'); } catch (e) {}
          }
          return el;
        };

        // 3) Lista de seletores de propagandas conhecidas
        const adSelectors = [
          '[id*="ad" i]','[class*="ad-" i]','[class*="ads" i]',
          '[id*="banner" i]','[class*="banner" i]',
          '[id*="popup" i]','[class*="popup" i]',
          '[id*="sponsor" i]','[class*="sponsor" i]',
          'iframe[src*="ads" i]','iframe[src*="doubleclick" i]',
          'iframe[src*="googlesyndication" i]','iframe[src*="adservice" i]',
          'iframe[src*="popcash" i]','iframe[src*="propeller" i]',
          'iframe[src*="exoclick" i]','iframe[src*="adsterra" i]',
          'div[style*="position: fixed"]',
          'ins.adsbygoogle',
          '.adsbox','.ad-container','.ad-wrapper','.advert','.advertisement'
        ];

        function hideAds() {
          adSelectors.forEach((sel) => {
            document.querySelectorAll(sel).forEach((el) => {
              // Não esconde o player de vídeo nem seus containers
              if (el.tagName === 'VIDEO') return;
              if (el.querySelector && el.querySelector('video, iframe[src*="player" i], iframe[src*="embed" i]')) return;
              try {
                el.style.setProperty('display', 'none', 'important');
                el.style.setProperty('visibility', 'hidden', 'important');
                el.style.setProperty('opacity', '0', 'important');
                el.style.setProperty('pointer-events', 'none', 'important');
                el.style.setProperty('height', '0', 'important');
                el.style.setProperty('width', '0', 'important');
              } catch (e) {}
            });
          });
        }

        // 4) Força o player a ocupar 100% da largura
        function expandPlayer() {
          const candidates = document.querySelectorAll(
            'video, iframe[src*="player" i], iframe[src*="embed" i], iframe[src*="stream" i], iframe[allowfullscreen]'
          );
          candidates.forEach((el) => {
            try {
              el.style.setProperty('width', '100%', 'important');
              el.style.setProperty('max-width', '100%', 'important');
              el.style.setProperty('height', '56.25vw', 'important'); // 16:9
              el.style.setProperty('min-height', '220px', 'important');
              el.style.setProperty('display', 'block', 'important');
              el.setAttribute('allowfullscreen', 'true');
            } catch (e) {}
          });
        }

        // 5) Injeta CSS extra para reforçar a limpeza
        const css = `
          html, body { background:#000 !important; margin:0 !important; padding:0 !important; }
          .ad, .ads, .ad-container, .ad-wrapper, .banner, .popup,
          .advertisement, ins.adsbygoogle { display:none !important; }
          iframe[src*="ads"], iframe[src*="doubleclick"],
          iframe[src*="googlesyndication"] { display:none !important; }
        `;
        const style = document.createElement('style');
        style.type = 'text/css';
        style.appendChild(document.createTextNode(css));
        (document.head || document.documentElement).appendChild(style);

        // 6) Bloqueia listeners de clique que abrem nova janela
        document.addEventListener('click', function (e) {
          const a = e.target && e.target.closest ? e.target.closest('a[target="_blank"]') : null;
          if (a) {
            e.preventDefault();
            e.stopPropagation();
            a.setAttribute('target', '_self');
          }
        }, true);

        // 7) Roda agora e observa mudanças no DOM (anúncios injetados depois)
        hideAds();
        expandPlayer();
        const observer = new MutationObserver(() => {
          hideAds();
          expandPlayer();
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });

        // 8) Reforça a cada 1s nos primeiros 10s
        let ticks = 0;
        const t = setInterval(() => {
          hideAds();
          expandPlayer();
          if (++ticks >= 10) clearInterval(t);
        }, 1000);
      } catch (err) {
        // Silencioso: nunca quebra o carregamento por causa do script
      }
    })();
  """;

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
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            setState(() => _loadProgress = progress);
          },
          onPageStarted: (url) {
            setState(() => _isLoading = true);
            controller.runJavaScript(_cleanupScript);
          },
          onPageFinished: (url) {
            controller.runJavaScript(_cleanupScript);
            setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            final url = request.url.toLowerCase();
            const adHosts = [
              'doubleclick.net','googlesyndication','googleadservices',
              'adservice.google','popcash','propellerads','exoclick',
              'adsterra','popads','onclickads','revcontent','taboola',
              'outbrain','mgid'
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Futemax Clean'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              LinearProgressIndicator(value: _loadProgress / 100.0),
          ],
        ),
      ),
    );
  }
}
