defmodule Mix.Tasks.Outerfaces.RemoveJsComments do
  use Mix.Task

  @shortdoc "Removes comment lines/blocks from .js files in the given directory"

  @impl Mix.Task
  def run(args \\ []) when is_list(args) do
    Mix.Task.reenable("outerfaces.remove_js_comments")
    args = parse_args(args)
    dir = Keyword.get(args, :dir, "priv/static/outerfaces/projects")
    js_files = Path.wildcard("#{dir}/**/*.js")
    IO.puts("Removing comments from .js files in #{dir}...")

    Enum.each(js_files, &remove_comments_from_file/1)
  end

  defp remove_comments_from_file(file_path) do
    file_path
    |> File.read!()
    |> remove_js_comments()
    |> then(&File.write!(file_path, &1))
  end

  @doc """
  Remove single-line (`// ...`) and block (`/* ... */`) comments from the given string.

  **Naive** RegEx approach – may fail for comments in string literals or other edge cases.
  """
  def remove_js_comments(content) do
    Regex.replace(~r{(?<!:)//[^\n\r]*}, content, "")
    |> then(fn content ->
      Regex.replace(~r{/\*.*?\*/}s, content, "")
    end)
    |> then(fn content ->
      Regex.replace(~r/\n{2,}/, content, "\n")
    end)
  end

  defp parse_args(args) do
    Enum.reduce(args, [], fn arg, acc ->
      [key, value] = String.split(arg, "=")
      [{String.to_atom(key), value} | acc]
    end)
  end
end
