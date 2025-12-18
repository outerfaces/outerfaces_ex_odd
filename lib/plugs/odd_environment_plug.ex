defmodule Outerfaces.Odd.Plugs.OddEnvironmentPlug do
  @moduledoc false
  import Plug.Conn
  alias Plug.Conn
  require Logger

  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts \\ []), do: opts

  @spec call(Conn.t(), Keyword.t()) :: Conn.t()
  def call(%Conn{request_path: "/environments/outerfaces_environment.js"} = conn, opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    # Fallback to Host header if no Origin (for same-origin requests)
    origin =
      if is_nil(origin) do
        host = get_req_header(conn, "host") |> List.first()
        if host, do: "https://#{host}", else: nil
      else
        origin
      end

    # Check for proxy headers
    proxy_prefix = get_req_header(conn, "x-proxy-prefix") |> List.first()

    conn
    |> put_resp_content_type("application/javascript")
    |> send_resp(200, build_pseudo_file(opts, origin, proxy_prefix))
    |> halt()
  end

  def call(conn, _opts), do: conn

  @spec build_pseudo_file(Keyword.t(), String.t() | nil, String.t() | nil) :: String.t()
  defp build_pseudo_file(opts, origin, proxy_prefix) when is_binary(proxy_prefix) do
    # Running behind proxy - return proxied URLs
    protocol = "https"  # Orchestrator is always HTTPS
    host_names = Keyword.get(opts, :host_names)
    extra_key_value_pairs = Keyword.get(opts, :extra_key_value_pairs, [])

    origin = (origin && strip_protocol_and_port(origin)) || nil
    origin_lower = origin && String.downcase(origin)

    # Case-insensitive matching
    host_name =
      if origin_lower do
        Enum.find(host_names, fn host ->
          String.downcase(host) == origin_lower
        end)
      else
        nil
      end

    # Log and default to first hostname if no match
    host_name =
      if host_name do
        Logger.debug("[OddEnvironmentPlug] Origin '#{origin}' matched hostname '#{host_name}'")
        host_name
      else
        default = Enum.at(host_names, 0)
        if origin do
          Logger.warning("[OddEnvironmentPlug] Origin '#{origin}' did not match any hostname in #{inspect(host_names)}, defaulting to '#{default}'")
        else
          Logger.debug("[OddEnvironmentPlug] No origin header, using default hostname '#{default}'")
        end
        default
      end

    # Build proxied URLs
    cdn_url = "#{protocol}://#{host_name}#{proxy_prefix}/cdn"
    api_url = "#{protocol}://#{host_name}#{proxy_prefix}/api"

    build_pseudo_file_with_urls(cdn_url, api_url, host_name, extra_key_value_pairs)
  end

  defp build_pseudo_file(opts, origin, nil) do
    # Direct access - use original logic with ports
    protocol = Keyword.get(opts, :protocol)
    host_names = Keyword.get(opts, :host_names)
    cdn_port = Keyword.get(opts, :cdn_port)
    api_port = Keyword.get(opts, :api_port)
    extra_key_value_pairs = Keyword.get(opts, :extra_key_value_pairs, [])

    origin = (origin && strip_protocol_and_port(origin)) || nil
    origin_lower = origin && String.downcase(origin)

    # Case-insensitive matching
    host_name =
      if origin_lower do
        Enum.find(host_names, fn host ->
          String.downcase(host) == origin_lower
        end)
      else
        nil
      end

    # Log and default to first hostname if no match
    host_name =
      if host_name do
        Logger.debug("[OddEnvironmentPlug] Origin '#{origin}' matched hostname '#{host_name}'")
        host_name
      else
        default = Enum.at(host_names, 0)
        if origin do
          Logger.warning("[OddEnvironmentPlug] Origin '#{origin}' did not match any hostname in #{inspect(host_names)}, defaulting to '#{default}'")
        else
          Logger.debug("[OddEnvironmentPlug] No origin header, using default hostname '#{default}'")
        end
        default
      end

    build_pseudo_file(protocol, host_name, cdn_port, api_port, extra_key_value_pairs)
  end

  @spec build_pseudo_file_with_urls(String.t(), String.t(), String.t(), [{String.t() | atom(), any()}]) :: String.t()
  defp build_pseudo_file_with_urls(cdn_url, api_url, host_name, extra_key_value_pairs) do
    extra_keypairs_formatted =
      extra_key_value_pairs
      |> Enum.map(fn
        # Support dynamic values via MFA tuples {Module, :function, args}
        {key, {module, function, args}} when is_atom(module) and is_atom(function) and is_list(args) ->
          resolved_value = apply(module, function, args)
          "#{do_normalize_key(key)}: #{do_normalize_value(resolved_value)}"

        {key, value} when is_list(value) ->
          formatted_values =
            value
            |> Enum.map(&do_normalize_value/1)
            |> Enum.join(", ")

          "#{do_normalize_key(key)}: [#{formatted_values}]"

        {key, value} ->
          "#{do_normalize_key(key)}: #{do_normalize_value(value)}"
      end)
      |> Enum.join(",\n  ")
      |> String.trim()

    extra_section = if extra_keypairs_formatted != "", do: ",\n  #{extra_keypairs_formatted}", else: ""

    """
    export default {
      outerfaces_cdn_url: '#{cdn_url}',
      outerfaces_api_url: '#{api_url}',
      api_host: '#{host_name}'#{extra_section}
    }
    """
  end

  @spec build_pseudo_file(String.t(), String.t(), integer(), integer(), [{String.t(), any()}]) ::
          String.t()
  defp build_pseudo_file(protocol, host_name, cdn_port, api_port, []) do
    """
    export default {
      outerfaces_cdn_url: '#{build_origin_path(protocol, host_name, cdn_port)}',
      outerfaces_api_url: '#{build_origin_path(protocol, host_name, api_port)}'
    }
    """
  end

  defp build_pseudo_file(protocol, host_name, cdn_port, api_port, extra_keypairs)
       when is_binary(protocol) and is_binary(host_name) and
              is_integer(cdn_port) and is_integer(api_port) and
              is_list(extra_keypairs) do
    extra_keypairs_formatted =
      extra_keypairs
      |> Enum.map(fn
        # Support dynamic values via MFA tuples {Module, :function, args}
        {key, {module, function, args}} when is_atom(module) and is_atom(function) and is_list(args) ->
          resolved_value = apply(module, function, args)
          "#{do_normalize_key(key)}: #{do_normalize_value(resolved_value)}"

        {key, value} when is_list(value) ->
          formatted_values =
            value
            |> Enum.map(&do_normalize_value/1)
            |> Enum.join(", ")

          "#{do_normalize_key(key)}: [#{formatted_values}]"

        {key, value} ->
          "#{do_normalize_key(key)}: #{do_normalize_value(value)}"
      end)
      |> Enum.join(",\n  ")
      |> String.trim()

    """
    export default {
      outerfaces_cdn_url: '#{build_origin_path(protocol, host_name, cdn_port)}',
      outerfaces_api_url: '#{build_origin_path(protocol, host_name, api_port)}',
      api_host: '#{host_name}:#{api_port}',
      #{extra_keypairs_formatted}
    }
    """
  end

  @spec do_normalize_key(String.t() | atom()) :: String.t() | nil
  defp do_normalize_key(key) do
    case key do
      k when is_binary(k) ->
        "#{k}" |> String.replace(" ", "_")

      k when is_atom(k) ->
        k |> Atom.to_string() |> String.replace(" ", "_")

      _ ->
        nil
    end
  end

  @spec do_normalize_value(any()) :: String.t() | nil
  defp do_normalize_value(value) do
    case value do
      v when is_binary(v) -> "'#{v}'"
      v when is_integer(v) -> "#{v}"
      v when is_boolean(v) -> "#{v}"
      v when is_float(v) -> "#{v}"
      _ -> nil
    end
  end

  @spec build_origin_path(String.t(), String.t(), integer()) :: String.t()
  defp build_origin_path(protocol, host, port) do
    "#{protocol}://#{host}:#{port}"
  end

  @spec strip_protocol_and_port(String.t()) :: String.t()
  defp strip_protocol_and_port(origin) do
    origin
    |> String.split("://")
    |> List.last()
    |> String.split(":")
    |> List.first()
  end
end
