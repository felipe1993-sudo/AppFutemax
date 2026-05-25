import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

// Bumpa este valor a cada build pra você saber qual versão está no celular.
const String kAppVersion = 'v2.0';

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

  // Script JS injetado para "limpar" a página de forma CIRÚRGICA:
  // só bloqueia anúncios e pop-unders claramente identificados pela URL/host,
  // SEM tocar em IDs/classes ambíguos do próprio site.
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

        // 1) Bloqueia window.open só quando for para fora do site
        const _origOpen = window.open;
        window.open = function (url, target, features) {
          try { if (url && isExternal(url)) return null; } catch (e) {}
          return _origOpen ? _origOpen.apply(window, arguments) : null;
        };

        // 2) Bloqueia cliques em links target=_blank externos
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

        // 3) Esconde APENAS iframes / scripts de ad networks conhecidos
        function hideAdNetworkIframes() {
          document.querySelectorAll('iframe').forEach(function (el) {
            const src = (el.src || el.getAttribute('data-src') || '').toLowerCase();
            if (!src) return;
            if (adHostFragments.some(function (h) { return src.indexOf(h) !== -1; })) {
              el.style.setProperty('display', 'none', 'important');
            }
          });
          // ins.adsbygoogle é o padrão do Google AdSense
          document.querySelectorAll('ins.adsbygoogle').forEach(function (el) {
            el.style.setProperty('display', 'none', 'important');
          });
        }

        hideAdNetworkIframes();
        const observer = new MutationObserver(hideAdNetworkIframes);
        observer.observe(document.documentElement, { childList: true, subtree: true });

      } catch (err) {
        try { console.log('[FutemaxClean] cleanup error:', err && err.message); } catch (e) {}
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('Futemax Clean'),
            const SizedBox(width: 8),
            Text(
              kAppVersion,
              style: TextStyle(
                fontSize: 12,
                color: Colors.greenAccent[400],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
