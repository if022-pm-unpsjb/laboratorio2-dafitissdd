defmodule Libremarket.Ventas do
  @tabla :ventas
  def productos() do
    for contador <- 1..10 do
      id = contador
      producto = "producto" <> Integer.to_string(contador)

      precio = :rand.uniform(1000)
      stockInicial = :rand.uniform(30)

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

  def actualizar_infraccion(_ \\ __MODULE__, resultado, compra_id) do
    GenServer.call({:global, __MODULE__}, {:actualizar_infraccion, resultado, compra_id}, 15_000)
  end

  def actualizar_autorizacion(_ \\ __MODULE__, resultado, compra_id) do
    GenServer.call(
      {:global, __MODULE__},
      {:actualizar_autorizacion, resultado, compra_id},
      15_000
    )
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
    IO.puts("Ventas: {Enviando actualización: #{inspect(message)}}")

    payload =
      :erlang.term_to_binary(%{
        result: message,
        compra_id: compra_id,
        producto_id: producto_id,
        accion: "reservar"
      })

    Basic.publish(state.chan, "", "compras", payload)
    {:noreply, state}
  end

  # Maneja el mensaje básico de confirmación de consumo
  @impl true
  def handle_info({:basic_consume_ok, _consumer_info}, chan) do
    {:noreply, chan}
  end

  def handle_info({:basic_deliver, payload, _meta}, state) do
    message = :erlang.binary_to_term(payload)

    case message[:accion] do
      "reservar_producto" ->
        IO.puts("Ventas: {Recibiendo mensaje de Compras -reservar_producto:  #{message[:compra_id]}}")
        Libremarket.Ventas.Server.reservarProducto(message[:compra_id], message[:producto_id], message[:cantidad])

      "detectar" ->
        IO.puts(
          "Ventas: {Recibiendo mensaje de Infracciones -actualizar_infraccion: #{message[:compra_id]}}"
        )
        Libremarket.Ventas.Server.actualizar_infraccion(message[:result], message[:compra_id])

      "autorizar" ->
        IO.puts(
          "Ventas: {Recibiendo mensaje de Pagos -actualizar_autorizacion: #{message[:compra_id]}}"
        )

        Libremarket.Ventas.Server.actualizar_autorizacion(message[:result], message[:compra_id])

      _ ->
        IO.puts("Ventas: acción desconocida: #{inspect(message)}")
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

  def reservarProducto(pid \\ __MODULE__, compra_id, producto_id, cantidad) do
    GenServer.cast({:global, __MODULE__}, {:reservar, compra_id, producto_id, cantidad})
  end

  def liberarProducto(pid \\ __MODULE__, comrpa_id, producto_id, cantidad) do
    GenServer.cast({:global, __MODULE__}, {:liberar, comrpa_id, producto_id, cantidad})
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

  def actualizar_autorizacion(_ \\ __MODULE__, resultado, compra_id) do
    GenServer.call(
      {:global, __MODULE__},
      {:actualizar_autorizacion, resultado, compra_id},
      15_000
    )
  end

  def actualizar_infraccion(_ \\ __MODULE__, resultado, compra_id) do
    GenServer.call({:global, __MODULE__}, {:actualizar_infraccion, resultado, compra_id}, 15_000)
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
            [] ->
              productos = Libremarket.Ventas.productos()
              vendedores = Libremarket.Ventas.vendedores()
              %{productos: productos, vendedores: vendedores, compras: %{}}

            [{_key, value}] ->
              value
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
    compras = Map.get(state, :compras, %{})
    nueva_compra =
      compras
      |> Map.get(compra_id, %{})
      |> Map.put(:producto_id, producto_id)
      |> Map.put(:cantidad, cantidad)
      |> Map.put(:infraccion, "proceso")
      |> Map.put(:pago_autorizado, "proceso")

    nuevas_compras = Map.put(compras, compra_id, nueva_compra)

    # Buscar el producto por su id
    producto = Enum.find(productos, fn p -> p.id == producto_id end)

    # Si el producto existe y tiene stock suficiente
    if producto && producto.stock >= cantidad do
      # Actualizamos el producto: reducimos el stock y aumentamos la cantidad reservada
      producto_actualizado =
        producto
        |> Map.update!(:stock, &(&1 - cantidad))
        |> Map.update!(:reservado, &(&1 + cantidad))

      # Actualizamos la lista de productos
      productos_actualizados =
        Enum.map(productos, fn p ->
          if p.id == producto_id do
            producto_actualizado
          else
            p
          end
        end)

      # Mandamos la actualización y retornamos el nuevo estado
      Libremarket.Ventas.Message.mandar_actualizacion(compra_id, producto_id, true)
      {:noreply, %{state | productos: productos_actualizados, compras: nuevas_compras}}
    else
      # Si no hay stock o no se encuentra el producto, mandamos la actualización de fallo
      Libremarket.Ventas.Message.mandar_actualizacion(compra_id, producto_id, false)
      # No se actualiza el estado
        {:noreply, %{state | compras: nuevas_compras}}
    end
  end

  @impl true
  def handle_call({:actualizar_infraccion, result, compra_id}, _from, state) do
    compras = Map.get(state, :compras, %{})
    compra = Map.get(compras, compra_id, %{})
    new_compra_state = Map.put(compra, "infraccion", result)
    new_state = Map.put(state, :compras, Map.put(compras, compra_id, new_compra_state))

    {:reply, {:ok, new_compra_state},  new_state}
  end

  @impl true
  def handle_call({:actualizar_autorizacion, result, compra_id}, _from, state) do
    compras = Map.get(state, :compras, %{})
    compra = Map.get(compras, compra_id, %{})
    new_compra_state = Map.put(compra, "pago_autorizado", result)
    new_state = Map.put(state, :compras, Map.put(compras, compra_id, new_compra_state))

    {:reply, {:ok, new_compra_state},  new_state}
  end

  @impl true
  def handle_info({:liberar, compra_id, producto_id, cantidad}, state) do
    # Llama directamente a `handle_cast` para reutilizar la lógica
    handle_cast({:liberar, compra_id, producto_id, cantidad}, state)
  end

  @impl true
  def handle_cast({:liberar, compra_id, producto_id, cantidad}, _from, state) do
    compras = Map.get(state, :compras, %{})
    compra = Map.get(compras, compra_id, %{})
    infraccion = Map.get(compra, "infraccion", "unknown")
    autorizada = Map.get(compra, "pago_autorizado", "unknown")

    cond do
      compra == %{} ->
        {:noreply, state}

        infraccion == "proceso" || autorizada == "proceso" ->
        # Reintentar después de 6000 ms (6 segundos)
        Process.send_after(self(), {:liberar, compra_id, producto_id, cantidad}, 6000)
        {:noreply, state}

      infraccion == "infraccion" || autorizada == false ->
        productos = state.productos

        # Buscar el producto por su id
        case Enum.find(productos, fn p -> p.id == producto_id end) do
          nil ->
            {:reply, {:error, "Producto no encontrado"}, state}

          producto ->
            if producto.reservado >= cantidad do
              # Actualizar el producto y la lista de productos
              producto_actualizado =
                producto
                |> Map.update!(:stock, &(&1 + cantidad))
                |> Map.update!(:reservado, &(&1 - cantidad))

              productos_actualizados =
                Enum.map(productos, fn p ->
                  if p.id == producto_id, do: producto_actualizado, else: p
                end)

              {:noreply, %{state | productos: productos_actualizados}}
            else
              {:noreply, state}
            end
        end

      true ->
        {:noreply, state}
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
