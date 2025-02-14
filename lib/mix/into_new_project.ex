defmodule Mix.Tasks.Outerfaces.IntoNewProject do
  @moduledoc """
  Copies the (for now) hello_world example project to the app's outerfaces/projects directory.
  Options:  name=my_new_outerfaces_project

  If no name is specified, the project will be copied to outerfaces/projects/hello_world,
  unless a project with that name already exists.

  Examples (from an app using Outerfaces):
  mix outerfaces.into_new_project
  mix outerfaces.into_new_project name=my_new_outerfaces_project

  Currently depends on local source files.
  """
  use Mix.Task

  @example_dir "outerfaces_js_examples"
  @default_example_project "hello-world"
  @target_app_dir_base "outerfaces/projects"

  def run(args \\ []) do
    opts = parse_args(args)

    source_base_path = Keyword.get(opts, :source_base_path)
    example_base_path = "#{source_base_path}/#{@example_dir}"

    full_source_dir = Path.join(example_base_path, @default_example_project)
    IO.puts("Copying Outerfaces starter project at #{full_source_dir}..")

    File.mkdir_p!(@target_app_dir_base)

    project_name = Keyword.get(opts, :name, @default_example_project)

    target_base_dir = Keyword.get(opts, :target_base_dir, @target_app_dir_base)

    full_target_dir = Path.expand("#{target_base_dir}/#{project_name}")

    if File.exists?(full_target_dir) do
      IO.puts("Project #{project_name} already exists in #{@target_app_dir_base}!")
    else
      File.mkdir_p!(full_target_dir)
      IO.puts("Copying starter project into outerfaces/projects/#{project_name}..")
      File.cp_r!(full_source_dir, full_target_dir)
      IO.puts("Done!")
    end
  end

  defp parse_args(args) do
    Enum.reduce(args, [], fn arg, acc ->
      [key, value] = String.split(arg, "=")
      [{String.to_atom(key), value} | acc]
    end)
  end
end
