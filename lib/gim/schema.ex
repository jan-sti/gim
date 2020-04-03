defmodule Gim.Schema do
  @moduledoc """
  Defines a schema.

  ## Example
      defmodule User do
        use Gim.Schema
        schema do
          property :name, index: :unique
          property :age, default: 0, index: true
          has_edges :author_of, Post, reflect: :authored_by
        end
      end

  ## Reflection

  Any schema module will generate the `__schema__` function that can be
  used for runtime introspection of the schema:

  * `__schema__(:primary_key)` - Returns the primary unique indexed property name or nil;

  * `__schema__(:properties)` - Returns a list of all property names;

  * `__schema__(:indexes)` - Returns a list of all indexed property names;

  * `__schema__(:index, property)` - Returns how the given property is indexed;

  * `__schema__(:indexes_unique)` - Returns a list of all unique indexed property names;

  * `__schema__(:indexes_non_unique)` - Returns a list of all non-unique indexed property names;

  * `__schema__(:associations)` - Returns a list of all association names;

  * `__schema__(:association, assoc)` - Returns the association reflection of the given assoc;

  * `__schema__(:type, assoc)` - Returns the type of the given association;

  Furthermore, `__struct__` functions are
  defined so structs functionalities are available.

  """

  @doc false
  defmacro __using__(_) do
    # apply(__MODULE__, which, [])
    quote do
      import Gim.Schema, only: [schema: 1]

      Module.register_attribute(__MODULE__, :gim_props, accumulate: true)
      Module.register_attribute(__MODULE__, :gim_assocs, accumulate: true)
    end
  end

  @doc """
  Defines a schema struct with a source name and property definitions.
  """
  defmacro schema([do: block]) do
    prelude =
      quote do
        Module.register_attribute(__MODULE__, :struct_fields, accumulate: true)

        Gim.Schema.__meta__(__MODULE__, :__id__, nil)
        Gim.Schema.__meta__(__MODULE__, :__repo__, nil)

        import Gim.Schema
        unquote(block)
      end

    postlude =
      quote unquote: false do
        defstruct @struct_fields

        props = @gim_props |> Enum.reverse
        assocs = @gim_assocs |> Enum.reverse

        def __schema__(:gim), do: true

        def __schema__(:properties), do: unquote(Enum.map(props, &elem(&1, 0)))

        def __schema__(:indexes), do: unquote(props |> Enum.filter(&elem(&1, 1)) |> Enum.map(&elem(&1, 0)))

        for {prop, index} <- @gim_props do
          def __schema__(:index, unquote(prop)), do: unquote(index)
        end
        def __schema__(:index, _), do: nil

        def __schema__(:indexes_unique), do: unquote(props |> Enum.filter(&elem(&1, 1) in [:unique, :primary]) |> Enum.map(&elem(&1, 0)))

        def __schema__(:indexes_non_unique), do: unquote(props |> Enum.filter(&elem(&1, 1) == true) |> Enum.map(&elem(&1, 0)))

        def __schema__(:associations), do: unquote(Enum.map(assocs, &elem(&1, 0)))

        for {name, _type, reflect} <- @gim_assocs do
          def __schema__(:association, unquote(name)), do: unquote(reflect)
        end
        def __schema__(:association, _), do: nil

        for {name, type, _reflect} <- @gim_assocs do
          def __schema__(:type, unquote(name)), do: unquote(type)
        end
        def __schema__(:type, _), do: nil
    end

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end


  ## API

  @doc """
  Defines a property with given name on the node type schema.

  The property is not typed, you can store any valid term.

  ## Example
      schema do
        property :uuid, index: :primary
        property :fullname, index: :unique
        property :birthday, index: true
        property :hobbies
      end

  ## Options

    * `:default` - Sets the default value on the schema and the struct.
      The default value is calculated at compilation time, so don't use
      expressions like `DateTime.utc_now` or `Ecto.UUID.generate` as
      they would then be the same for all nodes.

    * `:index` - When `true`, the property is indexed for lookups.
      When `:unique`, the property uniquely indexed, which is enforced.
      When `:primary`, the property is uniquely indexed and used as
      primary key.

  """
  defmacro property(name, opts \\ []) do
    quote do
      Gim.Schema.__property__(__MODULE__, unquote(name), unquote(opts))
    end
  end

  @doc """
  Defines a named (i.e. implicitly labeled) edge to a given type on the schema.

  You can store multiple edges with this name.

  ## Example
      schema do
        has_edges :categories, Category, reflect: :publications
      end

  ## Options

    * `:reflect` - Sets the edge name on the target type to automatically
      add a reflected edge on the target node.

  """
  defmacro has_edges(name, type, opts \\ []) do
    #type = expand_alias(type, __CALLER__)
    reflect = Keyword.get(opts, :reflect)
    quote do
      Gim.Schema.__has_edges__(__MODULE__, unquote(name), unquote(type), unquote(reflect), unquote(opts))

      def unquote(name)(nodes) when is_list(nodes) do
        Enum.map(nodes, fn %{:__repo__ => repo, unquote(name) => edges} ->
          repo.fetch!(unquote(type), edges)
        end)
        |> Enum.uniq()
      end

      def unquote(name)(%{:__repo__ => repo, unquote(name) => edges} = _node) do
        repo.fetch!(unquote(type), edges)
      end

      def unquote(:"add_#{name}")(struct, nodes) when is_list(nodes) do
        ids = Enum.map(nodes, fn %{__id__: id} -> id end)
        Map.update!(struct, unquote(name), fn x -> ids ++ x end)
      end
      def unquote(:"add_#{name}")(struct, %{__id__: id} = _node) do
        Map.update!(struct, unquote(name), fn x -> [id | x] end)
      end

      def unquote(:"delete_#{name}")(struct, nodes) when is_list(nodes) do
        Map.update!(struct, unquote(name), fn edges -> Enum.reject(edges, &Enum.member?(nodes, &1)) end)
      end
      def unquote(:"delete_#{name}")(struct, %{__id__: id} = _node) do
        Map.update!(struct, unquote(name), &List.delete(&1, id))
      end

      def unquote(:"set_#{name}")(struct, nodes) when is_list(nodes) do
        ids = Enum.map(nodes, fn %{__id__: id} -> id end)
        Map.put(struct, unquote(name), ids)
      end
      def unquote(:"set_#{name}")(struct, %{__id__: id} = _node) do
        Map.put(struct, unquote(name), [id])
      end

      def unquote(:"clear_#{name}")(struct) do
        Map.put(struct, unquote(name), [])
      end
    end
  end

  @doc """
  Defines a named (i.e. implicitly labeled) edge to a given type on the schema.

  You can have zero or one edge with this name.

  ## Example
      schema do
        has_edge :authored_by, Person, reflect: :author_of
      end

  ## Options

    * `:reflect` - Sets the edge name on the target type to automatically
      add a reflected edge on the target node.

  """
  defmacro has_edge(name, type, opts \\ []) do
    #type = expand_alias(type, __CALLER__)
    reflect = Keyword.get(opts, :reflect)
    quote do
      Gim.Schema.__has_edge__(__MODULE__, unquote(name), unquote(type), unquote(reflect), unquote(opts))

      def unquote(name)(nodes) when is_list(nodes) do
        Enum.map(nodes, fn %{:__repo__ => repo, unquote(name) => edge} ->
          repo.fetch!(unquote(type), edge)
        end)
        |> Enum.uniq()
      end

      def unquote(name)(%{:__repo__ => repo, unquote(name) => edge} = _node) do
        repo.fetch!(unquote(type), edge)
      end

      def unquote(:"set_#{name}")(struct, %{__id__: id} = _node) do
        Map.put(struct, unquote(name), id)
      end

      def unquote(:"clear_#{name}")(struct) do
        Map.put(struct, unquote(name), nil)
      end
    end
  end

  @valid_property_options [:default, :index]

  @doc false
  def __property__(mod, name, opts) do
    check_options!(opts, @valid_property_options, "property/2")
    put_struct_property(mod, name, Keyword.get(opts, :default))
    index = case Keyword.get(opts, :index) do
      :primary -> :primary
      :unique -> :unique
      truthy -> !!truthy
    end
    Module.put_attribute(mod, :gim_props, {name, index})
  end

  @doc false
  def __meta__(mod, name, default) do
    put_struct_property(mod, name, default)
  end

  @valid_has_options [:reflect]

  @doc false
  def __has_edges__(mod, name, type, reflect, opts) do
    check_type!(type, "has_edges/3")
    check_options!(opts, @valid_has_options, "has_edges/3")
    put_struct_property(mod, name, Keyword.get(opts, :default, []))
    Module.put_attribute(mod, :gim_assocs, {name, type, reflect})
  end

  @doc false
  def __has_edge__(mod, name, type, reflect, opts) do
    check_type!(type, "has_edge/3")
    check_options!(opts, @valid_has_options, "has_edge/3")
    put_struct_property(mod, name, Keyword.get(opts, :default))
    Module.put_attribute(mod, :gim_assocs, {name, type, reflect})
  end

  ## Private

  defp put_struct_property(mod, name, assoc) do
    props = Module.get_attribute(mod, :struct_fields)

    if List.keyfind(props, name, 0) do
      raise ArgumentError, "property/association #{inspect name} is already set on schema"
    end

    Module.put_attribute(mod, :struct_fields, {name, assoc})
  end

  defp check_type!(type, fun_arity) do
    # Can't use function_exported?(type, :__info__, 1)
    # Can't use Module.defines?(type, {:__schema__, 1})
    # Just catch the worst typos
    unless type |> to_string() |> String.starts_with?("Elixir.") do
      raise ArgumentError, "invalid type #{inspect type} for #{fun_arity}"
    end
  end

  defp check_options!(opts, valid, fun_arity) do
    case Enum.find(opts, fn {k, _} -> not(k in valid) end) do
      {k, _} -> raise ArgumentError, "invalid option #{inspect k} for #{fun_arity}"
      nil -> :ok
    end
  end

#  defp expand_alias({:__aliases__, _, _} = ast, env),
#    do: Macro.expand(ast, %{env | function: {:__schema__, 2}})
#  defp expand_alias(ast, _env),
#    do: ast
end