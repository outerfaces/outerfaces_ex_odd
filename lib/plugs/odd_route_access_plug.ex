defmodule Outerfaces.Odd.Plugs.OddRouteAccessPlug do
  @moduledoc """
  Applies a project's route manifest (`Outerfaces.Odd.RouteManifest`) to each
  request, before the plug that serves the shell and its files.

      plug OddRouteAccessPlug,
        manifest: "priv/static/projects/app/routes.manifest.json",
        static_root: "priv/static/projects/app",
        grants: {MyApp.ShellAccess, :grants, []}

  `grants` is an `{module, function, args}` called with the conn prepended,
  returning the strings the request holds (`["signed_in", "reports:read"]`).
  It is called once per request.

    * A file is judged by the path it reaches once `.` and `..` are resolved,
      never by the path as sent.
    * A path still under `/__rev/` is refused with a 404: `OddRevProxyPlug`
      must run first, and strips that prefix from every path it accepts.
      Judged unstripped, `/__rev/<rev>/spa/pages/x.js` is no project file, so
      it would pass as a shell request and the rev plug would then serve the
      gated `pages/x.js`; refusing it makes the wrong plug order fail closed.
    * Files anyone may fetch are those the manifest lists and their import
      closure with the public routes' pages (`RouteManifest.public_closure/2`).
    * A request for a file of the project that the visitor may not fetch gets
      the same 404 as a missing file, so it doesn't say the file exists. The
      manifest itself (and any compressed copy of it) is never served.
    * A file only some visitors may fetch is marked
      `conn.assigns.outerfaces_private_asset`, which `OddRevCacheHeadersPlug`
      turns into `Cache-Control: private`, so no shared cache keeps it.
    * Any other request (the shell) gets
      `conn.assigns.outerfaces_route_status` (`t:Outerfaces.Odd.RouteManifest.status/0`)
      and `conn.assigns.outerfaces_route_payload`, for the serving plug to set
      the status and hand the shell its routes (`RouteManifest.inject/2`).

  Both the manifest and the grants are also assigned
  (`outerfaces_route_manifest`, `outerfaces_route_grants`).
  """

  import Plug.Conn

  alias Outerfaces.Odd.RouteManifest

  @behaviour Plug

  @impl true
  def init(opts) do
    manifest = opts |> Keyword.fetch!(:manifest) |> Path.expand()
    static_root = opts |> Keyword.fetch!(:static_root) |> Path.expand()
    {module, function, args} = Keyword.fetch!(opts, :grants)

    %{
      manifest: manifest,
      static_root: static_root,
      manifest_relative: Path.relative_to(manifest, static_root),
      grants: {module, function, args}
    }
  end

  @impl true
  def call(conn, %{manifest: manifest_path, grants: {module, function, args}} = opts) do
    manifest = RouteManifest.load!(manifest_path)
    grants = RouteManifest.grants(apply(module, function, [conn | args]))

    conn =
      conn
      |> assign(:outerfaces_route_manifest, manifest)
      |> assign(:outerfaces_route_grants, grants)

    # The file a path reaches, not the path as sent: `styles/../pages/x.js` is
    # judged as `pages/x.js`, so a public folder can't lend its rule to a
    # gated file, and no spelling of the manifest's path serves it.
    relative = project_relative(conn.request_path, opts.static_root)

    cond do
      rev_prefixed?(relative) ->
        not_found(conn)

      manifest_file?(relative, opts.manifest_relative) ->
        not_found(conn)

      project_file?(relative, opts.static_root) ->
        public = RouteManifest.public_closure(manifest, opts.static_root)

        cond do
          not RouteManifest.file_allowed?(manifest, relative, grants, public) -> not_found(conn)
          RouteManifest.public_file?(manifest, relative, public) -> conn
          true -> assign(conn, :outerfaces_private_asset, true)
        end

      true ->
        conn
        |> assign(
          :outerfaces_route_status,
          RouteManifest.route_status(manifest, conn.request_path, grants)
        )
        |> assign(:outerfaces_route_payload, RouteManifest.client_payload(manifest, grants))
    end
  end

  # The request path relative to the project root after `.` and `..` are
  # resolved; a path that would leave the root keeps its own spelling, which
  # matches no project file.
  defp project_relative(request_path, root) do
    relative = String.trim_leading(request_path, "/")

    with false <- relative == "",
         false <- String.contains?(relative, [<<0>>, "\\", ":"]),
         expanded <- Path.expand(relative, root),
         true <- String.starts_with?(expanded, root <> "/") do
      Path.relative_to(expanded, root)
    else
      _ -> relative
    end
  end

  # A rev-pinned path the rev plug hasn't stripped (it runs after this one).
  defp rev_prefixed?(relative), do: relative == "__rev" or String.starts_with?(relative, "__rev/")

  defp manifest_file?(relative, manifest_relative),
    do: relative == manifest_relative or String.starts_with?(relative, manifest_relative <> ".")

  # A regular file inside the project (never a path that leaves it).
  defp project_file?(relative, root) do
    with false <- relative == "",
         false <- String.contains?(relative, [<<0>>, "\\", ":"]),
         candidate <- Path.expand(relative, root),
         true <- String.starts_with?(candidate, root <> "/") do
      File.regular?(candidate)
    else
      _ -> false
    end
  end

  defp not_found(conn) do
    conn
    |> send_resp(404, "File not found")
    |> halt()
  end
end
