# Futemax Clean (Flutter WebView + JS Injection)

App em **Flutter** que carrega `https://futemax.bot/` dentro de uma WebView e executa
um script de **JavaScript Injection** para:

- Esconder (`display: none`) divs/iframes de anúncios, banners e pop-ups conhecidos.
- Forçar o player de vídeo a ocupar **100% da largura** da tela (aspect ratio 16:9).
- Bloquear **pop-unders** (`window.open`) e abertura de novas janelas ao clicar em "Play".
- Bloquear navegação para domínios de ad-networks (DoubleClick, PopCash, ExoClick, etc).

> ⚠️ Aviso: este projeto é apenas um exercício técnico de WebView + JS Injection.
> Você é responsável por respeitar os Termos de Uso do site carregado e a legislação
> local sobre transmissão de conteúdo. Prefira fontes oficiais/licenciadas sempre que possível.

---

## 1. Pré-requisitos (Windows)

1. **Flutter SDK** — instale seguindo o guia oficial:
   <https://docs.flutter.dev/get-started/install/windows>
2. **Android Studio** (apenas para baixar o SDK do Android e o emulador) ou um celular
   Android com **Depuração USB** ativada.
3. **VS Code** com as extensões:
   - `Flutter` (Dart-Code)
   - `Dart`

Verifique que tudo está OK com:

```powershell
flutter doctor
```

Resolva qualquer item com `[X]` antes de continuar (especialmente "Android toolchain"
e "Android licenses": rode `flutter doctor --android-licenses`).

---

## 2. Estrutura do projeto

Este repositório já contém os arquivos principais:

```
futebol/
├─ pubspec.yaml                          # dependências (webview_flutter)
├─ lib/
│  └─ main.dart                          # app + script JS de limpeza
└─ android/app/src/main/
   └─ AndroidManifest.xml                # permissão de INTERNET
```

Mas o Flutter precisa gerar as pastas nativas (`android/`, `ios/`, `windows/`, etc.).
Faça isso rodando, **dentro da pasta `futebol/`**:

```powershell
flutter create . --project-name futemax_clean --platforms=android
```

> Isso **não** sobrescreve o `lib/main.dart` nem o `pubspec.yaml` que já existem
> (ele só adiciona o que falta). Se mesmo assim ele perguntar, responda `n` para
> manter os arquivos atuais.

Depois copie o `AndroidManifest.xml` deste repo por cima do gerado, ou apenas
adicione a linha `<uses-permission android:name="android.permission.INTERNET"/>`
ao arquivo gerado.

---

## 3. Instalar dependências e rodar

```powershell
flutter pub get
flutter run
```

Se tiver mais de um device, liste com `flutter devices` e escolha:

```powershell
flutter run -d <device_id>
```

Para gerar um APK de release:

```powershell
flutter build apk --release
```

O APK fica em `build/app/outputs/flutter-apk/app-release.apk`.

---

## 4. Como o "limpa anúncios" funciona

O coração da limpeza está em `lib/main.dart`, na constante `_cleanupScript`.
Ele é injetado em **dois momentos**:

1. `onPageStarted` — assim que o HTML começa a carregar (pega anúncios estáticos).
2. `onPageFinished` — depois que tudo carregou (pega anúncios injetados via JS).

Além disso, um `MutationObserver` fica observando o DOM e re-aplica a limpeza
sempre que o site tenta injetar uma nova propaganda. Um `setInterval` reforça
a limpeza nos primeiros 10 segundos.

**Estratégias usadas:**

| Técnica | O que faz |
|--------|-----------|
| Seletores CSS (`[id*="ad"]`, `iframe[src*="doubleclick"]`, …) | Esconde elementos de anúncio |
| `window.open = () => null` | Mata pop-unders |
| `target="_blank"` → `_self` | Impede que o site abra abas novas |
| `NavigationDelegate` no Flutter | Bloqueia requests para hosts de ad-networks |
| `expandPlayer()` | Força `<video>`/`<iframe>` do player para 100% de largura |

---

## 5. Customizando

- **Mudar o site/jogo:** altere a URL em `lib/main.dart`:
  ```dart
  home: const PlayerPage(initialUrl: 'https://futemax.bot/'),
  ```
- **Adicionar mais seletores de anúncio:** edite o array `adSelectors` no `_cleanupScript`.
- **Bloquear mais domínios:** edite a lista `adHosts` no `onNavigationRequest`.

