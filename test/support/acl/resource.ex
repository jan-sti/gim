defmodule GimTest.Acl.Resource do
  @moduledoc false
  use Gim.Schema

  alias GimTest.Acl.Access

  schema do
    property(:name, index: :unique)
    has_edges(:accesses, Access, reflect: :resource)
  end
end
