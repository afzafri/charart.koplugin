# Changelog

Notable changes for each release. Versions follow [semantic versioning](https://semver.org).

## [1.1.0] - 2026-09-29

### Added

- **A wiki chooser for books that are not recognised.** Instead of asking you to
  type an address, the plugin searches and shows what it found, with each wiki's
  name and how many articles it has. Hold one to open it in a browser and check
  before choosing. Typing an address by hand is still there as the last option.
- **The filename is used to work out the series.** Metadata is often thin --
  a book called "This Inevitable Ruin" never mentions Dungeon Crawler Carl --
  while the file it came from usually spells the series out.
- **More pictures per character.** Up to twelve are gathered instead of three,
  at no extra cost: the same requests return more rows, and only the picture you
  are looking at is ever downloaded. The title shows where you are, as
  "Carl · 3 of 12".

### Changed

- **Wiki detection weighs what it finds** rather than taking the first name that
  answers. Fandom is full of half-abandoned duplicates, and a series often has a
  separate wiki for its television adaptation; the busier wiki wins, but only
  between equally specific names, so a shortened guess can never beat a fuller
  one and land you on an unrelated wiki with a similar name.
- **Wheel of Time** now points at the wiki about the novels rather than the one
  about the television series.
- **The README** is written for readers now, with installation at the top.

### Fixed

- **Being offline said the wrong thing.** With no network the plugin reported
  that the character was not on the wiki, which was untrue and sent you looking
  for the wrong problem. It now says it could not reach the wiki.
- **A wiki typed by hand is checked before it is saved.** A typo used to be kept
  silently, leaving every later lookup blaming the wiki for an address that was
  never right.

## [1.0.0] - 2026-09-01

First release.

### Added

- **Character art from the book's wiki.** Highlight a name, tap *Character Art*,
  and get pictures of that character without leaving the book.
- **Two-phase lookup.** The highlighted text is resolved to a wiki article
  first, then pictures are gathered for that article. This copes with the long
  or half-remembered forms people actually highlight -- "Princess Donut the
  Queen Anne Chonk" still finds Donut.
- **Reachable from the dictionary popup**, where holding a single word takes
  you by default, as well as from the highlight menu and a bindable gesture.
- **Real credits.** Each picture is captioned with what the uploader wrote on
  the wiki, falling back to the filename, and *Source* opens the wiki page it
  came from.
- **Two or three pictures per character**, with *Previous* and *Next*, and
  *Set as default* to keep the one you prefer. The choice is remembered against
  the character and wiki, so it holds across a whole series.
- **Automatic wiki detection** from the book's metadata: a bundled list of known
  books, then a guess at the Fandom address, then asking once and remembering.
  Any MediaWiki site works, not only Fandom.
- **Caching** of both results and pictures, so looking a character up again is
  instant and works with the wifi off.

### Notes

- No AI is used anywhere: nothing is generated, no model is called, and no API
  key is needed. What a wiki hosts is what you see.
- Tested on an Onyx BOOX Go 6 running KOReader v2026.07.1 on Android 11.
