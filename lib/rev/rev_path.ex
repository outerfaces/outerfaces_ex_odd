defmodule Outerfaces.RevPath do
  @moduledoc """
  Canonical URL path builder for rev-pinned assets.

  This module provides a single source of truth for building rev-pinned asset URLs.
  All asset/module URLs should use this format to ensure consistency across the system.

  ## Canonical Format

  All rev-pinned URLs follow this structure:

      <origin>/__rev/<rev>/<namespace>/<path>

  Where:
  - `origin` - CDN origin (empty string for unified mode, full URL for direct mode)
  - `rev` - Git SHA or revision identifier
  - `namespace` - Asset namespace: "spa", "cdn", "apps", etc.
  - `path` - Asset path relative to namespace

  ## Examples

      # Unified proxy mode (origin = ""):
      asset("", "abc123", "cdn", "lib/foo.js")
      #=> "/__rev/abc123/cdn/lib/foo.js"

      # Direct CDN mode (origin = "http://localhost:60032"):
      asset("http://localhost:60032", "abc123", "cdn", "lib/foo.js")
      #=> "http://localhost:60032/__rev/abc123/cdn/lib/foo.js"

      # SPA assets (always relative):
      asset("", "abc123", "spa", "main.js")
      #=> "/__rev/abc123/spa/main.js"

  """

  @doc """
  Builds a canonical rev-pinned asset URL.

  ## Parameters

  - `origin` - CDN origin (empty string for same-origin, full URL for cross-origin)
  - `rev` - Revision identifier (git SHA, etc.)
  - `namespace` - Asset namespace ("spa", "cdn", "apps", etc.)
  - `path` - Asset path (should NOT start with "/")

  ## Returns

  Canonical rev-pinned URL string

  ## Examples

      iex> Outerfaces.RevPath.asset("", "abc123", "cdn", "lib/foo.js")
      "/__rev/abc123/cdn/lib/foo.js"

      iex> Outerfaces.RevPath.asset("http://localhost:60032", "abc123", "cdn", "lib/foo.js")
      "http://localhost:60032/__rev/abc123/cdn/lib/foo.js"

  """
  @spec asset(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def asset(origin, rev, namespace, path) do
    # Normalize path to ensure no leading slash
    normalized_path = String.trim_leading(path, "/")

    "#{origin}/__rev/#{rev}/#{namespace}/#{normalized_path}"
  end

  @doc """
  Builds a canonical rev-pinned CDN asset URL.

  Convenience wrapper for `asset/4` with namespace="cdn".

  ## Examples

      iex> Outerfaces.RevPath.cdn_asset("", "abc123", "lib/foo.js")
      "/__rev/abc123/cdn/lib/foo.js"

  """
  @spec cdn_asset(String.t(), String.t(), String.t()) :: String.t()
  def cdn_asset(origin, rev, path) do
    asset(origin, rev, "cdn", path)
  end

  @doc """
  Builds a canonical rev-pinned SPA asset URL.

  Convenience wrapper for `asset/4` with namespace="spa".
  SPA assets are always same-origin (origin is ignored).

  ## Examples

      iex> Outerfaces.RevPath.spa_asset("abc123", "main.js")
      "/__rev/abc123/spa/main.js"

  """
  @spec spa_asset(String.t(), String.t()) :: String.t()
  def spa_asset(rev, path) do
    asset("", rev, "spa", path)
  end
end
