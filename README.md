# Parsey
An elixir library to parse non-complex nested inputs with a given ruleset.

Example
-------
```elixir
rules = [
    whitespace: %{ match: ~r/\A\s/, ignore: true },
    element_end: %{ match: ~r/\A<\/.*?>/, ignore: true },
    element: %{ match: fn
        input = <<"<", _ :: binary>> ->
            elements = String.splitter(input, "<", trim: true)

            [first] = Enum.take(elements, 1)
            [{ 0, tag_length }] = Regex.run(~r/\A.*?>/, first, return: :index)
            tag_length = tag_length + 1

            { 0, length } = Stream.drop(elements, 1) |> Enum.reduce_while({ 1, 0 }, fn
                element = <<"/", _ :: binary>>, { 1, length } ->
                    [{ 0, tag_length }] = Regex.run(~r/\A.*?>/, element, return: :index)
                    { :halt, { 0, length + tag_length + 1 } }
                element = <<"/", _ :: binary>>, { count, length } -> { :cont, { count - 1, length + String.length(element) + 1 } }
                element, { count, length } -> { :cont, { count + 1, length + String.length(element) + 1 } }
            end)

            length = length + String.length(first) + 1
            [{ 0, length }, {1, tag_length - 2}, { tag_length, length - tag_length }]
        _ -> nil
    end, exclude: nil, option: fn input, [_, { index, length }, _] -> String.slice(input, index, length) end },
    value: %{ match: ~r/\A\d+/, rules: [] }
]

input = """
<array>
    <integer>1</integer>
    <integer>2</integer>
</array>
<array>
    <integer>3</integer>
    <integer>4</integer>
</array>
"""

Parsey.parse(input, rules)
#[
#    { :element, [
#        { :element, [value: ["1"]], "integer" },
#        { :element, [value: ["2"]], "integer" }
#    ], "array" },
#    { :element, [
#        { :element, [value: ["3"]], "integer" },
#        { :element, [value: ["4"]], "integer" }
#    ], "array" },
#]
```

Installation
------------
```elixir
defp deps do
    [{ :parsey, "~> 0.0.1" }]
end
```
