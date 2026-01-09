defmodule Outerfaces.Odd.Plugs.OddCDNRoflCSSPlug do
  @moduledoc """
  Transforms CSS @import statements by rewriting CDN tokens.

  Supports both legacy and new token patterns:
  - [OUTERFACES_LOCAL_CDN] - DEPRECATED, aliased to [OUTERFACES_ODD_CDN]
  - [OUTERFACES_ODD_CDN] - Dual-mode: rev-pinned or absolute URLs

  Dual-mode behavior:
  - When conn.assigns.outerfaces_rev is present: rev-pinned URLs (/__rev/<rev>/cdn/...)
  - Otherwise: absolute URLs (http://localhost:60032/...)
  """

  # Regex to match CSS @import statements with the OUTERFACES_LOCAL_CDN marker
  @local_cdn_imports_regex ~r/@import\s+['"]([^'"]*)\[OUTERFACES_LOCAL_CDN\]\/([^'"]*)['"]\s*;?/i
  # New regex (supports both ODD and LOCAL for backward compatibility)
  @odd_cdn_imports_regex ~r/@import\s+['"]([^'"]*)\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^'"]*)['"]\s*;?/i

  @spec transform_css_cdn_imports(
          file_content :: String.t(),
          cdn_service_host_name :: String.t(),
          cdn_service_host_port :: integer(),
          url_scheme :: String.t()
        ) :: String.t()
  def transform_css_cdn_imports(
        file_content,
        cdn_service_host_name,
        cdn_service_host_port,
        url_scheme
      ) do
    cdn_base_url = "#{url_scheme}://#{cdn_service_host_name}:#{cdn_service_host_port}"
    transform_css_cdn_imports_with_base_url(file_content, cdn_base_url)
  end

  @spec transform_css_cdn_imports_with_base_url(
          file_content :: String.t(),
          cdn_base_url :: String.t()
        ) :: String.t()
  def transform_css_cdn_imports_with_base_url(file_content, cdn_base_url) do
    content = normalize_newlines(file_content)
    replace_cdn_imports_with_base_url(content, cdn_base_url)
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
    cdn_base_url = "#{cdn_protocol}://#{cdn_host}:#{cdn_port}"
    replace_cdn_imports_with_base_url(file_body, cdn_base_url)
  end

  # New function that works with base URL (supports both absolute and proxy-relative URLs)
  @spec replace_cdn_imports_with_base_url(file_body :: String.t(), cdn_base_url :: String.t()) ::
          String.t()
  def replace_cdn_imports_with_base_url(file_body, cdn_base_url)
      when is_binary(file_body) and is_binary(cdn_base_url) do
    Regex.replace(
      @local_cdn_imports_regex,
      file_body,
      "@import '#{cdn_base_url}/\\2'"
    )
  end

  # NEW: Dual-mode transformation function

  @doc """
  Transforms CSS @import statements with dual-mode support (rev-pinned or absolute URLs).

  This function checks conn.assigns.outerfaces_rev to determine the mode:
  - If rev present: rewrites to rev-pinned URLs (/__rev/<rev>/cdn/...)
  - Otherwise: rewrites to absolute URLs using provided cdn_base_url

  ## Parameters

  - `file_content` - CSS file content
  - `conn` - Plug.Conn struct (used to check for rev)
  - `cdn_base_url` - Base URL for absolute mode (e.g., "http://localhost:60032")

  ## Returns

  Transformed CSS content with all tokens replaced
  """
  @spec transform_css_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  def transform_css_with_conn(file_content, conn, cdn_base_url) do
    content = normalize_newlines(file_content)
    replace_odd_cdn_imports_with_conn(content, conn, cdn_base_url)
  end

  @spec replace_odd_cdn_imports_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_odd_cdn_imports_with_conn(file_body, conn, cdn_base_url) do
    rev = get_rev(conn)

    # CDN imports always go to cdn_base_url with rev prefix
    Regex.replace(@odd_cdn_imports_regex, file_body, fn _match, prefix, path ->
      "@import '#{prefix}#{cdn_base_url}/__rev/#{rev}/cdn/#{path}'"
    end)
  end

  @spec get_rev(Plug.Conn.t()) :: String.t()
  defp get_rev(conn) do
    Map.get(conn.assigns, :outerfaces_rev) || Outerfaces.Rev.current_rev()
  end
end
