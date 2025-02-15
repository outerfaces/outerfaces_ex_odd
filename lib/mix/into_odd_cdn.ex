defmodule Mix.Tasks.Outerfaces.IntoOddCdn do
  @moduledoc """
  Copies the specified files to the app's outerfaces/projects/odd_cdn directory.
  Defaults to the main Outerfaces JS files (lib: :outerfaces_js_core).

  # TODO Create a hash digest of the files copied and store it in a file in the target directory.

  Examples:
  mix outerfaces.into_odd_cdn

  Currently depends on local source files.

  TODO: Copy from a public git repo or tarball.
  """
  use Mix.Task

  @default_lib_slug "outerfaces_js_core"
  @target_app_dir_base "outerfaces/projects/odd_cdn"
  @registry_file_name "outerfaces.registry.json"

  def run(args \\ []) do
    opts = parse_args(args)
    File.mkdir_p!(@target_app_dir_base)
    lib_slug = Keyword.get(opts, :lib, @default_lib_slug)
    source_base_path = Keyword.get(opts, :source_base_path)
    target_base_path = Keyword.get(opts, :target_base_path)
    source_dir = get_source_dir_for_lib(source_base_path, lib_slug)

    version = get_version_from_registry_json(source_base_path, lib_slug)
    IO.puts("Found version #{version} in #{source_dir}..")
    target_dir_with_version = "#{target_base_path}/#{lib_slug}/#{version}"
    IO.puts("Copying library files from #{source_dir} to #{target_dir_with_version}..")
    Mix.Tasks.Outerfaces.Copy.copy_files(source_dir, target_dir_with_version, source_base_path)
    IO.puts("Library files copied to #{target_dir_with_version}}")
    version
  end

  defp parse_args(args) do
    Enum.reduce(args, [], fn arg, acc ->
      [key, value] = String.split(arg, "=")
      [{String.to_atom(key), value} | acc]
    end)
  end

  defp get_source_dir_for_lib(source_base_path, lib_slug)
       when is_binary(source_base_path) and is_binary(lib_slug),
       do: "#{source_base_path}/#{lib_slug}"

  defp get_version_from_registry_json(source_base_path, lib_slug)
       when is_binary(source_base_path) and is_binary(lib_slug) do
    source_dir = get_source_dir_for_lib(source_base_path, lib_slug)
    registry_info_path = Path.expand(Path.join(source_dir, @registry_file_name))
    IO.puts("Reading #{@registry_file_name} from #{registry_info_path}")
    {:ok, registry_json} = File.read(registry_info_path)
    {:ok, %{"version" => version}} = Jason.decode(registry_json)
    version
  end
end
