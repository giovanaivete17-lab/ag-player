# AG Player IPTV

Projeto Flutter inicial funcional para reprodução de listas M3U e acesso Xtream Codes.

## Requisitos
- Flutter stable compatível com Dart >= 3.8
- Android Studio / Android SDK
- Para iOS: macOS + Xcode

## Executar
```bash
flutter pub get
flutter run
```

## Gerar APK
```bash
flutter build apk --release
```
O APK será criado em `build/app/outputs/flutter-apk/app-release.apk`.

## O que está implementado
- Interface adaptável com navegação por foco/controle remoto.
- Importação de M3U por URL ou arquivo.
- Parser M3U em Isolate.
- Login Xtream Codes e carregamento de canais ao vivo.
- Reprodução usando media_kit.
- Download de episódios por URL direta, com barra de progresso e salvamento local.
- Seleção básica de faixas de áudio/legenda quando disponibilizadas pela stream.
- Controles de proporção da tela.

## Downloads de episódios
A função de download recebe uma URL direta HTTP/HTTPS do arquivo de vídeo (por exemplo MP4 ou TS). Links HLS/DASH compostos por manifestos e segmentos não são baixados como um único episódio por esta função. Os arquivos ficam no diretório privado do app em `AGPlayer/episodios`.

## Limitações importantes
- DASH, codecs, DRM e seleção de faixas dependem da plataforma, da compilação nativa e da stream. Teste nos aparelhos de destino.
- A compatibilidade de media_kit com iOS exige configuração e validação próprias.
- Este pacote contém o código-fonte; não é um APK compilado nem foi testado em dispositivo físico nesta execução.
- Use somente listas e transmissões que você tenha autorização para acessar.

## Segurança
As credenciais Xtream são mantidas em armazenamento seguro local. Não compartilhe o arquivo de configuração com senhas.
