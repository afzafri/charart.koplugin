# Changelog

Notable changes for each release. Versions follow [semantic versioning](https://semver.org).

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
