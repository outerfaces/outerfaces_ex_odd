defmodule Mix.Tasks.Outerfaces.RemoveJsCommentsTest do
  @moduledoc """
  The comment stripper publishes what it writes, so its failures are shipped
  files. Most of these cases are not hypotheses: they are shapes that were
  already in the libraries this task runs over, and the first one is the line
  that was being published broken.
  """
  use ExUnit.Case, async: true

  import Mix.Tasks.Outerfaces.RemoveJsComments, only: [remove_js_comments: 1]

  describe "comment markers that are not comments" do
    test "a // inside a single-quoted string survives" do
      # This exact line was shipped as `return trimmed.startsWith('` — the rest
      # of it eaten, the file left unparseable.
      source = ~S|const isComment = (line) => line.trim().startsWith('//');|
      assert remove_js_comments(source) == source
    end

    test "a // inside a double-quoted string survives" do
      source = ~S|const sep = "//";|
      assert remove_js_comments(source) == source
    end

    test "a // inside a template literal survives" do
      source = ~S|const path = `${host}//${rest}`;|
      assert remove_js_comments(source) == source
    end

    test "a // inside a regex literal survives" do
      source = ~S|const doubled = /\/\/+/g;|
      assert remove_js_comments(source) == source
    end

    test "a /* inside a string survives" do
      source = ~S|const open = '/*';|
      assert remove_js_comments(source) == source
    end

    test "a URL keeps its scheme, which the old lookbehind hack existed for" do
      source = ~S|const SVG_NS = 'http://www.w3.org/2000/svg';|
      assert remove_js_comments(source) == source
    end

    test "a protocol-relative URL survives too, which the lookbehind hack could not manage" do
      source = ~S|const cdn = '//cdn.example.com/lib.js';|
      assert remove_js_comments(source) == source
    end
  end

  describe "comments that are comments" do
    test "a line comment goes, and its newline stays" do
      assert remove_js_comments("const a = 1; // why\nconst b = 2;\n") ==
               "const a = 1; \nconst b = 2;\n"
    end

    test "a block comment goes" do
      assert remove_js_comments("const a = /* inline */ 1;") == "const a =  1;"
    end

    test "a JSDoc block goes, and the blank lines it leaves are collapsed" do
      source = """
      /**
       * Does a thing.
       */
      export function thing() {}
      """

      assert remove_js_comments(source) == "\nexport function thing() {}\n"
    end

    test "a comment inside a template's interpolation is still a comment" do
      assert remove_js_comments("`${a /* drop */}`") == "`${a }`"
    end
  end

  describe "regex literal versus division" do
    test "a regex after an opening paren is a regex" do
      source = ~S|value.replace(/url\(['"]?#([^'")]+)/g, fix);|
      assert remove_js_comments(source) == source
    end

    test "a regex after `return` is a regex, not a division by `return`" do
      source = ~S|return /^[a-z0-9][a-z0-9._-]*$/.test(text);|
      assert remove_js_comments(source) == source
    end

    test "a slash in a character class does not end the regex" do
      source = ~S|const re = /[/#]|

      assert remove_js_comments(source <> "/;") == source <> "/;"
    end

    test "division is left alone" do
      assert remove_js_comments("const half = total / 2;") == "const half = total / 2;"
      assert remove_js_comments("const r = items[i] / count;") == "const r = items[i] / count;"
      assert remove_js_comments("const q = fn() / 2;") == "const q = fn() / 2;"
    end

    test "a division after a closing brace is not mistaken for a regex" do
      # The expensive direction of the ambiguity: reading this as a regex would
      # swallow everything up to the next `/` in the file.
      assert remove_js_comments("const x = {a: 1}\n/ 2;\n") == "const x = {a: 1}\n/ 2;\n"
    end
  end

  describe "strings and templates" do
    test "an escaped quote does not end a string" do
      source = ~S|const s = 'it\'s // fine';|
      assert remove_js_comments(source) == source
    end

    test "a template's interpolation can hold braces and a nested template" do
      source = ~S|const s = `${ {a: 1}.a }${ `${inner}/x` }`;|
      assert remove_js_comments(source) == source
    end

    test "an apostrophe in a comment cannot open a string" do
      assert remove_js_comments("// it's fine\nconst a = 1;\n") == "\nconst a = 1;\n"
    end
  end

  describe "containment" do
    test "an unterminated string does not swallow the rest of the file" do
      # Not valid JS, but a stripper that runs over whatever it is given should
      # damage one line rather than everything after it.
      assert remove_js_comments("const a = 'oops\nconst b = 2; // gone\n") ==
               "const a = 'oops\nconst b = 2; \n"
    end

    test "stripping twice changes nothing the second time" do
      source = """
      /** doc */
      const SVG_NS = 'http://www.w3.org/2000/svg'; // ns
      const re = /a\\/b/;
      """

      once = remove_js_comments(source)
      assert remove_js_comments(once) == once
    end
  end
end
