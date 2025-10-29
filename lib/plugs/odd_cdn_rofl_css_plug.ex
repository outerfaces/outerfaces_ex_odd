defmodule Outerfaces.Odd.Plugs.OddCDNRoflCSSPlug do
  # Regex to match CSS @import statements with the OUTERFACES_LOCAL_CDN marker
  @local_cdn_imports_regex ~r/@import\s+['"]([^'"]*)\[OUTERFACES_LOCAL_CDN\]\/([^'"]*)['"]\s*;?/i

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
    content = normalize_newlines(file_content)

    replace_cdn_imports(
      content,
      url_scheme,
      cdn_service_host_name,
      cdn_service_host_port
    )
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
    replacement = "@import '#{cdn_protocol}://#{cdn_host}:#{cdn_port}/\\2'"

    Regex.replace(
      @local_cdn_imports_regex,
      file_body,
      replacement
    )
  end
end
