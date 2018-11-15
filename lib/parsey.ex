defmodule Parsey do
    @moduledoc """
      A library to setup basic parsing requirements for non-complex nested
      inputs.

      Parsing behaviours are defined using rulesets, these sets take the format
      of <code class="inline">[<a href="#t:rule/0">rule</a>]</code>. Rulesets are
      matched against in the order defined. The first rule in the set will have a
      higher priority than the last rule in the set.

      A <code class="inline"><a href="#t:rule/0">rule</a></code> is a matching
      expression that is named. The name of a rule can be any atom, and multiple
      rules can consist of the same name. While the matching expression can be
      either a Regex expression or a function.

      Rules may additionally be configured to specify the additional options that
      will be returned in the <code class="inline"><a href="#t:ast/0">ast</a></code>,
      or the ruleset modification behaviour (what rules to exclude, include or
      re-define), and if the rule should be ignored (not added to the
      <code class="inline"><a href="#t:ast/0">ast</a></code>).

      The default behaviour of a matched rule is to remove all rules with the same
      name from the ruleset, and then try further match the matched input with the
      new ruleset. Returning the <code class="inline"><a href="#t:ast/0">ast</a></code>
      one completion.

      The behaviour of matchers (applies to both regex and functions) is return a
      list of indices `[{ index, length }]` where the first `List.first` tuple in
      the list is used to indicate the portion of the input to be removed, while
      the last `List.last` is used to indicate the portion of the input to be
      focused on (parsed further).
    """

    @type name :: atom
    @type matcher :: Regex.t | (String.t -> (nil | [{ integer, integer }]))
    @type formatter :: String.t | (String.t -> String.t)
    @type option :: any
    @type excluder :: name | { name, option }
    @type rule :: { name, matcher } | { name, %{ :match => matcher, :capture => non_neg_integer, :format => formatter, :option => option, :ignore => boolean, :skip => boolean, :exclude => excluder | [excluder], :include => rule | [rule], :rules => rule | [rule] } }
    @type ast :: String.t | { name, [ast] } | { name, [ast], option }

    @doc """
      Parse the given input using the specified ruleset.

      Example
      -------
        iex> rules = [
        ...>     whitespace: %{ match: ~r/\\A\\s/, ignore: true },
        ...>     element_end: %{ match: ~r/\\A<\\/.*?>/, ignore: true },
        ...>     element: %{ match: fn
        ...>         input = <<"<", _ :: binary>> ->
        ...>             elements = String.splitter(input, "<", trim: true)
        ...>
        ...>             [first] = Enum.take(elements, 1)
        ...>             [{ 0, tag_length }] = Regex.run(~r/\\A.*?>/, first, return: :index)
        ...>             tag_length = tag_length + 1
        ...>
        ...>             { 0, length } = Stream.drop(elements, 1) |> Enum.reduce_while({ 1, 0 }, fn
        ...>                 element = <<"/", _ :: binary>>, { 1, length } ->
        ...>                     [{ 0, tag_length }] = Regex.run(~r/\\A.*?>/, element, return: :index)
        ...>                     { :halt, { 0, length + tag_length + 1 } }
        ...>                 element = <<"/", _ :: binary>>, { count, length } -> { :cont, { count - 1, length + String.length(element) + 1 } }
        ...>                 element, { count, length } -> { :cont, { count + 1, length + String.length(element) + 1 } }
        ...>             end)
        ...>
        ...>             length = length + String.length(first) + 1
        ...>             [{ 0, length }, {1, tag_length - 2}, { tag_length, length - tag_length }]
        ...>         _ -> nil
        ...>     end, exclude: nil, option: fn input, [_, { index, length }, _] -> String.slice(input, index, length) end },
        ...>     value: %{ match: ~r/\\A\\d+/, rules: [] }
        ...> ]
        iex> input = \"\"\"
        ...> <array>
        ...>     <integer>1</integer>
        ...>     <integer>2</integer>
        ...> </array>
        ...> <array>
        ...>     <integer>3</integer>
        ...>     <integer>4</integer>
        ...> </array>
        ...> \"\"\"
        iex> Parsey.parse(input, rules)
        [
            { :element, [
                { :element, [value: ["1"]], "integer" },
                { :element, [value: ["2"]], "integer" }
            ], "array" },
            { :element, [
                { :element, [value: ["3"]], "integer" },
                { :element, [value: ["4"]], "integer" }
            ], "array" },
        ]
    """
    @spec parse(String.t, [rule]) :: [ast]
    def parse(input, rules), do: parse(input, rules, [])

    @doc false
    @spec parse(String.t, [rule], [ast]) :: [ast]
    defp parse("", _, nodes), do: flatten(nodes)
    defp parse(input, rules, [string|nodes]) when is_binary(string) do
        case get_node(input, rules) do
            { next, node } -> parse(next, rules, [node, string|nodes])
            nil -> parse(String.slice(input, 1..-1), rules, [string <> String.first(input)|nodes])
        end
    end
    defp parse(input, rules, [nil|nodes]) do
        case get_node(input, rules) do
            { next, nil } -> parse(next, rules, [nil|nodes])
            { next, node } -> parse(next, rules, [node|nodes])
            nil -> parse(String.slice(input, 1..-1), rules, [String.first(input)|nodes])
        end
    end
    defp parse(input, rules, nodes) do
        case get_node(input, rules) do
            { next, nil } -> parse(next, rules, nodes)
            { next, node } -> parse(next, rules, [node|nodes])
            nil -> parse(String.slice(input, 1..-1), rules, [String.first(input)|nodes])
        end
    end

    @doc false
    @spec flatten([ast | nil], [ast]) :: [ast]
    defp flatten(nodes, list \\ [])
    defp flatten([], nodes), do: nodes
    defp flatten([nil|nodes], list), do: flatten(nodes, list)
    defp flatten([node|nodes], list) when is_list(node), do: flatten(nodes, node ++ list)
    defp flatten([node|nodes], list), do: flatten(nodes, [node|list])

    @doc false
    @spec get_node(String.t, [rule]) :: { String.t, ast | nil } | nil
    defp get_node(input, rules) do
        Enum.find_value(rules, fn
            rule = { _, regex = %Regex{} } -> make_node(input, rule, Regex.run(regex, input, return: :index), rules)
            rule = { _, %{ match: regex = %Regex{} } } -> make_node(input, rule, Regex.run(regex, input, return: :index), rules)
            rule = { _, %{ match: func } } -> make_node(input, rule, func.(input), rules)
            rule = { _, func } -> make_node(input, rule, func.(input), rules)
        end)
    end

    @doc false
    @spec make_node(String.t, rule, nil | [{ integer, integer }], [rule]) :: { String.t, ast } | nil
    defp make_node(_, _, nil, _), do: nil
    defp make_node(input, rule = { _, %{ capture: capture } }, indexes, rules), do: make_node(input, rule, indexes, Enum.at(indexes, capture), rules)
    defp make_node(input, rule, indexes, rules), do: make_node(input, rule, indexes, List.last(indexes), rules)

    @doc false
    @spec make_node(String.t, rule, [{ integer, integer }], { integer, integer }, [rule]) :: { String.t, ast }
    defp make_node(input, rule, indexes = [{ entire_index, entire_length }|_], { index, length }, rules) do
        match_total = entire_index + entire_length
        <<_ :: unit(8)-size(match_total), next :: binary>> = input
        { next, node(format(binary_part(input, index, length), rule), rule, remove_rules(rules, rule) |> include_rules(rule) |> replace_rules(rule), input, indexes) }
    end

    @doc false
    @spec node(String.t, rule, [rule], String.t, [{ integer, integer }]) :: ast | nil
    defp node(_, { _, %{ ignore: true } }, _, _, _), do: nil
    defp node(input, { _, %{ skip: true } }, rules, _, _), do: parse(input, rules)
    defp node(input, { name, %{ option: option } }, rules, original, indexes) when is_function(option), do: { name, parse(input, rules), option.(original, indexes) }
    defp node(input, { name, %{ option: option } }, rules, _, _), do: { name, parse(input, rules), option }
    defp node(input, { name, _ }, rules, _, _), do: { name, parse(input, rules) }

    @doc false
    @spec remove_rules([rule], rule) :: [rule]
    defp remove_rules(rules, { _, %{ exclude: { name, option } } }) do
        Enum.filter(rules, fn
            { rule, %{ option: rule_option } } ->
                rule != name or rule_option != option
            _ -> true
        end)
    end
    defp remove_rules(rules, { _, %{ exclude: name } }) when is_atom(name), do: Enum.filter(rules, fn { rule, _ } -> rule != name end)
    defp remove_rules(rules, { _, %{ exclude: names } }) do
        Enum.filter(rules, fn
            { rule, %{ option: rule_option } } -> !Enum.any?(names, fn
                { name, option } -> rule == name and rule_option == option
                name -> rule == name
            end)
            { rule, _ } -> !Enum.any?(names, fn
                { _name, _option } -> false
                name -> rule == name
            end)
        end)
    end
    defp remove_rules(rules, { name, _ }), do: Enum.filter(rules, fn { rule, _ } -> rule != name end)

    @doc false
    @spec include_rules([rule], rule) :: [rule]
    defp include_rules(rules, { _, %{ include: new_rules } }), do: new_rules ++ rules
    defp include_rules(rules, _), do: rules

    @doc false
    @spec replace_rules([rule], rule) :: [rule]
    defp replace_rules(_, { _, %{ rules: new_rules } }), do: new_rules
    defp replace_rules(rules, _), do: rules

    @doc false
    @spec format(String.t, rule) :: String.t
    defp format(_, { _, %{ format: string } }) when is_binary(string), do: string
    defp format(input, { _, %{ format: func } }), do: func.(input)
    defp format(input, _), do: input
end
