defmodule Outerfaces.Odd.Endpoints.DynamicLoader do
  @moduledoc """
  Custom endpoint loader for Outerfaces projects.
  """
  @ports_per_project 1

  @behaviour Outerfaces.Endpoints.DynamicLoader.DynamicLoaderBehavior

  alias Outerfaces.Odd.Endpoints.ConfigurationBuilder
  alias Outerfaces.Odd.Plugs.OddCDNConsumerContentSecurityPlug
  alias Outerfaces.Odd.Plugs.OddCDNConsumerServeIndex
  alias Outerfaces.Odd.Plugs.OddCDNProviderContentSecurityPlug
  alias Outerfaces.Odd.Plugs.OddEnvironmentPlug
  alias Outerfaces.Odd.Plugs.OddRevProxyPlug
  alias Outerfaces.Odd.Plugs.OddRevCacheHeadersPlug
  alias Outerfaces.Odd.Plugs.OddRevEndpointPlug
  alias Outerfaces.Plugs.ServeIndex.DefaultServeIndex

  require Logger

  @impl true
  def endpoint_config_for_project(project_name, port, app_web_module) do
    Logger.debug("#{__MODULE__} Creating endpoint config for #{project_name}")
    # node_scope = Application.get_env(:my_app, :my_config][:localhost_or_public]
    node_scope = "localhost"
    ip = ConfigurationBuilder.build_ip_for_node_scope(node_scope)
    host = ConfigurationBuilder.build_host_for_node_scope(node_scope)
    secret_key_base = System.get_env("SECRET_KEY_BASE")
    # url_scheme = Application.get_env(:my_app, :my_config)[:http_or_https]
    url_scheme = "http"

    if url_scheme == "https" do
      ConfigurationBuilder.dynamic_loader_https_endpoint_url_configuration!(
        app_web_module,
        host,
        port,
        ip,
        secret_key_base,
        System.get_env("NODE_TLS_KEY_PATH"),
        System.get_env("NODE_TLS_CERT_PATH")
      )
    else
      ConfigurationBuilder.dynamic_loader_http_endpoint_url_configuration!(
        app_web_module,
        host,
        port,
        ip,
        secret_key_base
      )
    end
  end

  @impl true
  def prepare_endpoint_module(
        "odd_cdn" = outerfaces_project_name,
        app_slug,
        endpoint_module,
        opts
      ) do
    unless Code.ensure_loaded?(endpoint_module) do
      # TODO: Move this path building out
      project_path =
        [
          :code.priv_dir(app_slug),
          "static",
          "outerfaces",
          "projects",
          outerfaces_project_name
        ]
        |> Path.join()

      module_body =
        quote do
          # node_host_name = Application.compile_env(:my_app, :my_config)[:host_name]
          node_host_name = "localhost"
          # url_scheme = Application.compile_env(:my_app, :my_config)[:http_or_https]
          url_scheme = "http"

          # maybe_node_host_name_secondary =
          #   Application.compile_env(:my_app, :my_config)[:host_name_secondary]
          maybe_node_host_name_secondary = nil

          origin_applications = [
            %{
              protocol: url_scheme,
              host: node_host_name,
              port: Keyword.get(unquote(opts), :ui_port)
            }
          ]

          origin_applications =
            (maybe_node_host_name_secondary &&
               Enum.concat(origin_applications, [
                 %{
                   protocol: url_scheme,
                   host: maybe_node_host_name_secondary,
                   port: Keyword.get(unquote(opts), :ui_port)
                 }
               ])) || origin_applications

          use Phoenix.Endpoint, otp_app: unquote(app_slug)

          plug(Plug.Logger, log: :debug)

          plug(OddCDNProviderContentSecurityPlug,
            origin_applications: origin_applications,
            source_host_options: origin_applications
          )

          plug(DefaultServeIndex,
            index_path: "#{unquote(project_path)}/index.html",
            static_root: unquote(project_path)
          )
        end

      Module.create(endpoint_module, module_body, Macro.Env.location(__ENV__))
    end
  end

  def prepare_endpoint_module(outerfaces_project_name, app_slug, endpoint_module, opts) do
    unless Code.ensure_loaded?(endpoint_module) do
      # TODO: Move this path building out
      project_path =
        [
          :code.priv_dir(app_slug),
          "static",
          "outerfaces",
          "projects",
          outerfaces_project_name
        ]
        |> Path.join()

      module_body =
        quote do
          # node_host_name = Application.compile_env(:my_app, :my_config)[:host_name]
          node_host_name = "localhost"
          # node_scope = Application.compile_env(:my_app, :my_config)[:localhost_or_public]
          node_scope = "localhost"
          # url_scheme = Application.compile_env(:my_app, :my_config)[:http_or_https]
          url_scheme = "http"

          # maybe_host_name_secondary =
          #   Application.compile_env(:my_app, :my_config)[:secondary_host_name]
          maybe_node_host_name_secondary = nil

          api_port = Keyword.get(unquote(opts), :api_port)
          cdn_port = Keyword.get(unquote(opts), :cdn_port)
          ui_port = Keyword.get(unquote(opts), :ui_port)

          host_names =
            [
              "localhost",
              node_host_name,
              maybe_node_host_name_secondary
            ]
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          allowed_sources =
            host_names
            |> Enum.flat_map(fn host ->
              [
                %{
                  protocol: url_scheme,
                  host: host,
                  port: cdn_port
                },
                %{
                  protocol: url_scheme,
                  host: host,
                  port: api_port
                }
              ]
            end)

          use Phoenix.Endpoint, otp_app: unquote(app_slug)

          plug(Plug.Logger, log: :debug)

          # NEW: Rev plugs (MUST be first for rev URL parsing)
          plug(OddRevProxyPlug, mismatch_behavior: :redirect)
          plug(OddRevCacheHeadersPlug)

          # Rev endpoint for service worker rev checks
          plug(OddRevEndpointPlug)

          plug(OddCDNConsumerContentSecurityPlug,
            source_host_options: allowed_sources
          )

          plug(OddEnvironmentPlug,
            protocol: url_scheme,
            host_names: host_names,
            cdn_port: cdn_port,
            ui_port: ui_port,
            api_port: api_port
          )

          plug(OddCDNConsumerServeIndex,
            index_path: "#{unquote(project_path)}/index.html",
            static_root: unquote(project_path)
          )
        end

      Module.create(endpoint_module, module_body, Macro.Env.location(__ENV__))
    end
  end

  @impl true
  def prepare_endpoint_modules(project_directories, app_slug, app_web_module, opts) do
    Logger.debug("#{__MODULE__}: Generating endpoint modules")

    Enum.each(project_directories, fn project ->
      prepare_endpoint_module(
        project,
        app_slug,
        endpoint_module_name(app_web_module, project),
        opts
      )
    end)
  end

  @impl true
  def hydrate_endpoint_modules(
        project_directories,
        app_module,
        app_web_module,
        base_port
      ) do
    Logger.debug("#{__MODULE__}: Initializing generated endpoint modules")

    project_directories
    |> Enum.with_index()
    |> Enum.map(&create_dynamic_endpoint_spec(&1, app_module, app_web_module, base_port))
  end

  @impl true
  @spec create_dynamic_endpoint_spec(
          {String.t(), non_neg_integer()},
          atom(),
          atom(),
          pos_integer()
        ) :: {atom(), Keyword.t()}
  def create_dynamic_endpoint_spec(
        {project_name, index},
        app_module,
        app_web_module,
        base_port
      ) do
    Logger.debug("#{__MODULE__}: Creating dynamic endpoint spec")
    port = dynamic_port(base_port, index)
    endpoint_module = endpoint_module_name(app_web_module, project_name)
    config = endpoint_config_for_project(project_name, port, app_web_module)
    Application.put_env(app_module, endpoint_module, config)
    {endpoint_module, config}
  end

  @impl true
  def dynamic_port(base_port, 0) when is_integer(base_port) do
    base_port
  end

  def dynamic_port(base_port, index) when is_integer(base_port) and is_integer(index) do
    base_port + index * @ports_per_project
  end

  defp endpoint_module_name(app_web_module, project_name) do
    camel_case_name = snake_to_camel(project_name)
    Module.concat([app_web_module, "#{camel_case_name}Endpoint"])
  end

  defp snake_to_camel(snake_case) do
    snake_case
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end
end