---

## 6. Próximos passos sugeridos

Conforme você sugeriu no prompt original, comece **com um link fixo** e só depois evolua para:

1. Tela de **lista de jogos** (puxando os links do próprio futemax via scraping leve).
2. **Atualização diária** dos links (cron no servidor ou scraping no client).
3. **Picture-in-Picture** (PiP) no Android: pacote `floating` ou
   `flutter_pip_native`.
4. **Chromecast**: pacote `cast` ou `flutter_video_cast`.

---

## 7. Troubleshooting

- **Tela branca:** rode `flutter clean && flutter pub get && flutter run`.
- **`MissingPluginException`:** desinstale o app do device e rode `flutter run` de novo.
- **Vídeo não toca inline (iOS):** já tratado via `allowsInlineMediaPlayback: true`.
- **HTTPS / cleartext:** já tratado via `android:usesCleartextTraffic="true"`.

---

## 8. Build iOS sem ter um Mac (grátis, via GitHub Actions + Sideloadly)

Como a Apple só permite gerar `.ipa` em macOS, a estratégia para usuários de Windows
é compilar **na nuvem** (gratuita) e fazer o **sideload** no iPhone via cabo USB.

### Visão geral

```
PC Windows ─push─► GitHub ─trigger─► macOS runner ─► .ipa baixado
                                                         │
                                                         ▼
                                  Sideloadly + cabo ───► iPhone
```

### Passo 1: Subir o projeto para o GitHub

Crie um repositório no <https://github.com/new> (público é mais simples — minutos
ilimitados de macOS gratuitos). Depois, dentro da pasta do projeto:

```powershell
git init
git add .
git commit -m "Setup inicial: app Flutter + workflows iOS/Android"
git branch -M main
git remote add origin https://github.com/<seu-usuario>/<seu-repo>.git
git push -u origin main
```

### Passo 2: Disparar o build

O workflow `.github/workflows/build-ios.yml` já está configurado e roda automaticamente
a cada push para `main`. Você também pode disparar manualmente em:

> GitHub → seu repo → aba **Actions** → **Build iOS IPA (unsigned)** → **Run workflow**

O build leva **~10 a 15 minutos** (CocoaPods + Xcode + Flutter no macOS).

### Passo 3: Baixar o .ipa

Quando o workflow terminar (✓ verde), abra o run e role até o final.
Em **Artifacts**, clique em `futemax_clean-unsigned-ipa` para baixar o ZIP.
Extraia e você terá `futemax_clean-unsigned.ipa`.

### Passo 4: Sideload no iPhone com Sideloadly (Windows)

1. Baixe o **Sideloadly**: <https://sideloadly.io/> (versão Windows)
2. Instale também o **iTunes** se ainda não tiver
   (necessário para os drivers USB do iPhone — basta o "iTunes" da Microsoft Store).
3. Abra o Sideloadly, conecte o iPhone via cabo USB e **autorize** o computador no iPhone.
4. Arraste o `.ipa` para a janela do Sideloadly.
5. Em **Apple ID**, coloque seu Apple ID gratuito (cria uma senha de app em
   <https://appleid.apple.com> se aparecer erro de autenticação 2FA).
6. Clique em **Start**.
7. Quando ele pedir, **digite a senha do seu Apple ID** no popup.
8. Aguarde 30-60 segundos. Pronto, o app aparece na tela inicial do iPhone.

### Passo 5: Confiar no app no iPhone

Na primeira vez ele abre com erro "Desenvolvedor não confiável". Resolve assim:

> Ajustes → Geral → **VPN e Gerenciamento de Dispositivo** → toque no seu Apple ID
> → **Confiar em "<seu nome>"**.

Pronto, o app abre.

### Limitações da assinatura grátis

| Item | Limite |
|------|--------|
| Validade do app | **7 dias** (depois precisa repetir o passo 4 com cabo) |
| Apps ativos por Apple ID | 3 simultâneos |
| App IDs novos por 7 dias | 10 |

Para remover esses limites, a única forma legal é o **Apple Developer Program**
(US$99/ano) — aí o sideload vale 1 ano por instalação.

### Build Android automático também

O workflow `.github/workflows/build-android.yml` faz a mesma coisa para Android,
gerando o `app-debug.apk` como artifact. Útil quando você não quer ficar
recompilando localmente.
