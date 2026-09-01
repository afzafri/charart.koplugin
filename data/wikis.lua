--[[--
Known books and the wikis that cover them.

Guessing a Fandom address from a book's title gets it right maybe two thirds of
the time -- "stormlightarchive" works, "cradle" does not -- so this list carries
the ones guessing misses, along with the wikis that never lived on Fandom.

Each entry matches on a lowercased substring of the book's title, its series, or
its author, whichever the reader's copy happens to have in its metadata. The
first match wins, so put more specific patterns above general ones.

Adding the wiki for a book you are reading is a welcome pull request. Please
check that <wiki>/api.php answers before sending it.
--]]--

return {
    { match = "dungeon crawler carl", wiki = "https://dungeon-crawler-carl.fandom.com" },
    { match = "matt dinniman",        wiki = "https://dungeon-crawler-carl.fandom.com" },
    { match = "wandering inn",        wiki = "https://wiki.wanderinginn.com" },
    { match = "cradle",               wiki = "https://abidan-archives.fandom.com" },
    { match = "will wight",           wiki = "https://abidan-archives.fandom.com" },
    { match = "empyrean",             wiki = "https://the-empyrean-series.fandom.com" },
    { match = "fourth wing",          wiki = "https://the-empyrean-series.fandom.com" },
    { match = "iron flame",           wiki = "https://the-empyrean-series.fandom.com" },
    { match = "onyx storm",           wiki = "https://the-empyrean-series.fandom.com" },
    { match = "rebecca yarros",       wiki = "https://the-empyrean-series.fandom.com" },
    { match = "stormlight",           wiki = "https://stormlightarchive.fandom.com" },
    { match = "wheel of time",        wiki = "https://wheeloftime.fandom.com" },
    { match = "robert jordan",        wiki = "https://wheeloftime.fandom.com" },
    { match = "discworld",            wiki = "https://wiki.lspace.org" },
    { match = "terry pratchett",      wiki = "https://wiki.lspace.org" },
    { match = "song of ice and fire", wiki = "https://awoiaf.westeros.org" },
    { match = "george r r martin",    wiki = "https://awoiaf.westeros.org" },
    { match = "tolkien",              wiki = "https://lotr.fandom.com" },
    { match = "lord of the rings",    wiki = "https://lotr.fandom.com" },
    { match = "expanse",              wiki = "https://expanse.fandom.com" },
    { match = "bobiverse",            wiki = "https://bobiverse.fandom.com" },
    { match = "red rising",           wiki = "https://red-rising.fandom.com" },
    { match = "malazan",              wiki = "https://malazan.fandom.com" },
    { match = "harry potter",         wiki = "https://harrypotter.fandom.com" },
    { match = "mistborn",             wiki = "https://mistborn.fandom.com" },
}
