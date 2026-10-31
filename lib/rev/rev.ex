defmodule Outerfaces.Rev do
  @moduledoc """
  Manages the current revision identifier for rev-pinned asset serving.

  Rev sources (in priority order):
  1. OUTERFACES_REV environment variable (for production deployments)
  2. Git SHA via `git rev-parse HEAD` (for dev/staging)
  3. Application config :outerfaces_odd, :rev
  4. Timestamp fallback (for local dev without git)

  The rev value is cached in `:persistent_term` for optimal read performance.

  ## Scoped revs

  A host serving several projects can give each its own rev, so a project's
  rev moves only when that project changes. `set_rev/2` sets the rev for a
  scope (any term naming a project, such as its directory name) and
  `current_rev/1` reads it. A scope with no rev of its own falls back to
  `current_rev/0`, so the global rev keeps working where scopes aren't used.
  """

  @rev_cache_key :outerfaces_rev_current
  @scoped_cache_key :outerfaces_rev_scoped

  @doc """
  Returns the current revision identifier.

  The rev is cached in `:persistent_term` for performance. Once set, it persists
  for the lifetime of the VM (or until explicitly invalidated).

  ## Examples

      iex> Outerfaces.Rev.current_rev()
      "abc123def456"

  """
  @spec current_rev() :: String.t()
  def current_rev do
    case :persistent_term.get(@rev_cache_key, nil) do
      nil -> fetch_and_cache_rev()
      rev -> rev
    end
  end

  @doc """
  Returns the rev for `scope`, or the global rev when the scope has none of
  its own (or `scope` is nil).

  ## Examples

      iex> Outerfaces.Rev.set_rev(:docs_site, "7-3f2a9c1d0b7e")
      :ok
      iex> Outerfaces.Rev.current_rev(:docs_site)
      "7-3f2a9c1d0b7e"

  """
  @spec current_rev(term()) :: String.t()
  def current_rev(nil), do: current_rev()

  def current_rev(scope) do
    case :persistent_term.get(@scoped_cache_key, %{}) do
      %{^scope => rev} -> rev
      _ -> current_rev()
    end
  end

  @doc "Sets the rev for `scope`, leaving the global rev and other scopes as they are."
  @spec set_rev(term(), String.t()) :: :ok
  def set_rev(scope, rev) when not is_nil(scope) and is_binary(rev) do
    revs = :persistent_term.get(@scoped_cache_key, %{})
    :persistent_term.put(@scoped_cache_key, Map.put(revs, scope, rev))
    :ok
  end

  @doc "The revs set per scope, as a map of scope => rev."
  @spec scoped_revs() :: %{optional(term()) => String.t()}
  def scoped_revs, do: :persistent_term.get(@scoped_cache_key, %{})

  @doc "Removes every scope's rev, so each falls back to the global rev again."
  @spec clear_scoped_revs() :: :ok
  def clear_scoped_revs do
    :persistent_term.erase(@scoped_cache_key)
    :ok
  end

  @doc """
  Sets the revision to a specific value and caches it.

  This is useful when you want to manually update to a specific rev without
  relying on environment variables, git, or config.

  ## Examples

      iex> Outerfaces.Rev.set_rev("new-rev-123")
      :ok
      iex> Outerfaces.Rev.current_rev()
      "new-rev-123"

  """
  @spec set_rev(String.t()) :: :ok
  def set_rev(new_rev) when is_binary(new_rev) do
    :persistent_term.put(@rev_cache_key, new_rev)
    :ok
  end

  @doc """
  Invalidates the cached rev value, forcing a fresh fetch on next `current_rev/0` call.

  This is primarily useful for testing or when you need to update the rev at runtime
  by re-detecting from environment/git/config sources.

  If you want to set a specific rev value, use `set_rev/1` instead.
  """
  @spec invalidate_cache() :: :ok
  def invalidate_cache do
    :persistent_term.erase(@rev_cache_key)
    :ok
  end

  @doc """
  Rechecks and returns the current rev by invalidating the cache and fetching fresh.

  This is a convenience method that combines `invalidate_cache/0` and `current_rev/0`
  to force a re-detection from environment/git/config sources in a single call.

  ## Examples

      iex> Outerfaces.Rev.recheck()
      "abc123def456"  # Freshly fetched from OUTERFACES_REV, git, config, or timestamp

  """
  @spec recheck() :: String.t()
  def recheck do
    invalidate_cache()
    current_rev()
  end

  # Private Functions

  @spec fetch_and_cache_rev() :: String.t()
  defp fetch_and_cache_rev do
    rev =
      env_var_rev() ||
        git_sha_rev() ||
        app_config_rev() ||
        timestamp_rev()

    :persistent_term.put(@rev_cache_key, rev)
    rev
  end

  @spec env_var_rev() :: String.t() | nil
  defp env_var_rev do
    case System.get_env("OUTERFACES_REV") do
      nil -> nil
      "" -> nil
      rev -> String.trim(rev)
    end
  end

  @spec git_sha_rev() :: String.t() | nil
  defp git_sha_rev do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.slice(0..11)

      {_output, _exit_code} ->
        nil
    end
  rescue
    # git command not available
    _error -> nil
  end

  @spec app_config_rev() :: String.t() | nil
  defp app_config_rev do
    Application.get_env(:outerfaces_odd, :rev)
  end

  @spec timestamp_rev() :: String.t()
  defp timestamp_rev do
    timestamp = System.system_time(:second)
    "ts-#{timestamp}"
  end
end
