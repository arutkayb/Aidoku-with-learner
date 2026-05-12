# Aidoku Lingo

A personal-use fork of [Aidoku/Aidoku](https://github.com/Aidoku/Aidoku) focused on Japanese-learner features. Adds an OCR overlay, dictionary lookup, sentence translation, and vocabulary flashcards on top of the upstream manga reader.

## Features

### Reader (inherited from Aidoku)

- No ads
- Robust WASM source system
- Online reading through external sources
- Downloads
- Tracker integration (AniList, MyAnimeList)

### Learner mode (this fork)

- **OCR overlay** — tap any panel to extract text via on-device Vision
- **Dictionary lookup** — tap a word for definition, reading, and pitch accent
- **Sentence translation** — translate full dialogue using Apple Translation (requires iOS 18+)
- **Vocabulary flashcards** — save looked-up words and review them with spaced repetition

## Limitations

- **Reader**: iOS 15+
- **Learner mode**: iOS 18+ — depends on the [Apple Translation framework](https://developer.apple.com/documentation/translation), which requires iOS 18 and a downloaded language pack
- Personal-use only — not distributed via any app marketplace or beta platform

## Setup

The project requires two sibling packages checked out next to this repo:

```
mangadict/
  Aidoku-with-learner/   ← this repo
  AidokuRunner/          ← sibling, same parent dir
  Wasm3/                 ← sibling, same parent dir
```

```sh
# Clone all three into the same parent directory
git clone https://github.com/arutkayb/Aidoku-with-learner.git
git clone https://github.com/Aidoku/AidokuRunner.git
git clone https://github.com/Skittyblock/Wasm3.git
```

Then open `Aidoku-lingo.xcodeproj` in Xcode. Select your development team in Signing & Capabilities, choose a simulator or device, and hit Run.

## How to use

### Reader

Open the app, add a source in Settings → Sources, browse to a manga, and tap a chapter to start reading.

### Learner mode

1. Open a chapter in the reader.
2. Tap the cap icon in the toolbar to enable Learner mode.
3. Tap any speech bubble or panel — the OCR overlay highlights detected text.
4. Tap a word to see its dictionary entry (reading, definition, pitch accent).
5. Tap the translate button to get a full-sentence translation via Apple Translation.
6. Tap the bookmark icon on a word to save it to your vocabulary list.
7. Go to Settings → Flashcards to review saved words.

## Acknowledgements & license

Built on top of [Aidoku](https://github.com/Aidoku/Aidoku) by [Skittyblock](https://github.com/Skittyblock) and contributors. All upstream code remains under [GPLv3](LICENSE). Learner-mode additions in this fork are also GPLv3.
