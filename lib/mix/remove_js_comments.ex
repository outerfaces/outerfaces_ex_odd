defmodule Mix.Tasks.Outerfaces.RemoveJsComments do
  use Mix.Task

  @shortdoc "Removes comment lines/blocks from .js files in the given directory"

  @moduledoc """
  Strip comments from the `.js` files under a directory, in place.

  This used to be three regexes, and the module said so: *"**Naive** RegEx
  approach – may fail for comments in string literals"*. It did fail. A file
  containing

      trimmed.startsWith('//')

  was published with the `//')` eaten and the rest of the line gone, because
  `//` inside a string is indistinguishable from `//` starting a comment
  unless you know whether you are inside a string — which is to say, unless
  you lex. Callers worked around it by excluding whole directories from
  stripping (vendored three.js, for one), which is a big hammer for a problem
  that only ever needed the scanner below.

  So: a single pass that tracks what it is inside — code, a string, a template
  literal (including `${...}` interpolation, which returns to code and can
  nest), a regex literal, a line comment, a block comment — and only removes
  a comment when it is actually in one.

  ## The one genuine ambiguity

  A `/` in code starts either a regex literal or a division, and telling them
  apart needs the grammar, not the characters. The standard heuristic is used
  here: a `/` begins a regex when the last significant token was an operator,
  an opening bracket, a statement separator, or a keyword that can be followed
  by an expression (`return /^a$/.test(x)` is real code in the wild) — and is
  division when it followed an identifier, a number, or a closing `)`/`]`/`}`.

  `}` is deliberately in the *division* group. Both readings can be wrong, but
  they are not equally wrong: mistaking a division for a regex swallows
  everything up to the next `/`, while mistaking a regex for a division just
  scans the regex body as code, which removes nothing and changes nothing
  unless that body happens to contain a quote or a comment marker. The cheap
  mistake is the one worth making.
  """

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

  # Punctuation after which a `/` starts a regex rather than a division.
  # Note the absence of `}` — see the moduledoc.
  @regex_may_follow ~c"(,=:[!&|?;+-*%^~<>{\n\r\t "

  # Keywords after which a `/` starts a regex: `return /re/.test(x)`.
  @regex_keywords ~w(return typeof instanceof in of new delete void throw case do else yield await)

  @doc """
  Remove single-line (`// ...`) and block (`/* ... */`) comments from JS source,
  leaving comment-shaped text inside strings, template literals and regex
  literals alone.

  Newlines are preserved where a line comment was, then runs of blank lines are
  collapsed — matching what this task has always emitted.
  """
  def remove_js_comments(content) when is_binary(content) do
    content
    |> scan(:code, [], nil, [])
    |> IO.iodata_to_binary()
    |> then(&Regex.replace(~r/\n{2,}/, &1, "\n"))
  end

  # scan(rest, state, acc, last_significant_char, interpolation_stack)
  #
  # `acc` is reverse iodata. `last` is the last significant character emitted in
  # code state, which is all the regex/division heuristic needs beyond the
  # trailing word, which is recovered from `acc` on demand.

  defp scan(<<>>, _state, acc, _last, _stack), do: Enum.reverse(acc)

  # --- code ------------------------------------------------------------------

  defp scan(<<"//", rest::binary>>, :code, acc, last, stack),
    do: scan(rest, :line_comment, acc, last, stack)

  defp scan(<<"/*", rest::binary>>, :code, acc, last, stack),
    do: scan(rest, :block_comment, acc, last, stack)

  defp scan(<<"/", rest::binary>>, :code, acc, last, stack) do
    if regex_may_follow?(last, acc) do
      scan(rest, {:regex, false}, ["/" | acc], nil, stack)
    else
      scan(rest, :code, ["/" | acc], ?/, stack)
    end
  end

  defp scan(<<q::utf8, rest::binary>>, :code, acc, _last, stack) when q in [?", ?'],
    do: scan(rest, {:string, q}, [<<q::utf8>> | acc], nil, stack)

  defp scan(<<"`", rest::binary>>, :code, acc, _last, stack),
    do: scan(rest, :template, ["`" | acc], nil, stack)

  # `${` opens an interpolation: back to code, remembering how to get out.
  defp scan(<<"${", rest::binary>>, :template, acc, _last, stack),
    do: scan(rest, :code, ["${" | acc], nil, [0 | stack])

  # Braces inside an interpolation: only the one that closes it returns to the
  # template, so `${ {a: 1} }` does not end early.
  defp scan(<<"{", rest::binary>>, :code, acc, _last, [depth | stack]),
    do: scan(rest, :code, ["{" | acc], ?{, [depth + 1 | stack])

  defp scan(<<"}", rest::binary>>, :code, acc, _last, [0 | stack]),
    do: scan(rest, :template, ["}" | acc], nil, stack)

  defp scan(<<"}", rest::binary>>, :code, acc, _last, [depth | stack]),
    do: scan(rest, :code, ["}" | acc], ?}, [depth - 1 | stack])

  defp scan(<<c::utf8, rest::binary>>, :code, acc, last, stack) do
    next_last = if whitespace?(c), do: last, else: c
    scan(rest, :code, [<<c::utf8>> | acc], next_last, stack)
  end

  # --- line comment ----------------------------------------------------------
  # The newline survives, so nothing joins the line below it.

  defp scan(<<"\n", rest::binary>>, :line_comment, acc, last, stack),
    do: scan(rest, :code, ["\n" | acc], last, stack)

  defp scan(<<"\r", rest::binary>>, :line_comment, acc, last, stack),
    do: scan(rest, :code, ["\r" | acc], last, stack)

  defp scan(<<_::utf8, rest::binary>>, :line_comment, acc, last, stack),
    do: scan(rest, :line_comment, acc, last, stack)

  # --- block comment ---------------------------------------------------------

  defp scan(<<"*/", rest::binary>>, :block_comment, acc, last, stack),
    do: scan(rest, :code, acc, last, stack)

  defp scan(<<_::utf8, rest::binary>>, :block_comment, acc, last, stack),
    do: scan(rest, :block_comment, acc, last, stack)

  # --- strings ---------------------------------------------------------------

  defp scan(<<"\\", c::utf8, rest::binary>>, {:string, q}, acc, last, stack),
    do: scan(rest, {:string, q}, [<<c::utf8>>, "\\" | acc], last, stack)

  defp scan(<<q::utf8, rest::binary>>, {:string, q}, acc, _last, stack),
    do: scan(rest, :code, [<<q::utf8>> | acc], q, stack)

  # A bare newline cannot appear in a '' or "" string, so if one shows up the
  # quote was not a string after all. Bailing out contains the damage to the
  # line instead of swallowing the rest of the file.
  defp scan(<<"\n", rest::binary>>, {:string, _q}, acc, _last, stack),
    do: scan(rest, :code, ["\n" | acc], ?\n, stack)

  defp scan(<<c::utf8, rest::binary>>, {:string, q}, acc, last, stack),
    do: scan(rest, {:string, q}, [<<c::utf8>> | acc], last, stack)

  # --- template literals -----------------------------------------------------

  defp scan(<<"\\", c::utf8, rest::binary>>, :template, acc, last, stack),
    do: scan(rest, :template, [<<c::utf8>>, "\\" | acc], last, stack)

  defp scan(<<"`", rest::binary>>, :template, acc, _last, stack),
    do: scan(rest, :code, ["`" | acc], ?`, stack)

  defp scan(<<c::utf8, rest::binary>>, :template, acc, last, stack),
    do: scan(rest, :template, [<<c::utf8>> | acc], last, stack)

  # --- regex literals --------------------------------------------------------
  # The boolean is "inside a character class", where `/` is not a terminator.

  defp scan(<<"\\", c::utf8, rest::binary>>, {:regex, in_class}, acc, last, stack),
    do: scan(rest, {:regex, in_class}, [<<c::utf8>>, "\\" | acc], last, stack)

  defp scan(<<"[", rest::binary>>, {:regex, false}, acc, last, stack),
    do: scan(rest, {:regex, true}, ["[" | acc], last, stack)

  defp scan(<<"]", rest::binary>>, {:regex, true}, acc, last, stack),
    do: scan(rest, {:regex, false}, ["]" | acc], last, stack)

  defp scan(<<"/", rest::binary>>, {:regex, false}, acc, _last, stack),
    do: scan(rest, :code, ["/" | acc], ?/, stack)

  # A regex literal cannot span lines either.
  defp scan(<<"\n", rest::binary>>, {:regex, _}, acc, _last, stack),
    do: scan(rest, :code, ["\n" | acc], ?\n, stack)

  defp scan(<<c::utf8, rest::binary>>, {:regex, in_class}, acc, last, stack),
    do: scan(rest, {:regex, in_class}, [<<c::utf8>> | acc], last, stack)

  # --- the heuristic ---------------------------------------------------------

  defp regex_may_follow?(nil, _acc), do: true

  defp regex_may_follow?(last, acc) do
    cond do
      last in @regex_may_follow -> true
      identifier_char?(last) -> trailing_word(acc) in @regex_keywords
      true -> false
    end
  end

  # The identifier immediately before the `/`, to tell `return /re/` (a regex)
  # from `total /re/` (a division by something oddly named). `acc` is reverse
  # iodata, so this walks backwards: skip the whitespace, then take the word.
  defp trailing_word(acc), do: trailing_word(acc, :skip_whitespace, [])

  defp trailing_word([], _mode, word), do: List.to_string(word)

  defp trailing_word([chunk | rest], mode, word) do
    chars = chunk |> IO.iodata_to_binary() |> String.to_charlist() |> Enum.reverse()

    case take_word(chars, mode, word) do
      {:done, word} -> List.to_string(word)
      {:cont, mode, word} -> trailing_word(rest, mode, word)
    end
  end

  defp take_word([], mode, word), do: {:cont, mode, word}

  defp take_word([c | rest], :skip_whitespace, word) do
    cond do
      whitespace?(c) -> take_word(rest, :skip_whitespace, word)
      identifier_char?(c) -> take_word(rest, :word, [c | word])
      true -> {:done, word}
    end
  end

  defp take_word([c | rest], :word, word) do
    if identifier_char?(c),
      do: take_word(rest, :word, [c | word]),
      else: {:done, word}
  end

  defp identifier_char?(c),
    do: (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or (c >= ?0 and c <= ?9) or c in [?_, ?$]

  defp whitespace?(c), do: c in [?\s, ?\t, ?\n, ?\r]

  defp parse_args(args) do
    Enum.reduce(args, [], fn arg, acc ->
      [key, value] = String.split(arg, "=")
      [{String.to_atom(key), value} | acc]
    end)
  end
end
