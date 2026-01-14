# Rev Pinning Quickstart Guide

## Overview
This guide shows how to add rev-pinned ESM architecture to an Elixir/Phoenix app with Outerfaces.

## Prerequisites
- Phoenix 1.8+ application
- Outerfaces 0.2.4+
- Outerfaces.Odd 0.2.4+
- Client-side project in `outerfaces/projects/my_client_app/`

## Step 1: Choose Your ServeIndex Strategy

### Option A: Basic (Stock Library Plug)

**Use when**: You have simple HTML/JS files without ESM imports or import maps.

The stock `Outerfaces.Odd.Plugs.OddCDNConsumerServeIndex` provides:
- Static asset serving with `.rofl` file transformation
- Basic index.html fallback
- Rev-pinned URL support

**Does NOT include**:
- Import map injection (you'll need to hardcode it in HTML)
- CSP nonce generation
- Base tag injection

### Option B: Extended (Custom Implementation)

**Use when**: You need ES module import maps, CSP nonces, or advanced features.

**IMPORTANT**: The stock library plug does NOT inject import maps automatically. If you want import maps with rev-pinned paths, you need to create an extended version.

Create `/lib/my_app/outerfaces/cdn_consumer_serve_index.ex`:

```elixir
defmodule MyApp.Outerfaces.CDNConsumerServeIndex do
  @moduledoc """
  Extended ServeIndex with import map injection for rev-pinned ESM architecture.

  Extends the stock OddCDNConsumerServeIndex with:
  - Import map injection with `/__rev/<rev>/spa/...` paths
  - CSP nonce generation for inline scripts
  - Base tag injection for correct import resolution
  """

  import Plug.Conn

  alias Outerfaces.Odd.Plugs.OddCDNRoflJSPlug, as: ModifyCDNJsFiles
  alias Outerfaces.Odd.Plugs.OddCDNRoflCSSPlug, as: ModifyCDNCssFiles
  alias Outerfaces.Odd.Plugs.OddCDNRoflHTMLPlug, as: ModifyCDNHTMLFiles

  @behaviour Plug

  @impl true
  def init(opts) do
    static_root = Keyword.get(opts, :static_root, "priv/static")
    root = Path.expand(static_root)
    index_path = Keyword.get(opts, :index_path, Path.join(root, "index.html")) |> Path.expand()

    %{
      index_path: index_path,
      static_root: root,
      static_patterns: Keyword.get(opts, :static_patterns, default_static_patterns())
    }
  end

  @impl true
  def call(conn, %{index_path: index_path, static_root: static_root, static_patterns: static_patterns}) do
    request_path = conn.request_path

    cond do
      static_asset_request?(request_path, static_patterns) ->
        serve_static_asset(conn, static_root, request_path)

      true ->
        serve_index_html(conn, index_path)
    end
  end

  defp serve_static_asset(conn, static_root, request_path) do
    root = static_root

    with false <- String.contains?(request_path, <<0>>),
         rel <- String.trim_leading(request_path, "/"),
         false <- String.contains?(rel, ["\\", ":"]),
         candidate <- Path.expand(rel, root),
         true <- candidate == root or String.starts_with?(candidate, root <> "/"),
         true <- File.regular?(candidate) do
      mime_type = MIME.from_path(candidate)
      is_javascript = String.contains?(mime_type, "javascript")
      is_css = String.contains?(mime_type, "css")
      is_rofl_js_file = String.contains?(candidate, ".rofl.js")
      is_rofl_css_file = String.contains?(candidate, ".rofl.css")
      should_modify_js = is_javascript and is_rofl_js_file
      should_modify_css = is_css and is_rofl_css_file

      cond do
        should_modify_js ->
          with {:ok, content} <- File.read(candidate),
               modified_file <- ModifyCDNJsFiles.transform_javascript_with_conn(content, conn, "") do
            conn
            |> put_resp_content_type(mime_type)
            |> send_resp(200, modified_file)
          else
            _ ->
              conn
              |> put_resp_content_type(mime_type)
              |> send_file(200, candidate)
          end

        should_modify_css ->
          with {:ok, content} <- File.read(candidate),
               modified_file <- ModifyCDNCssFiles.transform_css_with_conn(content, conn, "") do
            conn
            |> put_resp_content_type(mime_type)
            |> send_resp(200, modified_file)
          else
            _ ->
              conn
              |> put_resp_content_type(mime_type)
              |> send_file(200, candidate)
          end

        true ->
          conn
          |> put_resp_content_type(mime_type)
          |> send_file(200, candidate)
      end
      |> halt()
    else
      _ ->
        send_resp(conn, 404, "File not found")
        |> halt()
    end
  end

  defp serve_index_html(conn, index_path) do
    {:ok, content} = File.read(index_path)

    # Generate CSP nonce early
    nonce = generate_csp_nonce()
    conn = assign(conn, :csp_nonce, nonce)

    # Get rev for import map
    rev = Map.get(conn.assigns, :outerfaces_rev) || Outerfaces.Rev.current_rev()

    # Check if this is a .rofl.html file that needs token transformation
    modified_content =
      if String.ends_with?(index_path, ".rofl.html") do
        content
        |> ModifyCDNHTMLFiles.transform_html_cdn_tokens(conn, "")
        |> inject_base_tag()
        |> inject_import_map(nonce, rev)
      else
        content
        |> inject_base_tag()
        |> inject_import_map(nonce, rev)
      end

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, modified_content)
    |> halt()
  end

  defp generate_csp_nonce do
    :crypto.strong_rand_bytes(16)
    |> Base.encode64()
    |> binary_part(0, 16)
  end

  defp inject_base_tag(content) do
    String.replace(
      content,
      ~r/<head>/i,
      "<head>\n  <base href=\"/\">"
    )
  end

  # CRITICAL: This is the import map injection feature not available in stock plug
  defp inject_import_map(content, nonce, rev) when is_binary(nonce) and is_binary(rev) do
    # Use rev-pinned SPA paths for import map entries
    base_path = "/__rev/#{rev}/spa/"

    import_map = """
    <script type="importmap" nonce="#{nonce}">
    {
      "imports": {
        "/routes/": "#{base_path}routes/",
        "/environments/": "#{base_path}environments/",
        "/services/": "#{base_path}services/",
        "/elements/": "#{base_path}elements/",
        "/styles/": "#{base_path}styles/",
        "/pages/": "#{base_path}pages/",
        "/images/": "#{base_path}images/"
      }
    }
    </script>
    """

    String.replace(
      content,
      ~r/(<base[^>]*>)/i,
      "\\1\n#{String.trim(import_map)}"
    )
  end

  defp static_asset_request?(request_path, patterns) do
    Enum.any?(patterns, &Regex.match?(&1, request_path))
  end

  defp default_static_patterns do
    [
      ~r{^/assets/},
      ~r{^/js/},
      ~r{^/css/},
      ~r{^/images/},
      ~r{\.js$},
      ~r{\.css$},
      ~r{\.png$},
      ~r{\.jpg$},
      ~r{\.svg$},
      ~r{\.json$},
      ~r{\.txt$},
      ~r{\.ico$},
      ~r{\.wasm$},
      ~r{\.webp$},
      ~r{\.map$}
    ]
  end
end
```

Then use it in your endpoint loader:

```elixir
defmodule MyApp.Outerfaces.EndpointLoader do
  alias Outerfaces.Odd.Plugs.OddRevProxyPlug
  alias Outerfaces.Odd.Plugs.OddRevCacheHeadersPlug
  alias Outerfaces.Odd.Plugs.OddRevEndpointPlug
  alias Outerfaces.Odd.Plugs.OddEnvironmentPlug
  alias MyApp.Outerfaces.CDNConsumerServeIndex  # <- Your extended version

  def prepare_endpoint_module(project_name, app_slug, endpoint_module, _opts) do
    project_path = Path.join([:code.priv_dir(app_slug), "static", "outerfaces", "projects", project_name])

    module_body = quote do
      use Phoenix.Endpoint, otp_app: unquote(app_slug)

      plug(Plug.Logger, log: :debug)

      # Rev plugs - MUST be first
      plug(OddRevProxyPlug, mismatch_behavior: :redirect)
      plug(OddRevCacheHeadersPlug)

      # Rev endpoint for service worker
      plug(OddRevEndpointPlug)

      # Environment config
      plug(OddEnvironmentPlug,
        protocol: "http",
        host_names: ["localhost"],
        cdn_port: 4001,
        ui_port: 4001,
        api_port: 4000
      )

      # Extended serve index with import map injection
      plug(CDNConsumerServeIndex,
        index_path: "#{unquote(project_path)}/index.rofl.html",
        static_root: unquote(project_path)
      )
    end

    Module.create(endpoint_module, module_body, Macro.Env.location(__ENV__))
  end
end
```

## Step 2: Create index.rofl.html

Rename `index.html` → `index.rofl.html` and add ESM structure:

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <title>My App</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <!-- Service worker registration -->
    <script type="module">
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('/service-worker.rofl.js');
      }
    </script>

    <!-- Main app entry point -->
    <script type="module" src="[OUTERFACES_ODD_SPA]/index.rofl.js"></script>
    <link rel="stylesheet" href="[OUTERFACES_ODD_SPA]/global-styles.css">
  </head>
  <body>
    <div id="app"></div>
  </body>
