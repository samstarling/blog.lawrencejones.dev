---
layout: post
title:  "Embed a Javascript website inside a binary with Go 1.16"
date:   "2021-02-16 12:00:00 +0000"
image:  /assets/images/golang-embed-screen-still.png
tags:
  - gophers
  - golang
  - binary
  - javascript
hackernews: https://news.ycombinator.com/item?id=26157483
excerpt: |
  <p>
    The upcoming Golang embed directive can help distribute applications that
    depend on non-Go code assets. See how you can embed an entire Javascript
    website into your Go program, simplifying distribution to single binary.
  </p>

---


Amongst all the news- both positive and grumbling- around the [Golang generics
proposal](https://news.ycombinator.com/item?id=26093778), you may have missed
the announcement of [native file
embedding](https://github.com/golang/go/issues/41191) coming in Go 1.16
(February 2021).

Go programs have always been easy to distribute, with great cross-platform
compilation and default static binaries. But if you had files you wanted to
bundle with your app, well, things get a bit harder.

With the new `embed` directive, including files becomes easy. And it opens the
door for some really great UX improvements!

# Website in a binary? Why not!

I have a long-running side-project called
[pgsink](https://github.com/lawrencejones/pgsink) which aims to be a lightweight
alternative to tools like [debezium](https://debezium.io/). In short, you
connect pgsink to a Postgres database and tell it to sync various tables into
the configured sink (at release, this will be Google BigQuery).

Aiming for ease-of-use, I wanted to provide a lightweight UI to expose table
sync status and allow toggling each table. This meant applying my shockingly
out-of-date Javascript knowledge to a modern toolchain (😱), but more crucially,
it makes app distribution harder.

<figure>
  <img
      src="{{ "/assets/images/golang-embed-screen-capture.gif" | prepend:site.baseurl }}"
      alt="Screen capture of the pgsink web UI"/>
  <figcaption>
    pgsink web UI, accessed by port-forwarding to the binary
  </figcaption>
</figure>

Now we have web assets, we need to ship them with our app. We could put
everything in a Dockerfile, but not everyone runs docker- and any standalone
binaries won’t have a working website. pgsink is meant to be super easy-to-use,
so adding an install step that configures web assets was also… yuck.

Screw this, I want to keep my single binary. Let’s see how `embed` makes this
possible.

# Project structure

First, project structure: pgsink has a Golang app at root, with
`cmd/pgsink/main.go` as the binary entrypoint (what you’ll pass to `go build
cmd/pgsink/main.go`). The Javascript app (created using create-react-app) live
in `web`, and will generate build assets into `web/build`.

Shown as a tree, it looks like this:

    pgsink
    ├── cmd
    │   └── pgsink
    │       └── cmd        << Golang binary entrypoint
    └── web
        ├── build          << production Javascript assets
        │   └── static
        │       ├── css
        │       └── js
        ├── public
        └── src
            └── components

# Embed the assets

First, we need to embed the assets. Remember this will work only work with Go >= 1.16,
which isn’t released yet. I’m using the release candidate for now: run `go get
golang.org/dl/go1.16beta1` if you want to follow along.

We’ll create a Golang file for the sole purpose of loading our build assets in
`web/build.go`:


```golang
// web/build.go
package web

import (
  "embed"
)

//go:embed build/*
var Assets embed.FS
```

That’s all we need to embed the assets into the binary.

Simple, right? To explain: `embed` is a new package coming in Go 1.16 which
helps you work with embedded content. You can find the full documentation at
[pkg/embed](https://tip.golang.org/pkg/embed/), but as a brief explanation:

- The `go:embed` directive asks to load all files within the build directory
  (relative to the Go source file) into `Assets`
- An `embed.FS` is a read-only collection of files, providing methods that
  emulate a real filesystem
- It implements the `fs.FS` interface, which allows you to use `embed.FS`
  alongside other stdlib constructs that are adapted for the upcoming filesystem
  consolidation (see [File System Interfaces for
  Go](https://go.googlesource.com/proposal/+/master/design/draft-iofs.md))

# Building a `http.Handler`

Now we have the website stored in `web.Assets`, we need to write a
`http.Handler` that can serve them.

The handler needs to:

- Accept requests at `/web/file/name` and return the contents of
  `web/build/file/name`
- As the Javascript app handles routing, requests to non-website assets should
  be served the root `index.html` (allowing the JS to take over)

In code, this looks like:

```golang
// web/build.go
// Continuing from previous example...

// fsFunc is short-hand for constructing a http.FileSystem
// implementation
type fsFunc func(name string) (fs.File, error)

func (f fsFunc) Open(name string) (fs.File, error) {
        return f(name)
}

// AssetHandler returns an http.Handler that will serve files from
// the Assets embed.FS.  When locating a file, it will strip the given
// prefix from the request and prepend the root to the filesystem
// lookup: typical prefix might be /web/, and root would be build.
func AssetHandler(prefix, root string) http.Handler {
        handler := fsFunc(func(name string) (fs.File, error) {
                assetPath := path.Join(root, name)

                // If we can't find the asset, return the default index.html
                // content
                f, err := Assets.Open(assetPath)
                if os.IsNotExist(err) {
                        return Assets.Open("build/index.html")
                }

                // Otherwise assume this is a legitimate request routed
                // correctly
                return f, err
        })

        return http.StripPrefix(prefix, http.FileServer(http.FS(handler)))
}
```

Picking this apart:

- We wrap the embedded filesystem so that requests to open file `name` are
  prefixed with our root, which is the `build` directory
- Not-found errors suggest we’re seeing a request for a Javascript internal
  route, so serve the `index.html`
- Wrap the `http.Handler` to strip the `/web/` prefix from our file reads

To serve requests from this handler, we can add it to whatever `mux` is routing
our server:


```golang
// Strip /web/ and prepend build, so that a file `a/b.js` would be
// found in web/build/a/b.js, but served from localhost:8080/web/a/b.js.
handler := web.AssetHandler("/web/", "build")

mux.Handle("GET", "/web/", handler.ServeHTTP)
mux.Handle("GET", "/web/*filepath", handler.ServeHTTP)
```

The compiled binary can now serve the site without touching the filesystem:

    $ pgsink serve
    ...
    component=http event=listen address=localhost:8080
    component=http request_id=D6ZD7V1f event=http_request http_method=GET
        http_path=/web/ http_status=200 http_bytes=2992 http_duration=0.005253945
    component=http request_id=h3Imq0Dl event=http_request http_method=GET
        http_path=/web/static/css/2.8938a2ac.chunk.css http_status=200 http_bytes=154146 http_duration=0.000736358
    component=http request_id=WczI7yhi event=http_request http_method=GET
        http_path=/web/static/css/main.44817166.chunk.css http_status=200 http_bytes=141 http_duration=2.8524e-05

# Build pipeline

For fast CI builds, you want to separate the building of Javascript assets from
your Golang toolchain. Producing a release binary will need to combine the two,
so we need to adjust our CI pipeline to account for this.

This project uses CircleCI, and separates the build into many different stages.
Relevant to us is `web-build`, which builds the web assets, and the `release`
step which compiles the final binary and creates a Github release.

Assuming familiarity with the CircleCI config file, we adjust `web-build` to
pass assets into the `release` step, and make `web-build` an input to release:

```yaml
# .circleci/config.yml
---
workflows:
  version: 2
  build-integration:
    jobs:
      - unit-integration
      - web-build
      - release:                    # create a Github release
          requires:
            - unit-integration      # require passing tests
            - web-build             # require web assets to build
          filters:
            branches: {only: master}

jobs:
  web-build:
    docker:
      - *docker_javascript
    working_directory: /app
    steps:
      - checkout
      - run: 'cd web && yarn build'
      # Provide the build assets for later pipeline steps
      - persist_to_workspace:
          root: .
          paths:
            - web/build
  release:
    docker:
      - *docker_golang
    working_directory: /app
    steps:
      - checkout
      # Attach web assets back into web/build
      - attach_workspace:
          at: .
      - run:
          name: Release
          command: goreleaser
```

This configuration allows `release` to use what `web-build` produces, without
bundling the Javascript toolchain alongside the Golang docker image.

<figure>
  <img
      src="{{ "/assets/images/golang-embed-circleci-pipeline.png" | prepend:site.baseurl }}"
      alt="Build that produced https://github.com/lawrencejones/pgsink/releases/tag/v0.6.0"/>
  <figcaption>
    Build that produced <a href="https://github.com/lawrencejones/pgsink/releases/tag/v0.6.0">https://github.com/lawrencejones/pgsink/releases/tag/v0.6.0</a>
  </figcaption>
</figure>

# Wrapping up

This is just one way the `embed` directive can really improve the experience
around distributing Golang apps. It won’t always be a good idea- bundling a
500MB Javascript app would have different trade-offs!- but it’s awesome that Go
gives you the choice.

See the PR that introduced this functionality at
[pgsink/pull/185](https://github.com/lawrencejones/pgsink/pull/185). The PR has
a few details I excluded from the post snippets for clarity, such as checking
the build assets are around before producing a release.

I’m excited to see how people use `embed` to improve their apps. If you have any
cool ideas, I’d love to hear them! [@lawrjones](https://twitter.com/lawrjones)
