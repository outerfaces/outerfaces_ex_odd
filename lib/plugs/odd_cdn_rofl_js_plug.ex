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
  @odd_cdn_imports_regex ~r/import\s+\{\s*([\s\S]*?)\s*\}\s+from\s+['"][^'"]*\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^'"]*)['"]\s*;?/is
  @odd_cdn_exports_regex ~r/export\s+(?:\{\s*([\s\S]*?)\s*\}|\*(?:\s+as\s+(\w+))?)\s+from\s+['"][^'"]*\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^'"]*)['"]\s*;?/is
  @odd_spa_imports_regex ~r/import\s+\{\s*([\s\S]*?)\s*\}\s+from\s+['"][^'"]*\[OUTERFACES_ODD_SPA\]\/([^'"]*)['"]\s*;?/is
  @odd_spa_exports_regex ~r/export\s+(?:\{\s*([\s\S]*?)\s*\}|\*(?:\s+as\s+(\w+))?)\s+from\s+['"][^'"]*\[OUTERFACES_ODD_SPA\]\/([^'"]*)['"]\s*;?/is

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
  Transforms JavaScript imports/exports with dual-mode support (rev-pinned or absolute URLs).

  This function checks conn.assigns.outerfaces_rev to determine the mode:
  - If rev present: rewrites to rev-pinned URLs (/__rev/<rev>/cdn/...)
  - Otherwise: rewrites to absolute URLs using provided cdn_base_url

  ## Parameters

  - `file_content` - JavaScript file content
  - `conn` - Plug.Conn struct (used to check for rev)
  - `cdn_base_url` - Base URL for absolute mode (e.g., "http://localhost:60032")

  ## Returns

  Transformed JavaScript content with all tokens replaced
  """
  @spec transform_javascript_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  def transform_javascript_with_conn(file_content, conn, cdn_base_url) do
    content = normalize_newlines(file_content)

    content
    |> replace_rev_token(conn)
    |> replace_odd_cdn_imports_with_conn(conn, cdn_base_url)
    |> replace_odd_cdn_exports_with_conn(conn, cdn_base_url)
    |> replace_odd_spa_imports_with_conn(conn)
    |> replace_odd_spa_exports_with_conn(conn)
  end

  # Replace __OUTERFACES_REV__ with the actual rev value (useful for service workers)
  # Using double underscores to avoid conflicts with regex character classes like [^/]
  @spec replace_rev_token(String.t(), Plug.Conn.t()) :: String.t()
  defp replace_rev_token(content, conn) do
    rev = get_rev(conn)
    String.replace(content, "__OUTERFACES_REV__", rev)
  end

  @spec replace_odd_cdn_imports_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_odd_cdn_imports_with_conn(file_body, conn, cdn_base_url) do
    rev = get_rev(conn)

    # CDN imports always go to cdn_base_url with rev prefix
    Regex.replace(@odd_cdn_imports_regex, file_body, fn _match, imports, path ->
      "import {#{imports}} from '#{cdn_base_url}/__rev/#{rev}/cdn/#{path}'"
    end)
  end

  @spec replace_odd_cdn_exports_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_odd_cdn_exports_with_conn(file_body, conn, cdn_base_url) do
    rev = get_rev(conn)

    # CDN exports always go to cdn_base_url with rev prefix
    Regex.replace(@odd_cdn_exports_regex, file_body, fn _match, g1, g2, g3 ->
      cond do
        g1 != "" -> "export {#{g1}} from '#{cdn_base_url}/__rev/#{rev}/cdn/#{g3}'"
        g2 != "" -> "export * as #{g2} from '#{cdn_base_url}/__rev/#{rev}/cdn/#{g3}'"
        true -> "export * from '#{cdn_base_url}/__rev/#{rev}/cdn/#{g3}'"
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

  @spec get_rev(Plug.Conn.t()) :: String.t()
  defp get_rev(conn) do
    Map.get(conn.assigns, :outerfaces_rev) || Rev.current_rev()
  end
end