</html>
```

The import map will be injected automatically by `OddCDNConsumerServeIndex`.

## Step 3: Create Service Worker

Create `service-worker.rofl.js` in your project directory:

```javascript
const SW_BUILD_REV = '__OUTERFACES_REV__';
const CACHE_PREFIX = 'my-app-rev-';
const BOOTSTRAP_KEY = new Request('/', { method: 'GET' });
const REV_METADATA_KEY = '/__outerfaces__/rev.json';
const MAX_REV_CACHES = 3;

// Get current cached rev from metadata
async function getCurrentCachedRev() {
  const cache = await caches.open(getBootstrapCacheName());
  const response = await cache.match(REV_METADATA_KEY);
  if (!response) return null;

  try {
    const data = await response.json();
    return data.rev;
  } catch (error) {
    return null;
  }
}

// Store rev metadata in cache
async function storeRevMetadata(rev) {
  const cache = await caches.open(getBootstrapCacheName());
  const revData = { rev, cached_at: Date.now() };

  await cache.put(
    REV_METADATA_KEY,
    new Response(JSON.stringify(revData), {
      headers: { 'Content-Type': 'application/json' }
    })
  );
}

function getBootstrapCacheName() {
  return `${CACHE_PREFIX}bootstrap`;
}

function getRevCacheName(rev) {
  return `${CACHE_PREFIX}${rev}`;
}

