defmodule Chisel.Font.Loader do
  alias Chisel.Font
  alias Chisel.Font.Glyph

  defstruct font: nil, props?: nil, total_chars: nil, char: nil, glyphs: nil

  def load_font(filename) do
    with {:ok, content} <- File.read(filename),
         content_charlist <- String.to_charlist(content),
         {:ok, tokens1, _} <- :bdf_lexer.string(content_charlist),
         {:ok, tokens2} <- :bdf_parser.parse(tokens1) do
      tokens2
      |> parse()
      |> finish_font()
      |> ensure_offset()
      |> ensure_size()
      |> ensure_name(filename)
    end
  end

  defp ensure_name({:ok, %Font{name: nil} = font}, filename),
    do: {:ok, %{font | name: Path.basename(filename)}}

  defp ensure_name(res, _filename),
    do: res

  defp ensure_offset({:ok, %Font{offset: nil} = font}),
    do: {:ok, %{font | offset: {0, 0}}}

  defp ensure_offset(res),
    do: res

  defp ensure_size({:ok, %Font{size: nil, glyphs: glyphs} = font}) do
    size =
      Enum.reduce(glyphs, {0, 0}, fn {_, %{size: {w, h}, offset: {ox, oy}}}, {cw, ch} ->
        cw1 = max(w + ox, cw)
        ch1 = max(h + oy, ch)

        {cw1, ch1}
      end)

    {:ok, %{font | size: size}}
  end

  defp ensure_size(res),
    do: res

  defp parse(tokens),
    do: Enum.reduce_while(tokens, create_context(), &parse/2)

  defp parse({:keyword, "STARTFONT", _version}, %{char: nil} = context),
    do: continue(context)

  defp parse({:keyword, "ENDFONT", []}, %{char: nil} = context) do
    context
    |> finish_font()
    |> continue()
  end

  defp parse({:keyword, "FONT", name}, %{char: nil} = context),
    do: continue(%{context | font: %{context.font | name: Enum.join(name)}})

  defp parse({:keyword, "SIZE", [_, _, _]}, %{char: nil} = context),
    do: continue(context)

  defp parse({:keyword, "STARTPROPERTIES", [_]}, %{char: nil} = context),
    do: continue(%{context | props?: true})

  defp parse({:keyword, "ENDPROPERTIES", []}, %{props?: true} = context),
    do: continue(%{context | props?: nil})

  defp parse(_, %{props?: true} = context),
    do: continue(%{context | props?: true})

  defp parse({:keyword, "CHARS", [total]}, %{char: nil} = context),
    do: continue(%{context | total_chars: parse_int!(total)})

  defp parse({:keyword, "FONTBOUNDINGBOX", args}, %{char: nil} = context) do
    [w, h, ox, oy] = parse_int!(args)

    context
    |> update_font(fn font ->
      %{font | size: {w, h}, offset: {ox, oy}}
    end)
    |> continue()
  end

  defp parse({:keyword, "STARTCHAR", [name]}, %{char: nil} = context) do
    context
    |> update_char(fn _ -> %Glyph{name: name} end)
    |> continue()
  end

  defp parse([row], %{char: %Glyph{data: data, size: {gw, gh}}} = context)
       when length(data) < gh do
    bits = trunc(String.length(row) / 2) * 8
    value = parse_int!(row, 16)
    <<row_data::bitstring-size(gw), _::bitstring>> = <<value::big-unsigned-integer-size(bits)>>
    data = [row_data | context.char.data]

    context
    |> update_char(fn char -> %{char | data: data} end)
    |> continue()
  end

  defp parse({:keyword, "BITMAP", []}, %{char: %Glyph{}} = context) do
    context
    |> update_char(fn char -> %{char | data: []} end)
    |> continue()
  end

  defp parse({:keyword, "ENCODING", [codepoint]}, %{char: %Glyph{}} = context) do
    context
    |> update_char(fn char -> %{char | codepoint: parse_int!(codepoint)} end)
    |> continue()
  end

  defp parse({:keyword, "DWIDTH", [dwx, _]}, %{char: %Glyph{}} = context) do
    dwx1 = parse_int!(dwx)

    context
    |> update_char(fn char -> %{char | dwx: dwx1} end)
    |> continue()
  end

  defp parse({:keyword, "SWIDTH", [_, _]}, %{char: %Glyph{}} = context) do
    continue(context)
  end

  defp parse({:keyword, "BBX", args}, %{char: %Glyph{}} = context) do
    [w, h, ox, oy] = parse_int!(args)

    context
    |> update_char(fn char ->
      %{char | size: {w, h}, offset: {ox, oy}}
    end)
    |> continue()
  end

  defp parse({:keyword, "ENDCHAR", []}, %{char: %Glyph{data: data, size: {_, h}}} = context)
       when length(data) == h do
    %{char: char} = context

    char = %{char | data: Enum.reverse(data)}

    context
    |> add_glyph(char)
    |> update_char(fn _ -> nil end)
    |> continue()
  end

  defp parse(offense, _),
    do: halt({:error, {:parse, offense}})

  defp finish_font({:ok, %Font{}} = res),
    do: res

  defp finish_font(%__MODULE__{char: nil, glyphs: glyphs} = context) do
    font_glyphs = Map.new(glyphs, fn %{codepoint: k} = v -> {k, v} end)

    %{font: font} =
      context
      |> update_font(fn font ->
        %{font | glyphs: font_glyphs}
      end)

    {:ok, font}
  end

  defp finish_font(_) do
    {:error, :load}
  end

  defp create_context() do
    %__MODULE__{
      char: nil,
      font: %Font{},
      glyphs: []
    }
  end

  defp continue(context),
    do: {:cont, context}

  defp halt(result),
    do: {:halt, result}

  defp update_char(context, fun),
    do: %{context | char: fun.(context.char)}

  defp add_glyph(context, glyph),
    do: %{context | glyphs: [glyph | context.glyphs]}

  defp update_font(context, fun),
    do: %{context | font: fun.(context.font)}

  defp parse_int!(str, base \\ 10)

  defp parse_int!(strs, base) when is_list(strs),
    do: Enum.map(strs, &parse_int!(&1, base))

  defp parse_int!(str, base) when is_binary(str) do
    case Integer.parse(str, base) do
      {value, ""} -> value
      _ -> raise {:error, {:parse_int, str}}
    end
  end
end
