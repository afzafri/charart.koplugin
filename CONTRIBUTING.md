# Contributing

Most of what makes this plugin useful is data, not code, and adding data needs
no Lua.

## The one hard rule

No AI-generated images, and no AI services.

Pull requests that generate pictures, call an image model, or route lookups
through an LLM or an "AI-enhanced" search will be closed. The point of this
plugin is to show readers art that a person drew, credited to them. A source
that needs an API key is almost always one of these, which is why the plugin
has no way to store one.

## Add a wiki

If the plugin can't find the wiki for a book you're reading, add it to
[`data/wikis.lua`](data/wikis.lua):

```lua
{ match = "dungeon crawler carl", wiki = "https://dungeon-crawler-carl.fandom.com" },
```

`match` is matched against the book's title, series and author, all lowercased,
so pick something that appears in at least one of them. Author works well for a
writer whose books share one wiki.

Please check the wiki answers before sending it:

```sh
curl -s -o /dev/null -w '%{http_code}\n' \
  'https://your-wiki.example/api.php?action=query&meta=siteinfo&format=json'
```

`200` is what you want. Some wikis return `403` to anything that isn't a
browser; those don't work here, and it's better to leave them out than to ship
an entry that fails.

## Add a gallery page pattern

Wikis collect art on a page whose name follows no standard at all. Dungeon
Crawler Carl uses `Fan Art for Carl`; the Wheel of Time wiki uses
`Rand al'Thor/Gallery`. If yours does something else, add it to
[`data/gallery_patterns.lua`](data/gallery_patterns.lua):

```lua
"{name}/Artwork",
```

`{name}` is replaced with the article title. All the patterns go out in a single
request, so one that matches nothing costs nothing.

## Add a source

A source is a file in `sources/` that returns a table:

```lua
return {
    id = "example",
    priority = 50,   -- lower runs first; the wiki source is 10
    search = function(ctx)
        -- ctx.term   what the reader highlighted
        -- ctx.wiki   the wiki chosen for this book
        -- ctx.limit  how many pictures to return
        -- ctx.width  how wide they should be
        return {
            { url = "https://…/picture.jpg", caption = "Carl, by the artist named on the wiki" },
        }
    end,
}
```

Return a list of results, or `nil` plus a short reason. Sources are tried in
priority order until one returns something.

Drop the file in `sources/` and it is picked up on startup. There is no list to
add yourself to.

Two things to know:

- `require` your dependencies at the top of the file, not inside `search`.
  KOReader puts the plugin directory on the module path only while the plugin
  is loading and removes it afterwards, so a late `require` of a plugin file
  will fail.
- `caption` is what the reader sees under the picture. If you can name the
  artist there, do.

## Running the checks

There is no test runner. The pure functions are plain Lua and can be exercised
directly:

```sh
luac -p *.lua sources/*.lua data/*.lua   # syntax
```

For anything touching the network, test against a real wiki rather than a mock;
the failure modes that matter here are all things real wikis do.
