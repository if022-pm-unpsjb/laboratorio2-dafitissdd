defmodule Libremarket.Ventas do

  def productos() do
    for contador <- 1..10 do
      id = contador
      producto = "producto"<> Integer.to_string(contador)

      precio = :rand.uniform(1000)
      stockInicial = :rand.uniform(10)

      %{id: id, producto: producto, precio: precio, stock: stockInicial, reservado: 0}
    end

  end

  def vendedores() do
    for contador <- 1..5 do
      id = contador
      vendedor = "vendedor"<> Integer.to_string(contador)
      dni = :rand.uniform(50000000)
      %{id: id, vendedor: vendedor, dni: dni}
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
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def productos(pid \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :productos)
  end

  def vendedores(pid \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :vendedores)
  end

  def reservarProducto(pid \\ __MODULE__, id, cantidad) do
    GenServer.call({:global, __MODULE__}, {:reservar, id, cantidad})
  end

  def liberarProducto(pid \\ __MODULE__, id, cantidad) do
    GenServer.call({:global, __MODULE__}, {:liberar, id, cantidad})
  end

  def buscarVendedor(pid \\ __MODULE__, vendedor_id) do
    GenServer.call({:global, __MODULE__}, {:buscar_vendedor, vendedor_id})
  end

  def enviarProducto(pid \\ __MODULE__, id, cantidad) do
    GenServer.call({:global, __MODULE__}, {:enviar, id, cantidad})
  end



  # Callbacks

  @doc """
  Inicializa el estado del servidor
  """
  @impl true
  def init(state) do
    productos = Libremarket.Ventas.productos()
    vendedores = Libremarket.Ventas.vendedores()
    {:ok, %{productos: productos, vendedores: vendedores}}
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
  def handle_call(:vendedores, _from, state) do
    vendedores = Map.get(state, :vendedores)
    {:reply, vendedores, state}
  end

  @impl true
  def handle_call({:reservar, id, cantidad}, _from, state) do
    productos = state.productos

    # Buscar el producto por su id usando Enum.find
    producto = Enum.find(productos, fn p -> p.id == id end)

    # Verificamos si el producto existe
    if producto do
      # Verificamos si hay suficiente stock
      if producto.stock >= cantidad do
        # Actualizamos solo el producto seleccionado
        producto_actualizado =
          producto
          |> Map.update!(:stock, &(&1 - cantidad))    # Reducir el stock
          |> Map.update!(:reservado, &(&1 + cantidad)) # Aumentar la cantidad reservada

        # Actualizamos la lista de productos con el producto actualizado
        productos_actualizados = Enum.map(productos, fn p ->
          if p.id == id do
            producto_actualizado
          else
            p
          end
        end)

        # Devolvemos la lista actualizada y confirmamos la reserva exitosa
        {:reply, {:ok, producto_actualizado}, %{state | productos: productos_actualizados}}
      else
        # No hay suficiente stock
        {:reply, {:error, "No hay suficiente stock disponible"}, state}
      end
    else
      # Producto no encontrado
      {:reply, {:error, "Producto no encontrado"}, state}
    end
  end

    @impl true
  def handle_call({:liberar, id, cantidad}, _from, state) do
    productos = state.productos

    # Buscar el producto por su id usando Enum.find
    producto = Enum.find(productos, fn p -> p.id == id end)

    # Verificamos si el producto existe
    if producto do
      # Verificamos si hay suficiente stock reservado
      if producto.reservado >= cantidad do
        # Actualizamos solo el producto seleccionado
        producto_actualizado =
          producto
          |> Map.update!(:stock, &(&1 + cantidad))
          |> Map.update!(:reservado, &(&1 - cantidad))

        # Actualizamos la lista de productos con el producto actualizado
        productos_actualizados = Enum.map(productos, fn p ->
          if p.id == id do
            producto_actualizado
          else
            p
          end
        end)

        # Devolvemos la lista actualizada y confirmamos la reserva exitosa
        {:reply, {:ok, producto_actualizado}, %{state | productos: productos_actualizados}}
      else
        # No hay suficiente stock
        {:reply, {:error, "No hay suficiente reservado disponible"}, state}
      end
    else
      # Producto no encontrado
      {:reply, {:error, "Producto no encontrado"}, state}
    end
  end

  @impl true
  def handle_call({:buscar_vendedor, vendedor_id}, _from, state) do
    vendedores = Map.get(state, :vendedores)

    # Buscar el vendedor por su id
    case Enum.find(vendedores, fn vendedor -> vendedor.id == vendedor_id end) do
      nil -> {:reply, {:error, :vendedor_no_encontrado}, state}
      vendedor -> {:reply, {:ok, vendedor}, state}
    end
  end

  @impl true
  def handle_call({:enviar, id, cantidad}, _from, state) do
    productos = state.productos

    # Buscar el producto por su id usando Enum.find
    producto = Enum.find(productos, fn p -> p.id == id end)

    if producto do
      producto_actualizado =
          producto
          |> Map.update!(:reservado, &(&1 - cantidad))

      # Actualizamos la lista de productos con el producto actualizado
      productos_actualizados = Enum.map(productos, fn p ->
        if p.id == id do
          producto_actualizado
        else
          p
        end
      end)

      {:reply, {:ok, producto_actualizado}, %{state | productos: productos_actualizados}}

      else
        # Producto no encontrado
        {:reply, {:error, "Producto no encontrado"}, state}
    end
  end

end
