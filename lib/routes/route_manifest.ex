defmodule Outerfaces.Odd.RouteManifest do
  @moduledoc """
  A project's client routes, kept on the server and handed to each visitor
  filtered by what they may reach, with the same rules deciding which of the
  project's files they may fetch.

  The manifest is a JSON file in the project (`routes.manifest.json` by
  convention), read by the server and never served:

      {
        "default_access": "signed_in",
        "title_suffix": " | Example",
        "sign_in": {"grant": "signed_in", "path": "/sign-in", "return_param": "next"},
        "public_files": ["index.js", "styles/", "pages/sign-in-page.js"],
        "files_access": "signed_in",
        "entries": {"signed_in": ["/elements/index.js"]},
        "routes": [
          {"app_path": "/", "page_path": "/pages/home-page.js", "slug": "home", "title": "Home"},
          {"app_path": "/sign-in", "page_path": "/pages/sign-in-page.js", "slug": "sign_in",
           "title": "Sign in", "access": "public"}
        ]
      }

  **Grants** are strings a request holds, decided by the host application
  (`"signed_in"`, a permission name, a plan): `"public"` is always held. A
  route is visible when its `access` (else `default_access`, else `"public"`)
  is a held grant.

    * `sign_in`: a visitor without its `grant` who asks for any path outside
      their routes is sent to its `path`, with where they were going in
      `return_param`. Missing and hidden routes answer alike, so a signed-out
      visitor learns nothing about routes they can't see.
    * `public_files`: the files anyone may fetch (a name, or a folder ending in
      `/`), and with them every module they and the public routes' pages
      import (`public_closure/2`), read from the files as served, so a build
      that bundles or renames modules stays covered. Every other file needs
      `files_access` (default `default_access`). Without `public_files`, every
      file is public.
    * `entries`: per grant, modules the shell imports at start when the
      visitor holds it (code only a signed-in shell needs).
  """

  @typedoc "A decoded manifest, string keys as in the file."
  @type t :: map()

  @typedoc "What a request holds; `\"public\"` is always among them."
  @type grants :: [String.t()]

  @typedoc """
  What a path is to a visitor: one of their routes, a path for which they must
  sign in first, a route they can't reach, or nothing.
  """
  @type status :: {:ok, map()} | :sign_in | {:forbidden, map()} | :not_found

  @doc """
  Reads and decodes the manifest at `path`, cached until the file changes.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    path = Path.expand(path)

    with {:ok, %File.Stat{mtime: mtime, size: size}} <- File.stat(path) do
      key = {__MODULE__, path}

      case :persistent_term.get(key, nil) do
        {^mtime, ^size, manifest} ->
          {:ok, manifest}

        _ ->
          with {:ok, json} <- File.read(path),
               {:ok, manifest} when is_map(manifest) <- Jason.decode(json) do
            :persistent_term.put(key, {mtime, size, manifest})
            {:ok, manifest}
          else
            {:ok, _not_a_map} -> {:error, :invalid_manifest}
            error -> error
          end
      end
    end
  end

  @doc "As `load/1`, raising when the manifest can't be read."
  @spec load!(Path.t()) :: t()
  def load!(path) do
    case load(path) do
      {:ok, manifest} -> manifest
      {:error, reason} -> raise ArgumentError, "route manifest #{path}: #{inspect(reason)}"
    end
  end

  @doc "`grants` with `\"public\"`, each once."
  @spec grants([String.t()] | nil) :: grants()
  def grants(held), do: Enum.uniq(["public" | Enum.filter(held || [], &is_binary/1)])

  @doc "The routes a visitor holding `grants` may reach, in manifest order."
  @spec visible_routes(t(), grants()) :: [map()]
  def visible_routes(manifest, grants) do
    grants = grants(grants)
    Enum.filter(routes(manifest), &(access(manifest, &1) in grants))
  end

  @doc """
  What `request_path` is to a visitor holding `grants` (see `t:status/0`).
  """
  @spec route_status(t(), String.t(), grants()) :: status()
  def route_status(manifest, request_path, grants) do
    grants = grants(grants)
    route = Enum.find(routes(manifest), &route_match?(&1["app_path"], request_path))

    cond do
      route != nil and access(manifest, route) in grants -> {:ok, route}
      must_sign_in?(manifest, grants) -> :sign_in
      route != nil -> {:forbidden, route}
      true -> :not_found
    end
  end

  @doc """
  Whether a visitor holding `grants` may fetch the project file at
  `relative_path` (`"pages/home-page.js"`, no leading slash). `public` is the
  project's `public_closure/2`.
  """
  @spec file_allowed?(t(), String.t(), grants(), MapSet.t(String.t())) :: boolean()
  def file_allowed?(manifest, relative_path, grants, public \\ MapSet.new()) do
    public_file?(manifest, relative_path, public) or
      files_access(manifest) in grants(grants)
  end

  @doc """
  Whether anyone may fetch the file at `relative_path`: it is listed in
  `public_files`, or in `public` (the project's `public_closure/2`).
  """
  @spec public_file?(t(), String.t(), MapSet.t(String.t())) :: boolean()
  def public_file?(manifest, relative_path, public \\ MapSet.new()) do
    listed_public?(manifest, relative_path) or
      MapSet.member?(public, String.trim_leading(relative_path, "/"))
  end

  @doc """
  The modules a signed-out shell may load beyond those listed: the import
  closure of the listed `public_files` modules and of the pages of the routes
  anyone may reach, as relative paths under `root` (the served project).
  Relative (`./`, `../`) and root (`/elements/...`) specifiers are followed,
  through static imports, re-exports and literal dynamic imports; bare
  specifiers (shared libraries) are not. Cached, and worked out again when
  the manifest or any module in the closure changes.
  """
  @spec public_closure(t(), Path.t()) :: MapSet.t(String.t())
  def public_closure(manifest, root) do
    root = Path.expand(root)
    key = {__MODULE__, :closure, root}
    version = :erlang.phash2(manifest)

    case :persistent_term.get(key, nil) do
      {^version, stamps, closure} when is_map(stamps) ->
        if Enum.all?(stamps, fn {file, mtime} -> mtime(file) == mtime end),
          do: closure,
          else: put_closure(key, manifest, root)

      _ ->
        put_closure(key, manifest, root)
    end
  end

  defp put_closure(key, manifest, root) do
    files = closure_files(manifest, root)
    stamps = Map.new(files, &{&1, mtime(&1)})
    closure = MapSet.new(files, &Path.relative_to(&1, root))
    :persistent_term.put(key, {:erlang.phash2(manifest), stamps, closure})
    closure
  end

  defp closure_files(manifest, root) do
    listed =
      for entry <- manifest["public_files"] || [],
          not String.ends_with?(entry, "/"),
          do: Path.join(root, String.trim_leading(entry, "/"))

    pages =
      for route <- visible_routes(manifest, []),
          is_binary(route["page_path"]),
          do: Path.join(root, String.trim_leading(route["page_path"], "/"))

    (listed ++ pages)
    |> Enum.filter(&module?/1)
    |> Enum.reduce(MapSet.new(), &visit(&1, root, &2))
    |> MapSet.to_list()
  end

  @import_pattern ~r/(?:\bfrom\s*|\bimport\s*\(?\s*)["']((?:\.{1,2}\/|\/)[^"']+)["']/

  defp visit(file, root, seen) do
    if MapSet.member?(seen, file) or not File.regular?(file) do
      seen
    else
      seen = MapSet.put(seen, file)

      Regex.scan(@import_pattern, File.read!(file), capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&resolve(&1, file, root))
      |> Enum.filter(&(&1 && module?(&1)))
      |> Enum.reduce(seen, &visit(&1, root, &2))
    end
  end

  defp resolve("/" <> path, _file, root), do: inside(Path.expand(path, root), root)
  defp resolve(spec, file, root), do: inside(Path.expand(spec, Path.dirname(file)), root)

  defp inside(path, root), do: if(String.starts_with?(path, root <> "/"), do: path)

  defp module?(path), do: Path.extname(path) in ~w(.js .mjs)

  defp mtime(file) do
    case File.stat(file) do
      {:ok, %File.Stat{mtime: mtime, size: size}} -> {mtime, size}
      _ -> nil
    end
  end

  defp listed_public?(manifest, relative_path) do
    case manifest["public_files"] do
      nil ->
        true

      entries when is_list(entries) ->
        path = String.trim_leading(relative_path, "/")

        Enum.any?(entries, fn entry ->
          entry = String.trim_leading(entry, "/")

          if String.ends_with?(entry, "/"),
            do: String.starts_with?(path, entry),
            else: path == entry
        end)
    end
  end

  @doc """
  What the shell is given: the visitor's routes (titles with the suffix), the
  entries their grants open, and `sign_in` while they lack its grant.
  """
  @spec client_payload(t(), grants()) :: map()
  def client_payload(manifest, grants) do
    grants = grants(grants)
    suffix = manifest["title_suffix"] || ""

    %{
      "routes" =>
        for route <- visible_routes(manifest, grants) do
          route
          |> Map.take(~w(app_path page_path slug title))
          |> Map.update("title", nil, fn
            nil -> nil
            title -> title <> suffix
          end)
        end,
      "entries" => entries(manifest, grants),
      "sign_in" => if(must_sign_in?(manifest, grants), do: manifest["sign_in"])
    }
  end

  @doc """
  `html` with `payload` as `<script type="application/json"
  id="outerfaces-routes">`, just before `</head>`. The JSON is escaped so
  nothing in it can close the script element.
  """
  @spec inject(String.t(), map()) :: String.t()
  def inject(html, payload) do
    json = Jason.encode!(payload, escape: :html_safe)
    tag = ~s(<script type="application/json" id="outerfaces-routes">#{json}</script>)

    if Regex.match?(~r{</head>}i, html),
      do: String.replace(html, ~r{</head>}i, tag <> "\n</head>", global: false),
      else: tag <> html
  end

  @doc """
  Whether `request_path` is the route `app_path`: a `:name` segment matches
  any one non-empty segment, and a trailing slash is ignored.
  """
  @spec route_match?(String.t() | nil, String.t()) :: boolean()
  def route_match?(nil, _request_path), do: false

  def route_match?(app_path, request_path) do
    route_segments = String.split(app_path, "/", trim: true)
    path_segments = String.split(request_path, "/", trim: true)

    length(route_segments) == length(path_segments) and
      route_segments
      |> Enum.zip(path_segments)
      |> Enum.all?(fn
        {":" <> _name, _segment} -> true
        {same, same} -> true
        _ -> false
      end)
  end

  defp entries(manifest, grants) do
    for {grant, modules} <- manifest["entries"] || %{},
        grant in grants,
        module <- List.wrap(modules),
        uniq: true,
        do: module
  end

  defp routes(manifest), do: Enum.filter(manifest["routes"] || [], &is_map/1)

  defp access(manifest, route),
    do: route["access"] || manifest["default_access"] || "public"

  defp files_access(manifest),
    do: manifest["files_access"] || manifest["default_access"] || "public"

  defp must_sign_in?(manifest, grants) do
    case manifest["sign_in"] do
      %{"grant" => grant, "path" => path} when is_binary(grant) and is_binary(path) ->
        grant not in grants

      _ ->
        false
    end
  end
end
