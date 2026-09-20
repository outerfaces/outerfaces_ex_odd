defmodule Mix.Tasks.Outerfaces.IntoOddCdn do
  @moduledoc """
  Vendor a JS library into the app's `outerfaces/projects/odd_cdn` directory.

  ## What gets copied

  1. **Task arguments** — `include="lib,README.md"`, `exclude="tests,tools"`.
  2. **Application config** —

         config :outerfaces_odd, :odd_cdn,
           exclude: ["tests", "tools"]

     or per library:

         config :outerfaces_odd, :odd_cdn,
           my_lib: [exclude: ["tests", "tools"]]

  3. **The library's own `outerfaces.registry.json`** — the best place for it,
     since what a library publishes is the library's business and not every
     consumer's:

         {
           "name": "my_lib",
           "version": "0.1.0",
           "odd_cdn": { "exclude": ["tests", "tools"] }
         }

  4. **Defaults** — `#{inspect(~w(.git .DS_Store node_modules _build deps cover .elixir_ls))}`,
     which are always excluded on top of whatever else is configured, because
     nothing wants them on a CDN.

  `include` and `exclude` are lists of `Path.wildcard/2` patterns relative to
  the library root, so `"tests"` prunes a directory, `"**/*.map"` prunes by
  extension anywhere, and `"lib"` (as an include) publishes that tree and
  nothing else. An empty `include` means "everything not excluded", which is
  the previous behaviour and stays the default.

  ## Examples

      mix outerfaces.into_odd_cdn
      mix outerfaces.into_odd_cdn lib="my_lib" exclude="tests,tools"

  Currently depends on local source files.

  TODO: Copy from a public git repo or tarball.
  TODO: Create a hash digest of the files copied and store it in a file in the
  target directory.
  """
  use Mix.Task

  @default_lib_slug "outerfaces_js_core"
  @target_app_dir_base "outerfaces/projects/odd_cdn"
  @registry_file_name "outerfaces.registry.json"
  @registry_rules_key "odd_cdn"

  # Always pruned, whatever else is configured.
  @always_exclude ~w(.git .DS_Store node_modules _build deps cover .elixir_ls)

  def run(args \\ []) do
    opts = parse_args(args)
    File.mkdir_p!(@target_app_dir_base)
    lib_slug = Keyword.get(opts, :lib, @default_lib_slug)
    source_base_path = Keyword.get(opts, :source_base_path)
    target_base_path = Keyword.get(opts, :target_base_path)
    source_dir = get_source_dir_for_lib(source_base_path, lib_slug)

    registry = read_registry(source_base_path, lib_slug)
    version = Map.fetch!(registry, "version")
    rules = resolve_rules(opts, registry, lib_slug)
    IO.puts("Found version #{version} in #{source_dir}..")

    target_dir_with_version =
      "#{target_base_path}/#{@target_app_dir_base}/#{lib_slug}/#{version}/"

    File.mkdir_p!(target_dir_with_version)
    IO.puts("Copying library files from #{source_dir} to #{target_dir_with_version}..")
    announce(rules)

    copied = copy_tree(source_dir, target_dir_with_version, rules)

    IO.puts("#{copied} library files copied to #{target_dir_with_version}")
    # A guard, not the mechanism: `.git` is in @always_exclude and should never
    # have been copied in the first place.
    remove_git_directories(target_dir_with_version)
    {:ok, version}
  end

  # ---------------------------------------------------------------------------
  # Rules
  # ---------------------------------------------------------------------------

  @doc false
  def resolve_rules(opts, registry, lib_slug) do
    from_registry = Map.get(registry, @registry_rules_key, %{})
    from_config = config_rules(lib_slug)

    %{
      include:
        first_present([
          list_arg(opts[:include]),
          from_config[:include],
          patterns(from_registry["include"])
        ]) || [],
      exclude:
        @always_exclude ++
          (first_present([
             list_arg(opts[:exclude]),
             from_config[:exclude],
             patterns(from_registry["exclude"])
           ]) || [])
    }
  end

  defp config_rules(lib_slug) do
    config = Application.get_env(:outerfaces_odd, :odd_cdn, [])

    case Keyword.fetch(config, String.to_atom(lib_slug)) do
      {:ok, per_lib} -> per_lib
      :error -> Keyword.take(config, [:include, :exclude])
    end
  end

  defp first_present(candidates), do: Enum.find(candidates, &(is_list(&1) and &1 != []))

  defp list_arg(nil), do: nil

  defp list_arg(value) when is_binary(value) do
    value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp patterns(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp patterns(_), do: nil

  defp announce(%{include: [], exclude: exclude}) do
    IO.puts("  excluding: #{Enum.join(exclude, ", ")}")
  end

  defp announce(%{include: include, exclude: exclude}) do
    IO.puts("  including: #{Enum.join(include, ", ")}")
    IO.puts("  excluding: #{Enum.join(exclude, ", ")}")
  end

  # ---------------------------------------------------------------------------
  # Copying
  # ---------------------------------------------------------------------------

  @doc false
  def copy_tree(source_dir, target_dir, rules) do
    source = Path.expand(source_dir)
    target = Path.expand(target_dir)

    ctx = %{
      excluded: expand_patterns(source, rules.exclude),
      included: if(rules.include == [], do: nil, else: expand_patterns(source, rules.include))
    }

    File.rm_rf!(target)
    File.mkdir_p!(target)
    copy_dir(source, target, ctx)
  end

  # Patterns resolve against the source tree, so a pattern that matches nothing
  # simply contributes nothing rather than failing the build.
  defp expand_patterns(source, patterns) do
    patterns
    |> Enum.flat_map(&Path.wildcard(Path.join(source, &1), match_dot: true))
    |> MapSet.new()
  end

  defp copy_dir(src, dst, ctx) do
    src
    |> File.ls!()
    |> Enum.reduce(0, fn entry, copied ->
      src_path = Path.join(src, entry)
      dst_path = Path.join(dst, entry)

      cond do
        excluded?(src_path, ctx) ->
          copied

        File.dir?(src_path) ->
          if descend?(src_path, ctx), do: copied + copy_dir(src_path, dst_path, ctx), else: copied

        included?(src_path, ctx) ->
          File.mkdir_p!(Path.dirname(dst_path))
          File.cp!(src_path, dst_path)
          copied + 1

        true ->
          copied
      end
    end)
  end

  defp excluded?(path, %{excluded: excluded}), do: MapSet.member?(excluded, path)

  defp included?(_path, %{included: nil}), do: true

  defp included?(path, %{included: included}),
    do: Enum.any?(included, &(&1 == path or String.starts_with?(path, &1 <> "/")))

  defp descend?(_dir, %{included: nil}), do: true

  # Worth walking into if it is itself included, or if anything included lives
  # under it.
  defp descend?(dir, %{included: included}) do
    Enum.any?(included, fn entry ->
      entry == dir or String.starts_with?(dir, entry <> "/") or
        String.starts_with?(entry, dir <> "/")
    end)
  end

  defp remove_git_directories(dir) do
    File.ls!(dir)
    |> Enum.each(fn
      ".git" ->
        File.rm_rf!(Path.join(dir, ".git"))

      file_or_dir ->
        path = Path.join(dir, file_or_dir)
        if File.dir?(path), do: remove_git_directories(path)
    end)
  end

  # ---------------------------------------------------------------------------
  # Inputs
  # ---------------------------------------------------------------------------

  defp parse_args(args) do
    Enum.reduce(args, [], fn arg, acc ->
      case String.split(arg, "=", parts: 2) do
        [key, value] -> [{String.to_atom(key), value} | acc]
        _ -> acc
      end
    end)
  end

  defp get_source_dir_for_lib(source_base_path, lib_slug)
       when is_binary(source_base_path) and is_binary(lib_slug),
       do: "#{source_base_path}/#{lib_slug}"

  defp read_registry(source_base_path, lib_slug)
       when is_binary(source_base_path) and is_binary(lib_slug) do
    source_dir = get_source_dir_for_lib(source_base_path, lib_slug)
    registry_info_path = Path.expand(Path.join(source_dir, @registry_file_name))
    IO.puts("Reading #{@registry_file_name} from #{registry_info_path}")
    {:ok, registry_json} = File.read(registry_info_path)
    {:ok, %{"version" => _} = registry} = Jason.decode(registry_json)
    registry
  end
end
