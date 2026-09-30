# UsageMeter

Aplikace do menu baru pro macOS: klidný přehled o zbývajících limitech tvých AI asistentů — stejná data jako `/usage` a `/status`, přímo v liště. 5hodinová + týdenní okna, odpočet do resetu, bez otevírání terminálu.

Podporovaní provideři:

| Provider | Zdroj dat | Přihlášení |
|---|---|---|
| **Claude Code** | `GET api.anthropic.com/api/oauth/usage` | automaticky z Claude Code, nebo vlastní OAuth |
| **Muse** | streamovaný `POST api.meta.ai/v1/responses` (kvóta v SSE eventu) | `muse login` v terminálu |
| **Codex** | `GET chatgpt.com/backend-api/wham/usage` (poll nic nestojí) | `codex login` v terminálu |

## Požadavky

- macOS 13+
- Přihlášení aspoň k jedné službě (viz tabulka). Claude Code samotný není potřeba.

## Instalace

1. Z [Releases](../../releases) stáhni `UsageMeter.dmg`.
2. Otevři ho a přetáhni **UsageMeter** do **Applications**.
3. Spusť z Applications. (Varování Gatekeeperu: pravý klik → Otevřít → Otevřít; u notarizovaného DMG není potřeba.)

## Používání

Klik na ikonku otevře panel: 5h a týdenní využití s odpočtem pro každého přihlášeného providera, tlačítko pro okamžitý refresh.

### Předvolby

- **Formát menu baru:** tečka + 5h % · jen 5h % · `5h % · weekly %` · jen tečka — a volitelně k tomu Muse / Codex číslo (tečka v brand barvě providera).
- **Refresh interval** (Claude; Muse a Codex se obnovují po 5 minutách).
- **Spouštět po přihlášení**, per-model breakdown (Claude), barevné prahy.

## Přihlášení Claude (bez Claude Code)

Kdo nepoužívá Claude Code na Macu, klikne v panelu na **Sign in with Claude**: otevře se autorizace v prohlížeči, schválený kód (`CODE#STATE`) se vloží zpět do appky. Přihlášení se ukládá do vlastní keychain položky a token si appka sama obnovuje. Odhlášení je v Předvolbách → Account.

Kdo Claude Code používá, nemusí dělat nic — appka si token najde v login keychain sama (jednorázový souhlas „Allow").

## Build ze zdroje

```bash
git clone https://github.com/krausv/usage-meter.git && cd usage-meter
swift build                # překlad (pro swift test je potřeba plné Xcode)
./scripts/build-app.sh     # sestaví ./UsageMeter.app
./scripts/build-app.sh --install  # + instalace do /Applications
```

Podepsané DMG pro distribuci: `./scripts/make-dmg.sh` (s vlastním Developer ID; volitelně `--notarize`). Automatické releasy běží v GitHub Actions při pushnutí `v*` tagu — potřebují secrety popsané v [.github/workflows/release.yml](.github/workflows/release.yml).

## Jak to funguje

- Každý provider má vlastního klienta a polling smyčku s exponenciálním backoffem (ctí `Retry-After`); poslední dobrá data zůstávají přes chyby.
- Claude: vlastní OAuth credentials mají přednost, fallback je token z Claude Code keychain (čtený přes `security`, aby polling nikdy nevyvolal prompt).
- Muse: `LLM|` klíč z keychain (`ai.meta.dev.credentials`), jeden drobný streamovaný probe za poll.
- Codex: token ze souboru `~/.codex/auth.json` (čte se znovu každý poll).
- Nikam se neposílá nic kromě dotazů na Anthropic / Meta / ChatGPT API za tvoje vlastní usage. Žádné analytiky.

## Poděkování

UsageMeter vychází z [CalmMeter](https://github.com/calmbit-sro/CalmMeter) od CalmBit s.r.o. (MIT) — Claude cesta je z něj převzatá, Muse a Codex podpora je vlastní.
