defmodule Outerfaces.RevScopeTest do
  # Revs live in :persistent_term, global to the VM.
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Outerfaces.Odd.Plugs.{OddRevEndpointPlug, OddRevProxyPlug}
  alias Outerfaces.Rev

  setup do
    global = :persistent_term.get(:outerfaces_rev_current, nil)
    Rev.set_rev("global-1")
    Rev.clear_scoped_revs()

    on_exit(fn ->
      Rev.clear_scoped_revs()
      if global, do: Rev.set_rev(global), else: Rev.invalidate_cache()
    end)
  end

  def rev_meta(tag), do: %{"release" => %{"channel" => tag}}

  describe "scoped revs" do
    test "a scope reads its own rev; others, and nil, read the global one" do
      :ok = Rev.set_rev(:site_a, "3-aaaa")
      assert Rev.current_rev(:site_a) == "3-aaaa"
      assert Rev.current_rev(:site_b) == "global-1"
      assert Rev.current_rev(nil) == "global-1"
      assert Rev.current_rev() == "global-1"
    end

    test "setting one scope leaves the global rev and other scopes alone" do
      Rev.set_rev(:site_a, "3-aaaa")
      Rev.set_rev(:site_b, "8-bbbb")
      Rev.set_rev(:site_a, "4-aaab")
      assert Rev.scoped_revs() == %{site_a: "4-aaab", site_b: "8-bbbb"}
      assert Rev.current_rev() == "global-1"
    end

    test "clearing the scopes falls every scope back to the global rev" do
      Rev.set_rev(:site_a, "3-aaaa")
      Rev.clear_scoped_revs()
      assert Rev.current_rev(:site_a) == "global-1"
    end
  end

  describe "OddRevProxyPlug with :rev_scope" do
    defp proxy(path, opts) do
      conn(:get, path) |> OddRevProxyPlug.call(OddRevProxyPlug.init(opts))
    end

    test "a URL pinned to the scope's rev passes, stripped, with the rev assigned" do
      Rev.set_rev(:site_a, "3-aaaa")
      conn = proxy("/__rev/3-aaaa/spa/app.js", rev_scope: :site_a)
      refute conn.halted
      assert conn.request_path == "/app.js"
      assert conn.assigns.outerfaces_rev == "3-aaaa"
      assert conn.assigns.outerfaces_rev_matched
    end

    test "the global rev is a mismatch for a scope with its own rev" do
      Rev.set_rev(:site_a, "3-aaaa")
      conn = proxy("/__rev/global-1/spa/app.js", rev_scope: :site_a)
      assert conn.halted
      assert conn.status == 409
      assert conn.assigns.outerfaces_rev_current == "3-aaaa"
    end

    test "a path without a rev is pinned to the scope's rev for the plugs after it" do
      Rev.set_rev(:site_a, "3-aaaa")
      conn = proxy("/", rev_scope: :site_a)
      refute conn.halted
      assert conn.assigns.outerfaces_rev == "3-aaaa"
    end

    test "without :rev_scope nothing changes: the global rev, no assign on plain paths" do
      Rev.set_rev(:site_a, "3-aaaa")
      assert proxy("/__rev/global-1/spa/app.js", []).assigns.outerfaces_rev_matched
      refute Map.has_key?(proxy("/", []).assigns, :outerfaces_rev)
    end
  end

  describe "OddRevEndpointPlug" do
    defp rev_json(opts) do
      conn =
        conn(:get, "/__outerfaces__/rev.json")
        |> OddRevEndpointPlug.call(OddRevEndpointPlug.init(opts))

      {conn, Jason.decode!(conn.resp_body)}
    end

    test "answers the scope's rev with :rev_scope, the global one without" do
      Rev.set_rev(:site_a, "3-aaaa")
      assert {_, %{"rev" => "3-aaaa"}} = rev_json(rev_scope: :site_a)
      assert {_, %{"rev" => "global-1"}} = rev_json([])
    end

    test ":metadata adds its map under meta; without it there is no meta" do
      {conn, body} = rev_json(metadata: {__MODULE__, :rev_meta, ["beta"]})
      assert body["meta"] == %{"release" => %{"channel" => "beta"}}
      assert get_resp_header(conn, "cache-control") == ["no-store, no-cache, must-revalidate"]

      {_, plain} = rev_json([])
      refute Map.has_key?(plain, "meta")
    end

    test "other paths pass through" do
      conn = conn(:get, "/") |> OddRevEndpointPlug.call(OddRevEndpointPlug.init([]))
      refute conn.halted
    end
  end
end
