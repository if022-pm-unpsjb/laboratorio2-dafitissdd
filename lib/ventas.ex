defmodule Libremarket.Ventas do

  def productos() do
    for contador <- 1..10 do
      id = contador
      producto = "producto"<> Integer.to_string(contador)

      precio = :rand.uniform(1000)
      vendedor = :rand.uniform(2)
      stockInicial = :rand.uniform(10)

      %{id: id, producto: producto, precio: precio, vendedor: vendedor, stock: stockInicial, reservado: 0}
    end

  end

end

defmodule Libremarket.Ventas.Server do
  @moduledoc """
  Ventas
  """

  use GenServer

  # API del cliente

  @doc """
  Crea un nuevo servidor de Ventas
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def productos(pid \\ __MODULE__) do
    GenServer.call(pid, :productos)
  end

  def reservarProducto(pid \\ __MODULE__, id, cantidad) do
    GenServer.call(pid, {:reservar, id, cantidad})
  end


  # Callbacks

  @doc """
  Inicializa el estado del servidor
  """
  @impl true
  def init(state) do
    productos = Libremarket.Ventas.productos()
    {:ok, %{productos: productos}}
  end

  @doc """
  Callback para un call :ventas
  """
  @impl true
  def handle_call(:productos, _from, state) do
    productos = Map.get(state, :productos)
    {:reply, productos, state}
  end

  @impl true
  def handle_call({:reservar,id, cantidad}, _from, state) do
    productos = Map.get(state, :productos)
    #buscar el productor por id, cambiar la reserva por la cantidad, restar el stock por la cantidad
    #fijarse que la cantidad no sea mayor al stock
    {:reply, productos, state}
  end

end
