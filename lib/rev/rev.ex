defmodule Outerfaces.Rev do
  @moduledoc """
  Manages the current revision identifier for rev-pinned asset serving.

  Rev sources (in priority order):
  1. OUTERFACES_REV environment variable (for production deployments)
  2. Git SHA via `git rev-parse HEAD` (for dev/staging)
  3. Application config :outerfaces_odd, :rev
  4. Timestamp fallback (for local dev without git)

  The rev value is cached in `:persistent_term` for optimal read performance.
  """

  @rev_cache_key :outerfaces_rev_current

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
  Invalidates the cached rev value, forcing a fresh fetch on next `current_rev/0` call.

  This is primarily useful for testing or when you need to update the rev at runtime.
  """
  @spec invalidate_cache() :: :ok
  def invalidate_cache do
    :persistent_term.erase(@rev_cache_key)
    :ok
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
