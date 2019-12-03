defmodule Chisel.Renderer do
  @moduledoc """
  The renderer is capable of draw the text on any target using for that
  a function that receives the x, y coordinates of the pixel to be painted.
  """

  alias Chisel.Font
  alias Chisel.Font.Glyph

  @typedoc """
  The function used to paint the canvas.

  Chisel will use this function to draw the text.
  """
  @type pixel_fun :: (x :: integer(), y :: integer() -> term())

  @doc """
  Draws an string

  The coordinates (`tlx`, `tly`) are for the top left corner.
  """
  @spec draw_text(
          text :: String.t(),
          tlx :: integer(),
          tly :: integer(),
          font :: Font.t(),
          put_pixel :: pixel_fun
        ) ::
          {x :: integer(), y :: integer()}
  def draw_text(text, tlx, tly, %Font{} = font, put_pixel) when is_binary(text) do
    text
    |> to_charlist()
    |> Enum.reduce({tlx, tly}, fn char, {x, y} ->
      draw_char(char, x, y, font, put_pixel)
    end)
  end

  @doc """
  Draws a character using the codepoint

  The coordinates (`tlx`, `tly`) are for the top left corner.
  """
  @spec draw_char(
          codepoint :: integer(),
          clx :: integer(),
          cly :: integer(),
          font :: Font.t(),
          put_pixel :: pixel_fun
        ) ::
          {x :: integer(), y :: integer()}
  def draw_char(codepoint, clx, cly, %Font{} = font, put_pixel) when is_integer(codepoint) do
    %{size: {_, font_h}} = font

    case lookup_glyph(codepoint, font) do
      %Glyph{} = glyph ->
        draw_glyph(glyph, clx, cly + font_h, put_pixel)

        glyph_dx = glyph.dwx

        {clx + glyph_dx, cly}

      _ ->
        {clx, cly}
    end
  end

  @doc """
  Gets the size of the rendered string using the font provided
  """
  @spec get_text_width(
          text :: String.t(),
          font :: Font.t()
        ) :: integer()
  def get_text_width(text, %Font{} = font) when is_binary(text) do
    to_charlist(text)
    |> Enum.reduce(0, fn char, size ->
      case lookup_glyph(char, font) do
        %Glyph{} = glyph ->
          glyph_dx = glyph.dwx

          size + glyph_dx

        _ ->
          size
      end
    end)
  end

  defp draw_glyph(%Glyph{} = glyph, gx, gy, put_pixel) do
    %{
      data: data,
      size: {_bb_w, bb_h},
      offset: {bb_xoff, bb_yoff}
    } = glyph

    x = gx - bb_xoff
    y = gy - bb_yoff - bb_h

    do_render_glyph(data, {x, y}, put_pixel)
  end

  defp do_render_glyph(rows, pos, put_pixel, iy \\ 0)

  defp do_render_glyph([], _pos, _put_pixel, _iy),
    do: nil

  defp do_render_glyph([row | rows], pos, put_pixel, iy) do
    render_glyph_row(row, pos, iy, put_pixel)

    do_render_glyph(rows, pos, put_pixel, iy + 1)
  end

  defp render_glyph_row(row, pos, iy, put_pixel, ix \\ 0)

  defp render_glyph_row(<<>>, _pos, _iy, _put_pixel, _ix),
    do: nil

  defp render_glyph_row(<<1::1, rest::bitstring>>, {x, y} = pos, iy, put_pixel, ix) do
    put_pixel.(x + ix, y + iy)
    render_glyph_row(rest, pos, iy, put_pixel, ix + 1)
  end

  defp render_glyph_row(<<_::1, rest::bitstring>>, pos, iy, put_pixel, ix),
    do: render_glyph_row(rest, pos, iy, put_pixel, ix + 1)

  defp lookup_glyph(char, font),
    do: Map.get(font.glyphs, char)
end