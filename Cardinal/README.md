# Cardinal for Tuna

A [Tuna](https://tunaformac.com) extension that searches every file on your Mac with
[Cardinal](https://github.com/cardisoft/cardinal), as you type.

Type `file` in Tuna, select "Search Files", press → to step into it, and type a name.
If a name matches nothing, the search is retried with its words split at punctuation
(`change.md` finds `changes.md`). Results come from
Cardinal's full-disk index, ranked for a launcher: your own files first, system files,
app internals, caches and build output last. Every result is a normal Tuna file, so
Open, Reveal in Finder, Quick Look and other file actions work. When Cardinal finds more
than 50 matches, the last row opens Cardinal with the same search.

Cardinal's query syntax works too: `ext:pdf invoice`, `size:>100MB`, `in:~/Documents report`.

## Requirements

- Cardinal with the local search API, from the `local-search-api` branch of
  [Yuchen971/cardinal](https://github.com/Yuchen971/cardinal). Cardinal must be running;
  it keeps running in the background after you close its window.
- Tuna 0.96 or later on an Apple silicon Mac.

## Install

See [Install](../README.md#install). From source: `./scripts/install.sh Cardinal --restart`.

## How it talks to Cardinal

Cardinal listens on `127.0.0.1` and writes its port and a fresh access token to
`~/Library/Application Support/com.cardinal.one/local-api.json` on every launch. Only the
current user can read that file. The extension reads it, calls `GET /v1/search`, and calls
`POST /v1/show` for "Show all results in Cardinal".
