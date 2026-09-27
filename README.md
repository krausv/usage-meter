# UsageMeter

Menu-bar app pro macOS: klidný přehled o zbývajících limitech **Claude Code** a **Muse** — stejná data jako `/usage`, přímo v menu baru (5h + týdenní okna, countdown do resetu).

Vychází z [CalmMeter](https://github.com/calmbit-sro/CalmMeter) (MIT, CalmBit s.r.o.) — Claude cesta je převzata beze změny, navíc je přidán provider pro Muse.

## Požadavky

- macOS 13+
- Swift toolchain (`xcode-select --install`); pro `swift test` je potřeba plné Xcode (CLT neobsahuje XCTest)

## Build

```bash
swift build
./scripts/build-app.sh [--install]
```
