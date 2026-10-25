defmodule Outerfaces.Odd.RouteManifestTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Outerfaces.Odd.RouteManifest
  alias Outerfaces.Odd.Plugs.OddRouteAccessPlug
  alias Outerfaces.Odd.Plugs.OddRevCacheHeadersPlug

  @manifest %{
    "default_access" => "signed_in",
    "title_suffix" => " | App",
    "sign_in" => %{"grant" => "signed_in", "path" => "/sign-in", "return_param" => "next"},
    "public_files" => ["index.js", "styles/", "pages/sign-in-page.js"],
    "entries" => %{"signed_in" => ["/elements/index.js"]},
    "routes" => [
      %{
        "app_path" => "/",
        "page_path" => "/pages/home-page.js",
        "slug" => "home",
        "title" => "Home"
      },
      %{
        "app_path" => "/sign-in",
        "page_path" => "/pages/sign-in-page.js",
        "slug" => "sign_in",
        "title" => "Sign in",
        "access" => "public"
      },
      %{
        "app_path" => "/reports/:id",
        "page_path" => "/pages/report-page.js",
        "slug" => "report",
        "title" => "Report",
        "access" => "reports:read"
      },
      %{
        "app_path" => "/not-found",
        "page_path" => "/pages/not-found-page.js",
        "slug" => "not_found"
      }
    ]
  }

  describe "routes" do
    test "a visitor sees the routes their grants reach" do
      assert slugs(RouteManifest.visible_routes(@manifest, [])) == ["sign_in"]

      assert slugs(RouteManifest.visible_routes(@manifest, ["signed_in"])) ==
               ["home", "sign_in", "not_found"]

      assert slugs(RouteManifest.visible_routes(@manifest, ["signed_in", "reports:read"])) ==
               ["home", "sign_in", "report", "not_found"]
    end

    test "signed out, a hidden route and a missing one answer alike" do
      assert RouteManifest.route_status(@manifest, "/", []) == :sign_in
      assert RouteManifest.route_status(@manifest, "/reports/7", []) == :sign_in
      assert RouteManifest.route_status(@manifest, "/nowhere", []) == :sign_in

      assert {:ok, %{"slug" => "sign_in"}} =
               RouteManifest.route_status(@manifest, "/sign-in/", [])
    end

    test "signed in, a route without its grant is forbidden and a missing one not found" do
      assert {:ok, %{"slug" => "home"}} =
               RouteManifest.route_status(@manifest, "/", ["signed_in"])

      assert {:forbidden, %{"slug" => "report"}} =
               RouteManifest.route_status(@manifest, "/reports/7", ["signed_in"])

      assert RouteManifest.route_status(@manifest, "/nowhere", ["signed_in"]) == :not_found
    end

    test "the payload carries the visitor's routes, entries and sign-in" do
      out = RouteManifest.client_payload(@manifest, [])
      assert [%{"slug" => "sign_in", "title" => "Sign in | App"} = route] = out["routes"]
      refute Map.has_key?(route, "access")
      assert out["entries"] == []
      assert out["sign_in"]["path"] == "/sign-in"

      signed_in = RouteManifest.client_payload(@manifest, ["signed_in"])
      assert signed_in["entries"] == ["/elements/index.js"]
      assert signed_in["sign_in"] == nil
      assert %{"title" => nil} = Enum.find(signed_in["routes"], &(&1["slug"] == "not_found"))
    end

    test "the payload can't close the script element it is written into" do
      manifest = put_in(@manifest, ["routes", Access.at(1), "title"], "</script><b>")
      html = RouteManifest.inject("<head></head>", RouteManifest.client_payload(manifest, []))

      assert [_] = Regex.scan(~r{</script>}, html)
      assert html =~ ~s(<script type="application/json" id="outerfaces-routes">)
    end

    test "without public_files every file is public" do
      manifest = Map.delete(@manifest, "public_files")
      assert RouteManifest.file_allowed?(manifest, "pages/report-page.js", [])
    end

    test "files outside public_files need the files grant" do
      assert RouteManifest.file_allowed?(@manifest, "styles/app.css", [])
      assert RouteManifest.file_allowed?(@manifest, "/index.js", [])
      refute RouteManifest.file_allowed?(@manifest, "pages/home-page.js", [])
      refute RouteManifest.file_allowed?(@manifest, "index.js.map", [])
      assert RouteManifest.file_allowed?(@manifest, "pages/home-page.js", ["signed_in"])
    end
  end

  describe "public_closure/2" do
    setup do
      root = Path.join(System.tmp_dir!(), "route-closure-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(root) end)

      write = fn path, body ->
        File.mkdir_p!(Path.dirname(Path.join(root, path)))
        File.write!(Path.join(root, path), body)
      end

      write.("index.js", "import { x } from './services/api.js';\nimport 'lib/shared.js';")
      write.("services/api.js", "export * from '../chunks/chunk-a.js';")
      write.("chunks/chunk-a.js", "export const x = 1;")
      write.("pages/sign-in-page.js", "import { form } from '/elements/sign-in.js';")
      write.("elements/sign-in.js", "const later = () => import('./two-factor.js');")
      write.("elements/two-factor.js", "")
      write.("pages/home-page.js", "import { nav } from '../elements/nav.js';")
      write.("elements/nav.js", "")
      write.("outside.js", "import '../../escape.js';")
      %{root: root, write: write}
    end

    test "follows the listed modules and the public pages, not bare or gated ones", %{root: root} do
      closure = RouteManifest.public_closure(@manifest, root)

      assert Enum.sort(closure) == [
               "chunks/chunk-a.js",
               "elements/sign-in.js",
               "elements/two-factor.js",
               "index.js",
               "pages/sign-in-page.js",
               "services/api.js"
             ]

      assert RouteManifest.file_allowed?(@manifest, "chunks/chunk-a.js", [], closure)
      refute RouteManifest.file_allowed?(@manifest, "elements/nav.js", [], closure)
    end

    test "is worked out again when a module in it changes", %{root: root, write: write} do
      refute "elements/nav.js" in RouteManifest.public_closure(@manifest, root)

      write.("elements/two-factor.js", "import './nav.js'; // changed")
      File.touch!(Path.join(root, "elements/two-factor.js"), System.os_time(:second) + 5)

      assert "elements/nav.js" in RouteManifest.public_closure(@manifest, root)
    end
  end

  describe "OddRouteAccessPlug" do
    setup do
      root = Path.join(System.tmp_dir!(), "route-access-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "pages"))
      File.write!(Path.join(root, "routes.manifest.json"), Jason.encode!(@manifest))
      File.write!(Path.join(root, "routes.manifest.json.gz"), "")
      File.write!(Path.join(root, "index.js"), "")
      File.write!(Path.join(root, "pages/home-page.js"), "")
      on_exit(fn -> File.rm_rf!(root) end)

      opts =
        OddRouteAccessPlug.init(
          manifest: Path.join(root, "routes.manifest.json"),
          static_root: root,
          grants: {__MODULE__, :grants_from_header, []}
        )

      %{opts: opts}
    end

    test "a gated file is a 404 to a visitor without the grant", %{opts: opts} do
      conn = OddRouteAccessPlug.call(conn(:get, "/pages/home-page.js"), opts)
      assert conn.halted and conn.status == 404
      assert conn.resp_body == "File not found"
    end

    test "a gated file passes with the grant, marked private", %{opts: opts} do
      conn = OddRouteAccessPlug.call(signed_in(conn(:get, "/pages/home-page.js")), opts)
      refute conn.halted
      assert conn.assigns.outerfaces_private_asset
    end

    test "a public file passes for anyone, unmarked", %{opts: opts} do
      conn = OddRouteAccessPlug.call(conn(:get, "/index.js"), opts)
      refute conn.halted
      refute Map.has_key?(conn.assigns, :outerfaces_private_asset)
    end

    test "the manifest is never served", %{opts: opts} do
      for path <- ["/routes.manifest.json", "/routes.manifest.json.gz"] do
        conn = OddRouteAccessPlug.call(signed_in(conn(:get, path)), opts)
        assert conn.halted and conn.status == 404
      end
    end

    test "a path that steps out of a public folder is judged by the file it reaches", %{
      opts: opts
    } do
      # styles/ is public; the page it reaches is gated.
      conn = OddRouteAccessPlug.call(conn(:get, "/styles/../pages/home-page.js"), opts)
      assert conn.halted and conn.status == 404

      conn = OddRouteAccessPlug.call(signed_in(conn(:get, "/styles/../pages/home-page.js")), opts)
      refute conn.halted
      assert conn.assigns.outerfaces_private_asset
    end

    test "the manifest is never served by a path that reaches it indirectly", %{opts: opts} do
      for path <- ["/pages/../routes.manifest.json", "/styles/../routes.manifest.json.gz"] do
        conn = OddRouteAccessPlug.call(signed_in(conn(:get, path)), opts)
        assert conn.halted and conn.status == 404
      end
    end

    test "a rev-pinned path the rev plug has not stripped is refused", %{opts: opts} do
      # Placed before OddRevProxyPlug, the gate would otherwise pass these as
      # shell requests and the rev plug would serve the gated page.
      for path <- [
            "/__rev/abc123/spa/pages/home-page.js",
            "/__rev/abc123/cdn/styles/app.css",
            "/__rev",
            "//__rev/abc123/spa/pages/home-page.js",
            "/styles/../__rev/abc123/spa/pages/home-page.js"
          ],
          grant <- [&Function.identity/1, &signed_in/1] do
        # Set as the server would; conn/2 would read "//__rev/..." as a host.
        conn = OddRouteAccessPlug.call(grant.(%{conn(:get, "/") | request_path: path}), opts)
        assert conn.halted and conn.status == 404, "#{path} was not refused"
      end
    end

    test "a shell request carries its status and payload", %{opts: opts} do
      conn = OddRouteAccessPlug.call(conn(:get, "/reports/7"), opts)
      refute conn.halted
      assert conn.assigns.outerfaces_route_status == :sign_in
      assert slugs(conn.assigns.outerfaces_route_payload["routes"]) == ["sign_in"]

      conn = OddRouteAccessPlug.call(signed_in(conn(:get, "/")), opts)
      assert {:ok, %{"slug" => "home"}} = conn.assigns.outerfaces_route_status
    end

    test "a private file is cached privately", %{opts: opts} do
      conn =
        conn(:get, "/pages/home-page.js")
        |> signed_in()
        |> assign(:outerfaces_rev_matched, true)
        |> OddRevCacheHeadersPlug.call([])
        |> OddRouteAccessPlug.call(opts)
        |> put_resp_content_type("text/javascript")
        |> send_resp(200, "")

      assert get_resp_header(conn, "cache-control") == ["private, max-age=31536000, immutable"]
    end
  end

  def grants_from_header(conn) do
    case get_req_header(conn, "x-test-grants") do
      [value] -> String.split(value, ",", trim: true)
      _ -> []
    end
  end

  defp signed_in(conn), do: put_req_header(conn, "x-test-grants", "signed_in")

  defp slugs(routes), do: Enum.map(routes, & &1["slug"])
end