// Install event - setup bootstrap cache
self.addEventListener('install', (event) => {
  console.log('[SW] Install event');
  self.skipWaiting();
});

// Activate event - claim clients and cleanup old caches
self.addEventListener('activate', (event) => {
  console.log('[SW] Activate event');
  event.waitUntil(
    (async () => {
      await self.clients.claim();

      // Cleanup old rev caches
      const cacheNames = await caches.keys();
      const revCaches = cacheNames
        .filter(name => name.startsWith(CACHE_PREFIX) && name !== getBootstrapCacheName())
        .sort()
        .reverse();

      if (revCaches.length > MAX_REV_CACHES) {
        const toDelete = revCaches.slice(MAX_REV_CACHES);
        await Promise.all(toDelete.map(name => caches.delete(name)));
      }
    })()
  );
});

// Fetch event - cache strategy based on URL pattern
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Skip non-GET requests
  if (event.request.method !== 'GET') {
    return;
  }

  // Rev-pinned assets - cache first
  if (url.pathname.startsWith('/__rev/')) {
    event.respondWith(handleRevPinnedAsset(event.request));
    return;
  }

  // Bootstrap (/, /index.html) - network first
  if (url.pathname === '/' || url.pathname === '/index.html') {
    event.respondWith(handleBootstrap(event.request));
    return;
  }

  // Everything else - network only
  event.respondWith(fetch(event.request));
});

async function handleRevPinnedAsset(request) {
  const url = new URL(request.url);
  const revMatch = url.pathname.match(/^\/__rev\/([^\/]+)\//);

  if (!revMatch) {
    return fetch(request);
  }

  const requestedRev = revMatch[1];
  const cacheName = getRevCacheName(requestedRev);
  const cache = await caches.open(cacheName);

  // Try cache first
  const cached = await cache.match(request);
  if (cached) {
    return cached;
  }

  // Fetch and cache if same rev as current
  const response = await fetch(request);

  // Only cache successful, same-origin responses
  if (response.ok && response.type === 'basic') {
    cache.put(request, response.clone());
  }

  return response;
}

async function handleBootstrap(request) {
  try {
    // Always fetch fresh bootstrap
    const response = await fetch(request, { cache: 'no-store' });

    if (response.ok) {
      // Cache at canonical key
      const cache = await caches.open(getBootstrapCacheName());
      await cache.put(BOOTSTRAP_KEY, response.clone());

      // Check for rev update
      const revHeader = response.headers.get('x-outerfaces-rev');
      if (revHeader) {
        await checkRevUpdate(revHeader);
      }
    }

    return response;
  } catch (error) {
    // Fallback to cached bootstrap
    const cache = await caches.open(getBootstrapCacheName());
    const cached = await cache.match(BOOTSTRAP_KEY);
    return cached || new Response('Offline', { status: 503 });
  }
}

async function checkRevUpdate(newRev) {
  const cachedRev = await getCurrentCachedRev();

  if (cachedRev && cachedRev !== newRev) {
    // Rev mismatch - reload all clients
    const clients = await self.clients.matchAll({ includeUncontrolled: true });
    for (const client of clients) {
      client.postMessage({ type: 'RELOAD', reason: 'REV_MISMATCH', from: cachedRev, to: newRev });
    }
  }

  // Store new rev
  await storeRevMetadata(newRev);
}

// Message handler for client-initiated update checks
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'CHECK_FOR_UPDATE') {
    event.waitUntil(
      (async () => {
        const response = await fetch('/__outerfaces__/rev.json', { cache: 'no-store' });
        if (response.ok) {
          const data = await response.json();
          await checkRevUpdate(data.rev);
        }
      })()
    );
  }
});
```

## Step 4: Update mix.exs with Helpers

Add these aliases to your `mix.exs`:

```elixir
defp aliases do
  [
    # ... existing aliases ...

    dist: [
      "outerfaces.dist",
      "outerfaces.remove_js_comments dir=\"priv/static/outerfaces/projects/my_client_app\""
    ],
    vendor_outerfaces_js: [
      "outerfaces.into_odd_cdn source_base_path=\"/path/to/outerfaces/repos\" target_base_path=\"/path/to/your/app\""
    ]
  ]
