defmodule ParseyTest do
    use ExUnit.Case
    doctest Parsey

    test "parsing with no rules" do
        assert ["test"] == Parsey.parse("test", [])
    end

    test "simple matching" do
        assert [{ :consonant, ["t"] }, { :vowel, ["e"] }, { :consonant, ["st"] }] == Parsey.parse("test", [vowel: ~r/\A[aeiou]+/, consonant: ~r/\A[^aeiou]+/])
        assert [{ :consonant, ["t"] }, { :vowel, ["e"] }, { :consonant, ["st"] }] == Parsey.parse("test", [vowel: %{ match: ~r/\A[aeiou]+/ }, consonant: %{ match: ~r/\A[^aeiou]+/ }])
        assert [{ :bracket, [{ :consonant, ["t"] }, { :vowel, ["e"] }, { :consonant, ["st"] }] }] == Parsey.parse("(test)", [bracket: ~r/\A\((.*?)\)/, vowel: ~r/\A[aeiou]+/, consonant: ~r/\A[^aeiou]+/])
        assert ["t", { :vowel, ["e"] }, "st"] == Parsey.parse("test", [vowel: fn
            <<"e", _ :: binary>> -> [{ 0, 1 }]
            _ -> nil
        end])
        assert [{ :test, ["abc"] }] == Parsey.parse("abc", test: ~r/abc/)
        assert [{ :test, ["a"] }] == Parsey.parse("abc", test: ~r/(a)bc/)
        assert [{ :test, ["c"] }] == Parsey.parse("abc", test: ~r/(a)(b)(c)/)
        assert [{ :test, ["b"] }] == Parsey.parse("abc", test: %{ match: ~r/(a)(b)(c)/, capture: 2 })
    end

    test "simple formatting" do
        assert [{ :test, ["ac"] }] == Parsey.parse("abc", test: %{ match: ~r/abc/, format: &String.replace(&1, "b", "") })
    end

    test "simple options" do
        assert ["t", { :vowel, ["e"], :test }, "st"] == Parsey.parse("test", [vowel: %{ match: ~r/\A[aeiou]+/, option: :test }])
        assert [{ :bracket, [{ :consonant, ["t"], :t }, { :vowel, ["e"] }, { :consonant, ["s"] }, { :consonant, ["t"], :t }] }] == Parsey.parse("(test)", [bracket: ~r/\A\((.*?)\)/, vowel: ~r/\A[aeiou]+/, consonant: ~r/\A([^aeiout]+)/, consonant: %{ match: ~r/\A(t)/, option: :t }])
        assert ["t", { :vowel, ["e"], { "est", [{ 0, 1 }] } }, "st"] == Parsey.parse("test", [vowel: %{ match: ~r/\A[aeiou]+/, option: &({ &1, &2 })}])
    end

    test "simple exclusion" do
        assert [{ :bracket, ["t", { :vowel, ["e"] }] }, { :consonant, ["st"] }] == Parsey.parse("(te)st", [bracket: %{ match: ~r/\A\((.*?)\)/, exclude: :consonant }, vowel: ~r/\A[aeiou]+/, consonant: ~r/\A[^aeiou]+/])
        assert [{ :bracket, ["te", { :consonant, ["s"] }, "t"] }] == Parsey.parse("(test)", [bracket: %{ match: ~r/\A\((.*?)\)/, exclude: [{ :consonant, :t }, :vowel] }, vowel: ~r/\A[aeiou]+/, consonant: ~r/\A([^aeiout]+)/, consonant: %{ match: ~r/\A(t)/, option: :t }])
    end

    test "simple inclusion" do
        assert [{ :bracket, ["t", { :inner_vowel, ["e"] }, { :consonant, ["s"] }, "t"] }] == Parsey.parse("(test)", [bracket: %{ match: ~r/\A\((.*?)\)/, exclude: [{ :consonant, :t }, :vowel], include: [inner_vowel: ~r/\A[aeiou]+/] }, vowel: ~r/\A[aeiou]+/, consonant: ~r/\A([^aeiout]+)/, consonant: %{ match: ~r/\A(t)/, option: :t }])
    end

    test "simple replace" do
        assert [{ :bracket, ["test"] }] == Parsey.parse("(test)", [bracket: %{ match: ~r/\A\((.*?)\)/, rules: [] }, vowel: ~r/\A[aeiou]+/, consonant: ~r/\A([^aeiout]+)/, consonant: %{ match: ~r/\A(t)/, option: :t }])
        assert [{ :bracket, ["t", { :inner_vowel, ["e"] }, "st"] }] == Parsey.parse("(test)", [bracket: %{ match: ~r/\A\((.*?)\)/, rules: [inner_vowel: ~r/\A[aeiou]+/] }, vowel: ~r/\A[aeiou]+/, consonant: ~r/\A([^aeiout]+)/, consonant: %{ match: ~r/\A(t)/, option: :t }])
    end

    test "simple ignore" do
        assert [{ :consonant, ["t"] }, { :consonant, ["st"] }] == Parsey.parse("test", [vowel: %{ match: ~r/\A[aeiou]+/, ignore: true }, consonant: ~r/\A[^aeiou]+/])
        assert ["t", "t"] == Parsey.parse("test", [invalid: %{ match: ~r/\A[^t]/, ignore: true }])
        assert ["t", "t"] == Parsey.parse("tests", [invalid: %{ match: ~r/\A[^t]/, ignore: true }])
        assert [{ :valid, ["t"] }, { :valid, ["t"] }] == Parsey.parse("test", [invalid: %{ match: ~r/\A[^t]/, ignore: true }, valid: ~r/\At/])
    end

    test "complex parsing Lisp-like" do
        rules = [
            whitespace: %{ match: ~r/\A\s/, ignore: true },
            expression: %{ match: ~r/\A\((.*)\)/, exclude: nil },
            integer: %{ match: ~r/\A\d+/, rules: [] },
            atom: %{ match: ~r/\A\S+/, rules: [] }
        ]

        assert [
            expression: [
                atom: ["+"],
                expression: [
                    atom: ["+"],
                    integer: ["1"],
                    integer: ["2"]
                ],
                integer: ["15"]
            ]
        ] == Parsey.parse("(+ (+ 1 2) 15)", rules)
    end

    test "complex parsing XML-like" do
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
        source = """
        <array>
            <integer>1</integer>
            <integer>2</integer>
        </array>
        <array>
            <integer>3</integer>
            <integer>4</integer>
        </array>
        """

        assert [
            { :element, [
                { :element, [value: ["1"]], "integer" },
                { :element, [value: ["2"]], "integer" }
            ], "array" },
            { :element, [
                { :element, [value: ["3"]], "integer" },
                { :element, [value: ["4"]], "integer" }
            ], "array" },
        ] == Parsey.parse(source, rules)
    end
end
