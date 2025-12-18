defmodule Outerfaces.Odd.Plugs.OddCDNRoflJSPlug do
  # These magical regexes are used to match and replace import / export statements in JavaScript files
  @local_cdn_imports_regex ~r/import\s+\{\s*([\s\S]*?)\s*\}\s+from\s+['"][^'"]*\[OUTERFACES_LOCAL_CDN\]\/([^'"]*)['"]\s*;?/is
  @local_cdn_exports_regex ~r/export\s+(?:\{\s*([\s\S]*?)\s*\}|\*(?:\s+as\s+(\w+))?)\s+from\s+['"][^'"]*\[OUTERFACES_LOCAL_CDN\]\/([^'"]*)['"]\s*;?/is

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
end
