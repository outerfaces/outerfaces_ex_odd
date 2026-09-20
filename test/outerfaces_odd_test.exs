defmodule Outerfaces.OddTest do
  use ExUnit.Case

  # The module this doctested was `OuterfacesOdd`, left over from `mix new`.
  # It was renamed to `Outerfaces.Odd` and the test was not, so `mix test`
  # failed to compile and every suite in this project had to be run by naming
  # its file.
  doctest Outerfaces.Odd
end
