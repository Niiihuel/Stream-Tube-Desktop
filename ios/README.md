# Stream Tube para iOS (iPhone)

Cliente nativo de YouTube **sin anuncios** para iPhone construido sobre **`streamtube-core`** (Rust + Innertube + proxy HLS local + SQLite + UniFFI) y **SwiftUI + `AVPlayer`**.

## Características principales en iOS
- **0% anuncios:** extrae directamente el manifiesto HLS Apple (`visionOS` / `iOS` Innertube) sin cargar el reproductor web de YouTube.
- **Proxy HLS local en Rust (`127.0.0.1`):** filtra códecs compatibles por hardware con `AVPlayer` (H.264 / HEVC hasta 4K60), respeta selección de resolución y pista de audio original/doblada, y evita errores HTTP 403 por desajuste IPv4/IPv6 en redes móviles.
- **SponsorBlock en tiempo real:** salta automáticamente patrocinios, autopromoción, recordatorios, intros/outros y dibuja los segmentos sobre la barra de tiempo.
- **Background Audio + Picture-in-Picture (PiP) + Lock Screen:** sigue reproduciendo con la pantalla bloqueada, controles en Dynamic Island / Centro de Control y ventana flotante PiP automática.
- **DeArrow & Return YouTube Dislike:** títulos/miniaturas sin clickbait y contador real de dislikes.
- **Privacidad local o cuenta opcional:** suscripciones, historial con reanudación y listas locales en SQLite sin cuenta, o vinculación opcional mediante código (`google.com/device`), además de importación desde NewPipe, FreeTube, Google Takeout u OPML.

---

## Cómo compilar y registrar la app en tu iPhone

### Opción A: Sin Mac (desde Linux usando GitHub Actions + SideStore / AltStore / Sideloadly)
1. Subí los cambios a tu fork en GitHub (`git push origin main`).
2. Entrá a la pestaña **Actions → Build iOS IPA** en tu repositorio `Niiihuel/Stream-Tube-Desktop` y ejecutá el workflow (**Run workflow**).
3. Al finalizar (~4-6 min), descargá el artefacto **`StreamTube-iOS-IPA`** (`StreamTube-iOS.ipa`).
4. Firmalo e instalalo en tu iPhone con tu Apple ID (gratuito o de desarrollador) usando **SideStore**, **AltStore** o **Sideloadly**.

### Opción B: Con Mac + Xcode (registro directo con tu Apple ID)
```bash
./scripts/build-ios.sh
open ios/StreamTube.xcodeproj
```
En Xcode:
1. Seleccioná el target **StreamTube → Signing & Capabilities**.
2. Activá **Automatically manage signing**, elegí tu **Team** (tu Apple ID personal o cuenta Apple Developer) y cambiá el `Bundle Identifier` a uno único (ej. `com.nihuel.streamtube`).
3. Conectá tu iPhone, activá el *Modo Desarrollador* en *Ajustes → Privacidad y seguridad*, y presioná **Run (⌘R)**.