end
```

## Step 5: Distribution

Run the distribution command to copy project files:

```bash
mix dist
```

This will:
1. Copy your project files from `outerfaces/` to `priv/static/outerfaces/`
2. Remove JS comments for production optimization

### Optional: Vendor JavaScript Libraries

If your app uses external JavaScript libraries like `outerfaces_js_core`, add a vendor alias:

```elixir
vendor_outerfaces_js: [
  "outerfaces.into_odd_cdn source_base_path=\"/path/to/outerfaces/repos\" target_base_path=\"/path/to/your/app\""
]
```

Then run:
```bash
mix vendor_outerfaces_js
mix dist
```

This copies libraries into `priv/static/outerfaces/projects/odd_cdn/`.

## Step 6: Set OUTERFACES_REV Environment Variable

For production deployments, set the revision:

```bash
export OUTERFACES_REV=$(git rev-parse --short HEAD)
```

The framework will automatically:
- Fall back to git SHA if not set
- Use timestamp for local development without git

## How It Works

### URL Structure
- **Bootstrap (unversioned)**: `/` → Always serves current rev
- **Rev-pinned assets**: `/__rev/<rev>/spa/file.js` → Immutable, cached forever
- **Rev endpoint**: `/__outerfaces__/rev.json` → Current rev for service worker checks

### Import Map Injection
The `OddCDNConsumerServeIndex` plug automatically injects:

```html
<script type="importmap" nonce="...">
{
  "imports": {
    "/routes/": "/__rev/abc123/spa/routes/",
    "/services/": "/__rev/abc123/spa/services/",
    "/elements/": "/__rev/abc123/spa/elements/"
  }
}
</script>
```

This allows your code to use bare imports:
```javascript
import { MyService } from '/services/my-service.js';
```

Which resolve to rev-pinned URLs:
```
/__rev/abc123/spa/services/my-service.js
```

### Cache Strategy
1. **Bootstrap** (`/`, `/index.html`): Network-first with cache fallback
2. **Rev-pinned assets** (`/__rev/<rev>/spa/...`): Cache-first, immutable
3. **Rev mismatch**: Service worker detects and triggers page reload
4. **Cache cleanup**: Old rev caches auto-deleted (keeps last 3)

## Verification

1. Start your app: `iex -S mix`
2. Visit http://localhost:4000
3. Open DevTools → Application → Service Workers (verify registered)
4. Open DevTools → Application → Cache Storage (verify rev-pinned caches)
5. Check Network tab for rev-pinned URLs: `/__rev/<rev>/spa/...`
6. Verify `/__outerfaces__/rev.json` endpoint returns current rev

## Troubleshooting

### Service worker not registering
- Check console for errors
- Verify `/service-worker.rofl.js` is accessible
- Ensure HTTPS or localhost (service workers require secure context)

### Import map not injected
- Verify `index.rofl.html` extension (not `.html`)
- Check that `OddCDNConsumerServeIndex` is in plug pipeline
- Verify plug order (must be after `OddRevProxyPlug`)

### Assets not caching
- Check that URLs start with `/__rev/<rev>/spa/`
- Verify `OddRevProxyPlug` is first in pipeline
- Check `OddRevCacheHeadersPlug` is installed

### Rev mismatch not reloading
- Verify `OddRevEndpointPlug` is in pipeline
- Check `/__outerfaces__/rev.json` returns correct rev
- Verify service worker message handler for `CHECK_FOR_UPDATE`
```

