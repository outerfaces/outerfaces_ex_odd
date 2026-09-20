defmodule Mix.Tasks.Outerfaces.IntoOddCdnTest do
  @moduledoc """
  What this task copies becomes what the CDN serves, so the interesting cases
  are the ones where it copies too much: a library's test suite, its lockfiles,
  a `.DS_Store`. All of those were being published before the copy took rules.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Outerfaces.IntoOddCdn

  setup do
    root = Path.join(System.tmp_dir!(), "odd_cdn_test_#{System.unique_integer([:positive])}")
    source = Path.join(root, "src")
    target = Path.join(root, "out")

    write = fn rel, contents ->
      path = Path.join(source, rel)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
    end

    write.("lib/index.js", "export const a = 1;")
    write.("lib/deep/nested/thing.js", "export const b = 2;")
    write.("lib/images/art.svg", "<svg/>")
    write.("tests/thing_test.js", "// a test")
    write.("tools/build.mjs", "// a tool")
    write.("README.md", "# readme")
    write.("deno.lock", "{}")
    write.(".DS_Store", "junk")
    write.(".git/config", "[core]")

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, source: source, target: target}
  end

  defp rules(overrides \\ []) do
    IntoOddCdn.resolve_rules(overrides, %{"version" => "0.1.0"}, "some_lib")
  end

  defp copied(target) do
    target
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&Path.relative_to(&1, target))
    |> Enum.sort()
  end

  describe "defaults" do
    test "copies everything except the junk nobody wants on a CDN", ctx do
      IntoOddCdn.copy_tree(ctx.source, ctx.target, rules())

      files = copied(ctx.target)
      assert "lib/index.js" in files

      assert "lib/deep/nested/thing.js" in files,
             "nested files are copied, not just the top level"

      assert "lib/images/art.svg" in files, "non-JS assets are copied too"
      assert "README.md" in files
      refute ".DS_Store" in files
      refute ".git/config" in files
    end

    test "still copies tests and tools when nothing says otherwise", ctx do
      # The previous behaviour. Publishing them is now a choice, but it is the
      # choice a library that says nothing keeps making.
      IntoOddCdn.copy_tree(ctx.source, ctx.target, rules())
      assert "tests/thing_test.js" in copied(ctx.target)
    end
  end

  describe "exclude" do
    test "prunes a directory and everything under it", ctx do
      IntoOddCdn.copy_tree(ctx.source, ctx.target, rules(exclude: "tests,tools"))

      files = copied(ctx.target)
      refute "tests/thing_test.js" in files
      refute "tools/build.mjs" in files
      assert "lib/index.js" in files
    end

    test "prunes by glob, anywhere in the tree", ctx do
      IntoOddCdn.copy_tree(ctx.source, ctx.target, rules(exclude: "**/*.svg"))

      files = copied(ctx.target)
      refute "lib/images/art.svg" in files
      assert "lib/index.js" in files
    end

    test "a pattern that matches nothing is not an error", ctx do
      IntoOddCdn.copy_tree(ctx.source, ctx.target, rules(exclude: "does/not/exist"))
      assert "lib/index.js" in copied(ctx.target)
    end
  end

  describe "include" do
    test "an include list publishes that tree and nothing else", ctx do
      IntoOddCdn.copy_tree(ctx.source, ctx.target, rules(include: "lib"))

      files = copied(ctx.target)
      assert "lib/index.js" in files
      assert "lib/deep/nested/thing.js" in files
      assert "lib/images/art.svg" in files
      refute "README.md" in files
      refute "tests/thing_test.js" in files
      refute "deno.lock" in files
    end

    test "exclude still applies inside an include", ctx do
      IntoOddCdn.copy_tree(ctx.source, ctx.target, rules(include: "lib", exclude: "**/*.svg"))

      files = copied(ctx.target)
      assert "lib/index.js" in files
      refute "lib/images/art.svg" in files
    end

    test "a single file can be included alongside a tree", ctx do
      IntoOddCdn.copy_tree(ctx.source, ctx.target, rules(include: "lib,README.md"))

      files = copied(ctx.target)
      assert "lib/index.js" in files
      assert "README.md" in files
      refute "tools/build.mjs" in files
    end
  end

  describe "where the rules come from" do
    test "the library's registry can declare them" do
      registry = %{"version" => "0.1.0", "odd_cdn" => %{"exclude" => ["tests"]}}
      rules = IntoOddCdn.resolve_rules([], registry, "some_lib")
      assert "tests" in rules.exclude
    end

    test "task arguments win over the registry" do
      registry = %{"version" => "0.1.0", "odd_cdn" => %{"exclude" => ["tests"]}}
      rules = IntoOddCdn.resolve_rules([exclude: "tools"], registry, "some_lib")
      assert "tools" in rules.exclude
      refute "tests" in rules.exclude
    end

    test "the junk excludes are always on, whatever is configured" do
      rules = IntoOddCdn.resolve_rules([exclude: "tools"], %{"version" => "0.1.0"}, "some_lib")
      assert ".git" in rules.exclude
      assert ".DS_Store" in rules.exclude
    end

    test "an npm-style `files` key is ignored, because taken literally it ships almost nothing" do
      registry = %{"version" => "0.1.0", "files" => ["lib/*.js"]}
      rules = IntoOddCdn.resolve_rules([], registry, "some_lib")
      assert rules.include == []
    end
  end
end
