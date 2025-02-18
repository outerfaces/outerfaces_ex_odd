defmodule Outerfaces.Odd.Endpoints.ConfigurationBuilder do
  @moduledoc false

  @spec dynamic_loader_https_endpoint_url_configuration!(
          app_web_module :: atom(),
          host :: String.t(),
          port :: integer(),
          node_ip :: String.t() | {integer(), integer(), integer(), integer()},
          secret_key_base :: String.t(),
          keyfile_path :: String.t(),
          certfile_path :: String.t()
        ) :: Keyword.t()
  def dynamic_loader_https_endpoint_url_configuration!(
        app_web_module,
        host,
        port,
        ip_address,
        secret_key_base,
        keyfile_path,
        certfile_path
      )
      when is_atom(app_web_module) and
             is_binary(host) and
             is_integer(port) and
             is_binary(secret_key_base) and
             is_binary(keyfile_path) and
             is_binary(certfile_path) and
             (is_binary(ip_address) or is_tuple(ip_address)) do
    [
      url: [
        host: host,
        port: port,
        scheme: "https"
      ],
      https: [
        ip: ip_address,
        port: port,
        cipher_suite: :strong,
        keyfile: keyfile_path,
        certfile: certfile_path
      ],
      server: true,
      secret_key_base: secret_key_base,
      force_ssl: [hsts: true],
      adapter: Bandit.PhoenixAdapter,
      transport_options: [
        alpn_preferred_protocols: ["h2", "http/1.1"]
      ],
      render_errors: [
        formats: [json: Module.concat([app_web_module, ErrorJSON])],
        layout: false
      ]
    ]
  end

  def dynamic_loader_https_endpoint_url_configuration!(
        app_web_module,
        host,
        port,
        ip_address,
        secret_key_base,
        keyfile_path,
        certfile_path
      ) do
    raise ArgumentError, """
    Invalid arguments for #{__MODULE__}.dynamic_loader_https_endpoint_url_configuration!/6:
    #{inspect(app_web_module: app_web_module,
    host: host,
    port: port,
    ip_address: ip_address,
    secret_key_base: secret_key_base,
    keyfile_path: keyfile_path,
    certfile_path: certfile_path)}
    """
  end

  @spec dynamic_loader_http_endpoint_url_configuration!(
          app_web_module :: atom(),
          host :: String.t(),
          port :: integer(),
          ip_address ::
            String.t() | {integer(), integer(), integer(), integer()},
          secret_key_base :: String.t()
        ) :: Keyword.t()
  def dynamic_loader_http_endpoint_url_configuration!(
        app_web_module,
        host,
        port,
        ip_address,
        secret_key_base
      )
      when is_atom(app_web_module) and
             is_binary(host) and
             is_integer(port) and
             is_binary(secret_key_base) and
             (is_binary(ip_address) or is_tuple(ip_address)) do
    [
      http: [ip: ip_address, port: port],
      url: [host: host, port: port, scheme: "http"],
      server: true,
      secret_key_base: secret_key_base,
      adapter: Bandit.PhoenixAdapter,
      render_errors: [
        formats: [json: Module.concat([app_web_module, ErrorJSON])],
        layout: false
      ]
    ]
  end

  def dynamic_loader_http_endpoint_url_configuration!(
        app_web_module,
        host,
        port,
        ip_address,
        secret_key_base
      ) do
    raise ArgumentError, """
    Invalid arguments for #{__MODULE__}.dynamic_loader_http_endpoint_url_configuration!/5:
    #{inspect(app_web_module: app_web_module,
    host: host,
    port: port,
    ip_address: ip_address,
    secret_key_base: secret_key_base)}
    """
  end

  @spec build_ip_for_node_scope(String.t()) :: {integer, integer, integer, integer}
  def build_ip_for_node_scope("public") do
    {0, 0, 0, 0}
  end

  def build_ip_for_node_scope(_) do
    {127, 0, 0, 1}
  end

  @spec build_ipv6_for_node_scope(String.t()) ::
          {integer, integer, integer, integer, integer, integer, integer, integer}
  def build_ipv6_for_node_scope("public") do
    {0, 0, 0, 0, 0, 0, 0, 0}
  end

  def build_ipv6_for_node_scope(_) do
    {0, 0, 0, 0, 0, 0, 0, 1}
  end

  @spec build_host_for_node_scope(String.t()) :: String.t()
  def build_host_for_node_scope("public") do
    "0.0.0.0"
  end

  def build_host_for_node_scope(_) do
    "127.0.0.1"
  end
end
