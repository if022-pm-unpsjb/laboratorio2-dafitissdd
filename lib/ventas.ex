defmodule Libremarket.Ventas do
  @tabla :ventas
  def productos() do
    for contador <- 1..10 do
      id = contador
      producto = "producto" <> Integer.to_string(contador)

      precio = :rand.uniform(1000)
      stockInicial = :rand.uniform(10)

      %{id: id, producto: producto, precio: precio, stock: stockInicial, reservado: 0}
    end
  end
  def vendedores() do
    for contador <- 1..5 do
      id = contador
      vendedor = "vendedor" <> Integer.to_string(contador)
      dni = :rand.uniform(50_000_000)
      %{id: id, vendedor: vendedor, dni: dni}
    end
  end

  def guardarEstado(state) do
    :dets.insert(@tabla, {:ventas, state})
  end
end

defmodule Libremarket.Ventas.Message do
  use GenServer
  use AMQP

  @queue "ventas"

  # Public API para iniciar el proceso
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    {:ok, conn} =
      Connection.open(
        "amqps://sjyxztwd:nQ28DYT15fVo8thS6lxtyHvI6ZUw7GcK@cougar.rmq.cloudamqp.com/sjyxztwd",
        ssl_options: [verify: :verify_none]
      )

    {:ok, chan} = Channel.open(conn)

    Queue.declare(chan, @queue, auto_delete: true)
    Basic.consume(chan, @queue, nil, no_ack: true)

    {:ok, %{conn: conn, chan: chan}}
  end

  def mandar_actualizacion(compra_id, producto_id, message) do
    GenServer.cast(__MODULE__, {:mandar_actualizacion, compra_id, producto_id, message})
  end

  @impl true
  def handle_cast({:mandar_actualizacion, compra_id, producto_id, message}, state) do
    IO.puts("Enviando actualización: #{inspect(message)}")
    payload = :erlang.term_to_binary(%{result: message, compra_id: compra_id, producto_id: producto_id, accion: "reservar"})
    IO.puts("Enviando payload: #{inspect(payload)}")

    Basic.publish(state.chan, "", "compras", payload)
    {:noreply, state}
  end

  # Maneja el mensaje básico de confirmación de consumo
  @impl true
  def handle_info({:basic_consume_ok, _consumer_info}, chan) do
    {:noreply, chan}
  end

  @impl true
  def handle_info({:basic_deliver, payload, _meta}, state) do
    message = :erlang.binary_to_term(payload)
    IO.puts("Mensaje recibido: #{inspect(message)}")

    case message[:action] do
      "reservar" ->
        IO.puts("Recibiendo mensaje de compras #{message[:producto_id]}")
        Libremarket.Ventas.Server.reservarProducto(message[:compra_id], message[:producto_id], message[:cantidad])

      _ ->
        IO.puts("Acción desconocida: #{inspect(message)}")
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{conn: conn, chan: chan}) do
    Channel.close(chan)
    Connection.close(conn)
    :ok
  end
end

defmodule Libremarket.Ventas.Server do
  @moduledoc """
  Ventas
  """

  use GenServer
  @tabla :ventas
  @intervalo 60_000
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

  def reservarProducto(pid \\ __MODULE__, producto_id, cantidad) do
    GenServer.cast({:global, __MODULE__}, {:reservar, producto_id, cantidad})
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

  def obtener_estado(pid \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :obtener_estado)
  end

  def guardar_estado(pid \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :guardar_estado)
  end

  # Callbacks

  @doc """
  Inicializa el estado del servidor
  """
  @impl true
  def init(state) do
    case :dets.open_file(@tabla, type: :set, file: ~c"ventas.dets") do
      {:ok, _} ->
        state =
          case :dets.lookup(@tabla, :ventas) do
            [] ->     productos = Libremarket.Ventas.productos()
                      vendedores = Libremarket.Ventas.vendedores()
                      %{productos: productos, vendedores: vendedores}
            [{_key, value}] -> value
          end

          :timer.send_interval(@intervalo, self(), :guardar_estado)
          {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
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
  def handle_cast({:reservar, compra_id, producto_id, cantidad}, state) do
    productos = state.productos

    # Buscar el producto por su id usando Enum.find
    producto = Enum.find(productos, fn p -> p.id == producto_id end)

    # Verificamos si el producto existe
    if producto do
      # Verificamos si hay suficiente stock
      if producto.stock >= cantidad do
        # Actualizamos solo el producto seleccionado
        producto_actualizado =
          producto
          # Reducir el stock
          |> Map.update!(:stock, &(&1 - cantidad))
          # Aumentar la cantidad reservada
          |> Map.update!(:reservado, &(&1 + cantidad))

        # Actualizamos la lista de productos con el producto actualizado
        productos_actualizados =
          Enum.map(productos, fn p ->
            if p.id == producto_id do
              producto_actualizado
            else
              p
            end
          end)
          Libremarket.Ventas.Message.mandar_actualizacion(compra_id, producto_id, true)
        # Devolvemos la lista actualizada y confirmamos la reserva exitosa
        {:noreply, productos_actualizados}
      end
    else
      # Producto no encontrado o no hay stock
        Libremarket.Ventas.Message.mandar_actualizacion(compra_id, producto_id, false)
        {:noreply, state}
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
        productos_actualizados =
          Enum.map(productos, fn p ->
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
      productos_actualizados =
        Enum.map(productos, fn p ->
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

  @impl true
  def handle_info(:guardar_estado, state) do
    Libremarket.Ventas.guardarEstado(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:obtener_estado, _from, state) do
    {:reply, state, state}
  end

end
