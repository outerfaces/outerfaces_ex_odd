# Server-Sent Routes and Gated Files

A shell normally ships every route in a routes module and serves every page
module to anyone. That exposes the whole application's shape to visitors who
aren't signed in, even when its API refuses them everything. Hiding only the
route list doesn't help: the modules are still one request away. The server
has to decide both which routes a visitor gets and which files they may fetch.

`Outerfaces.Odd.RouteManifest` and `Outerfaces.Odd.Plugs.OddRouteAccessPlug`
do that from one file, so one project serves signed-out and signed-in
visitors alike.

## The manifest

`routes.manifest.json` in the project, read by the server and never served:

```json
{
  "default_access": "signed_in",
  "title_suffix": " | Example",
  "sign_in": {"grant": "signed_in", "path": "/sign-in", "return_param": "next"},
  "public_files": ["index.js", "global-styles.css", "styles/", "images/"],
  "entries": {"signed_in": ["/elements/index.js"]},
  "routes": [
    {"app_path": "/", "page_path": "/pages/home-page.js", "slug": "home", "title": "Home"},
    {"app_path": "/sign-in", "page_path": "/pages/sign-in-page.js", "slug": "sign_in",
     "title": "Sign in", "access": "public"}
  ]
}
```

- **Grants** are strings a request holds (`"signed_in"`, a permission, a
  plan), decided by your application; `"public"` is always held. A route is
  visible when its `access` (else `default_access`, else `"public"`) is held.
- **`sign_in`**: a visitor without its grant who asks for anything outside
  their routes is sent there. Missing and hidden routes answer alike.
- **`public_files`**: the roots and static assets anyone may fetch (a file, or
  a folder ending in `/`). The modules they import, and those the public
  routes' pages import, are public too: the closure is read from the files as
  served, so bundling and hashed chunk names don't change it. Every other file
  needs `files_access` (default `default_access`). Leave `public_files` out
  and every file is public.
- **`entries`**: per grant, modules the shell imports at start, for code only
  some visitors should get.

## The plug

```elixir
plug OddRouteAccessPlug,
  manifest: Path.join(project_path, "routes.manifest.json"),
  static_root: project_path,
  grants: {MyApp.ShellGrants, :grants, []}
```

Place it after the rev and environment plugs and before the plug that serves
the shell. `grants` is called with the conn and returns the request's grants.
If a proxy computes them, read them from a header that only the proxy sets.

- A file the visitor may not fetch gets the same 404 as a missing file. The
  manifest is never served.
- A file only some visitors may fetch is marked
  `conn.assigns.outerfaces_private_asset`; `OddRevCacheHeadersPlug` then sends
  `Cache-Control: private` instead of `public`.
- For a shell request it assigns `outerfaces_route_status` (`{:ok, route}`,
  `:sign_in`, `{:forbidden, route}` or `:not_found`) and
  `outerfaces_route_payload`. Your serving plug sets the status from the first
  (for example 200, 401, 403, 404) and writes the payload into the shell with
  `RouteManifest.inject/2`, as `<script type="application/json"
  id="outerfaces-routes">`.

## The browser

outerfaces_js_core reads the payload and starts the router from it:

```js
const manifest = readRouteManifest();
await useRouteManifest(manifest);
navigationService.navigate(window.location.pathname);
```

While `sign_in` is set, a path outside the visitor's routes goes to the
sign-in route with the return parameter. Reload the page after signing in or
out, so the next shell carries the new routes.

## Building

A bundler must treat each `entries` module as an entry point, since nothing
imports them by name. Never cache the shell HTML across sessions; it differs
per visitor.
