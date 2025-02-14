defmodule Outerfaces.Bespoke.Plugs.BespokeEnvironmentPlug do
  @moduledoc false
  import Plug.Conn
  alias Plug.Conn

  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts \\ []), do: opts

  @spec call(Conn.t(), Keyword.t()) :: Conn.t()
  def call(%Conn{request_path: "/environments/outerfaces_environment.js"} = conn, opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    conn
    |> put_resp_content_type("application/javascript")
    |> send_resp(200, build_pseudo_file(opts, origin))
    |> halt()
  end

  def call(conn, _opts), do: conn

  @spec build_pseudo_file(Keyword.t(), String.t()) :: String.t()
  defp build_pseudo_file(opts, origin) do
    protocol = Keyword.get(opts, :protocol)
    host_names = Keyword.get(opts, :host_names)
    cdn_port = Keyword.get(opts, :cdn_port)
    api_port = Keyword.get(opts, :api_port)

    origin = (origin && strip_protocol_and_port(origin)) || nil

    host_name = Enum.find(host_names, fn host -> host == origin end) || Enum.at(host_names, 0)

    build_pseudo_file(protocol, host_name, cdn_port, api_port)
  end

  @spec build_pseudo_file(String.t(), String.t(), integer(), integer()) :: String.t()
  defp build_pseudo_file(protocol, host_name, cdn_port, api_port)
       when is_binary(protocol) and is_binary(host_name) and
              is_integer(cdn_port) and is_integer(api_port) do
    """
    export default {
      outerfaces_cdn_url: '#{build_origin_path(protocol, host_name, cdn_port)}',
      outerfaces_api_url: '#{build_origin_path(protocol, host_name, api_port)}'
    }
    """
  end

  @spec build_origin_path(String.t(), String.t(), integer()) :: String.t()
  defp build_origin_path(protocol, host, port) do
    "#{protocol}://#{host}:#{port}"
  end

  defp strip_protocol_and_port(origin) do
    origin
    |> String.split("://")
    |> List.last()
    |> String.split(":")
    |> List.first()
  end
end
