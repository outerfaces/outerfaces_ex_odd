defmodule Outerfaces.Odd.Plugs.OddCDNRoflJSPlug do
  @moduledoc """
  Transforms JavaScript import/export statements by rewriting CDN and SPA tokens.

  Supports both legacy and new token patterns:
  - [OUTERFACES_LOCAL_CDN] - DEPRECATED, aliased to [OUTERFACES_ODD_CDN]
  - [OUTERFACES_ODD_CDN] - Dual-mode: rev-pinned or absolute URLs
  - [OUTERFACES_ODD_SPA] - Always rev-pinned

  Dual-mode behavior:
  - When conn.assigns.outerfaces_rev is present: rev-pinned URLs (/__rev/<rev>/cdn/...)
  - Otherwise: absolute URLs (http://localhost:60032/...)
  """

  alias Outerfaces.Rev

  # Legacy regex (still works via ODD|LOCAL alternation below)
  @local_cdn_imports_regex ~r/import\s+\{\s*([\s\S]*?)\s*\}\s+from\s+['"][^'"]*\[OUTERFACES_LOCAL_CDN\]\/([^'"]*)['"]\s*;?/is
  @local_cdn_exports_regex ~r/export\s+(?:\{\s*([\s\S]*?)\s*\}|\*(?:\s+as\s+(\w+))?)\s+from\s+['"][^'"]*\[OUTERFACES_LOCAL_CDN\]\/([^'"]*)['"]\s*;?/is

  # New regex patterns (support both ODD and LOCAL for backward compatibility)
  # Named imports: import { foo, bar } from "..."
  @odd_cdn_imports_regex ~r/import\s+\{\s*([\s\S]*?)\s*\}\s+from\s+['"][^'"]*\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^'"]*)['"]\s*;?/is
  @odd_cdn_exports_regex ~r/export\s+(?:\{\s*([\s\S]*?)\s*\}|\*(?:\s+as\s+(\w+))?)\s+from\s+['"][^'"]*\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^'"]*)['"]\s*;?/is
  @odd_spa_imports_regex ~r/import\s+\{\s*([\s\S]*?)\s*\}\s+from\s+['"][^'"]*\[OUTERFACES_ODD_SPA\]\/([^'"]*)['"]\s*;?/is
  @odd_spa_exports_regex ~r/export\s+(?:\{\s*([\s\S]*?)\s*\}|\*(?:\s+as\s+(\w+))?)\s+from\s+['"][^'"]*\[OUTERFACES_ODD_SPA\]\/([^'"]*)['"]\s*;?/is

  # Additional ESM syntax patterns (D2: expanded coverage)
  # Default imports: import X from "..."
  @odd_cdn_default_imports_regex ~r/import\s+(\w+)\s+from\s+['"][^'"]*\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^'"]*)['"]\s*;?/i
  @odd_spa_default_imports_regex ~r/import\s+(\w+)\s+from\s+['"][^'"]*\[OUTERFACES_ODD_SPA\]\/([^'"]*)['"]\s*;?/i

  # Namespace imports: import * as X from "..."
  @odd_cdn_namespace_imports_regex ~r/import\s+\*\s+as\s+(\w+)\s+from\s+['"][^'"]*\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^'"]*)['"]\s*;?/i
  @odd_spa_namespace_imports_regex ~r/import\s+\*\s+as\s+(\w+)\s+from\s+['"][^'"]*\[OUTERFACES_ODD_SPA\]\/([^'"]*)['"]\s*;?/i

  # Side-effect imports: import "..."
  @odd_cdn_side_effect_imports_regex ~r/import\s+['"][^'"]*\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^'"]*)['"]\s*;?/i
  @odd_spa_side_effect_imports_regex ~r/import\s+['"][^'"]*\[OUTERFACES_ODD_SPA\]\/([^'"]*)['"]\s*;?/i

  @spec transform_javascript_cdn_imports_and_exports(
          file_content :: String.t(),
          cdn_service_host_name :: String.t(),
          cdn_service_host_port :: integer(),
          url_scheme :: String.t()
        ) :: String.t()
  def transform_javascript_cdn_imports_and_exports(
        file_content,
        cdn_service_host_name,
        cdn_service_host_port,
        url_scheme
      ) do
    cdn_base_url = "#{url_scheme}://#{cdn_service_host_name}:#{cdn_service_host_port}"
    transform_javascript_cdn_imports_and_exports_with_base_url(file_content, cdn_base_url)
  end

  @spec transform_javascript_cdn_imports_and_exports_with_base_url(
          file_content :: String.t(),
          cdn_base_url :: String.t()
        ) :: String.t()
  def transform_javascript_cdn_imports_and_exports_with_base_url(
        file_content,
        cdn_base_url
      ) do
    content = normalize_newlines(file_content)

    content
    |> replace_cdn_imports_with_base_url(cdn_base_url)
    |> replace_cdn_exports_with_base_url(cdn_base_url)
  end

  @spec normalize_newlines(String.t()) :: String.t()
  def normalize_newlines(content), do: String.replace(content, "\r\n", "\n")

  @spec replace_cdn_imports(
          file_body :: String.t(),
          cdn_protocol :: String.t(),
          cdn_host :: String.t(),
          cdn_port :: integer()
        ) :: String.t()
  def replace_cdn_imports(
        file_body,
        cdn_protocol,
        cdn_host,
        cdn_port
      )
      when is_binary(file_body) and
             is_binary(cdn_protocol) and
             is_binary(cdn_host) and
             is_integer(cdn_port) do
    replacement = "import {\\1} from '#{cdn_protocol}://#{cdn_host}:#{cdn_port}/\\2'"

    Regex.replace(
      @local_cdn_imports_regex,
      file_body,
      replacement
    )
  end

  @spec replace_cdn_exports(
          file_body :: String.t(),
          cdn_protocol :: String.t(),
          cdn_host :: String.t(),
          cdn_port :: integer()
        ) :: String.t()
  def replace_cdn_exports(
        file_body,
        cdn_protocol,
        cdn_host,
        cdn_port
      )
      when is_binary(file_body) and
             is_binary(cdn_protocol) and
             is_binary(cdn_host) and
             is_integer(cdn_port) do
    cdn_base_url = "#{cdn_protocol}://#{cdn_host}:#{cdn_port}"
    replace_cdn_exports_with_base_url(file_body, cdn_base_url)
  end

  # New functions that work with base URL (supports both absolute and proxy-relative URLs)
  @spec replace_cdn_imports_with_base_url(file_body :: String.t(), cdn_base_url :: String.t()) ::
          String.t()
  def replace_cdn_imports_with_base_url(file_body, cdn_base_url)
      when is_binary(file_body) and is_binary(cdn_base_url) do
    Regex.replace(
      @local_cdn_imports_regex,
      file_body,
      "import {\\1} from '#{cdn_base_url}/\\2'"
    )
  end

  @spec replace_cdn_exports_with_base_url(file_body :: String.t(), cdn_base_url :: String.t()) ::
          String.t()
  def replace_cdn_exports_with_base_url(file_body, cdn_base_url)
      when is_binary(file_body) and is_binary(cdn_base_url) do
    Regex.replace(
      @local_cdn_exports_regex,
      file_body,
      fn _match, g1, g2, g3 ->
        # g1 = named exports or empty
        # g2 = namespace name (for "* as name") or empty
        # g3 = file path
        cond do
          g1 != "" -> "export {#{g1}} from '#{cdn_base_url}/#{g3}'"
          g2 != "" -> "export * as #{g2} from '#{cdn_base_url}/#{g3}'"
          true -> "export * from '#{cdn_base_url}/#{g3}'"
        end
      end
    )
  end

  # NEW: Dual-mode transformation functions

  @doc """
  Transforms JavaScript imports/exports with rev-pinned URLs.

  This function always emits rev-pinned URLs in the canonical format:
  - CDN: `<cdn_origin>/__rev/<rev>/cdn/<path>`
  - SPA: `/__rev/<rev>/spa/<path>`

  ## Parameters

  - `file_content` - JavaScript file content
  - `conn` - Plug.Conn struct (used to get rev)
  - `cdn_origin` - Origin for CDN assets:
    - Unified proxy mode: "" (empty string, emits relative URLs)
    - Direct CDN mode: "http://localhost:60032" (full origin)

  ## Returns

  Transformed JavaScript content with all tokens replaced

  ## Examples

      # Unified proxy mode (cdn_origin = "")
      transform_javascript_with_conn(content, conn, "")
      # Emits: /__rev/abc123/cdn/foo.js

      # Direct CDN mode (cdn_origin = "http://localhost:60032")
      transform_javascript_with_conn(content, conn, "http://localhost:60032")
      # Emits: http://localhost:60032/__rev/abc123/cdn/foo.js
  """
  @spec transform_javascript_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  def transform_javascript_with_conn(file_content, conn, cdn_origin) do
    # Short-circuit if no tokens present (performance optimization)
    if String.contains?(file_content, "[OUTERFACES_") or
         String.contains?(file_content, "__OUTERFACES_REV__") do
      content = normalize_newlines(file_content)

      content
      |> replace_rev_token(conn)
      |> replace_odd_cdn_imports_with_conn(conn, cdn_origin)
      |> replace_odd_cdn_exports_with_conn(conn, cdn_origin)
      |> replace_odd_spa_imports_with_conn(conn)
      |> replace_odd_spa_exports_with_conn(conn)
      |> replace_default_imports_with_conn(conn, cdn_origin)
      |> replace_namespace_imports_with_conn(conn, cdn_origin)
      |> replace_side_effect_imports_with_conn(conn, cdn_origin)
    else
      file_content
    end
  end

  # Replace __OUTERFACES_REV__ with the actual rev value (useful for service workers)
  # Using double underscores to avoid conflicts with regex character classes like [^/]
  @spec replace_rev_token(String.t(), Plug.Conn.t()) :: String.t()
  defp replace_rev_token(content, conn) do
    rev = get_rev(conn)
    String.replace(content, "__OUTERFACES_REV__", rev)
  end

  @spec replace_odd_cdn_imports_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_odd_cdn_imports_with_conn(file_body, conn, cdn_origin) do
    rev = get_rev(conn)

    # Emit canonical rev-pinned URLs: <cdn_origin>/__rev/<rev>/cdn/<path>
    Regex.replace(@odd_cdn_imports_regex, file_body, fn _match, imports, path ->
      "import {#{imports}} from '#{cdn_origin}/__rev/#{rev}/cdn/#{path}'"
    end)
  end

  @spec replace_odd_cdn_exports_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_odd_cdn_exports_with_conn(file_body, conn, cdn_origin) do
    rev = get_rev(conn)

    # Emit canonical rev-pinned URLs: <cdn_origin>/__rev/<rev>/cdn/<path>
    Regex.replace(@odd_cdn_exports_regex, file_body, fn _match, g1, g2, g3 ->
      cond do
        g1 != "" -> "export {#{g1}} from '#{cdn_origin}/__rev/#{rev}/cdn/#{g3}'"
        g2 != "" -> "export * as #{g2} from '#{cdn_origin}/__rev/#{rev}/cdn/#{g3}'"
        true -> "export * from '#{cdn_origin}/__rev/#{rev}/cdn/#{g3}'"
      end
    end)
  end

  @spec replace_odd_spa_imports_with_conn(String.t(), Plug.Conn.t()) :: String.t()
  defp replace_odd_spa_imports_with_conn(file_body, conn) do
    rev = get_rev(conn)

    Regex.replace(@odd_spa_imports_regex, file_body, fn _match, imports, path ->
      "import {#{imports}} from '/__rev/#{rev}/spa/#{path}'"
    end)
  end

  @spec replace_odd_spa_exports_with_conn(String.t(), Plug.Conn.t()) :: String.t()
  defp replace_odd_spa_exports_with_conn(file_body, conn) do
    rev = get_rev(conn)

    Regex.replace(@odd_spa_exports_regex, file_body, fn _match, g1, g2, g3 ->
      cond do
        g1 != "" -> "export {#{g1}} from '/__rev/#{rev}/spa/#{g3}'"
        g2 != "" -> "export * as #{g2} from '/__rev/#{rev}/spa/#{g3}'"
        true -> "export * from '/__rev/#{rev}/spa/#{g3}'"
      end
    end)
  end

  # D2: Additional ESM syntax support helpers

  @spec replace_default_imports_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_default_imports_with_conn(file_body, conn, cdn_origin) do
    rev = get_rev(conn)

    file_body
    |> then(fn content ->
      Regex.replace(@odd_cdn_default_imports_regex, content, fn _match, import_name, path ->
        "import #{import_name} from '#{cdn_origin}/__rev/#{rev}/cdn/#{path}'"
      end)
    end)
    |> then(fn content ->
      Regex.replace(@odd_spa_default_imports_regex, content, fn _match, import_name, path ->
        "import #{import_name} from '/__rev/#{rev}/spa/#{path}'"
      end)
    end)
  end

  @spec replace_namespace_imports_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_namespace_imports_with_conn(file_body, conn, cdn_origin) do
    rev = get_rev(conn)

    file_body
    |> then(fn content ->
      Regex.replace(@odd_cdn_namespace_imports_regex, content, fn _match, namespace_name, path ->
        "import * as #{namespace_name} from '#{cdn_origin}/__rev/#{rev}/cdn/#{path}'"
      end)
    end)
    |> then(fn content ->
      Regex.replace(@odd_spa_namespace_imports_regex, content, fn _match, namespace_name, path ->
        "import * as #{namespace_name} from '/__rev/#{rev}/spa/#{path}'"
      end)
    end)
  end

  @spec replace_side_effect_imports_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_side_effect_imports_with_conn(file_body, conn, cdn_origin) do
    rev = get_rev(conn)

    file_body
    |> then(fn content ->
      Regex.replace(@odd_cdn_side_effect_imports_regex, content, fn _match, path ->
        "import '#{cdn_origin}/__rev/#{rev}/cdn/#{path}'"
      end)
    end)
    |> then(fn content ->
      Regex.replace(@odd_spa_side_effect_imports_regex, content, fn _match, path ->
        "import '/__rev/#{rev}/spa/#{path}'"
      end)
    end)
  end

  @spec get_rev(Plug.Conn.t()) :: String.t()
  defp get_rev(conn) do
    Map.get(conn.assigns, :outerfaces_rev) || Rev.current_rev()
  end
end
