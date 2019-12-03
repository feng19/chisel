defmodule Chisel.Font do
  @moduledoc """
  Font
  """

  alias Chisel.Font
  alias Font.Glyph

  @type t :: %__MODULE__{
          name: String.t(),
          glyphs: %{Glyph.codepoint() => Glyph.t()},
          size: {w :: integer(), h :: integer()},
          offset: {x :: integer(), y :: integer()}
        }

  defstruct name: nil,
            glyphs: nil,
            size: nil,
            offset: nil

  @doc """
  Loads a font from a file
  """
  @spec load(filename :: String.t()) :: {:ok, Font.t()} | {:error, term()}
  defdelegate load(filename), to: Chisel.Font.Loader, as: :load_font

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(font, _opts) do
      concat(["#Font<#{font.name}>"])
    end
  end
end