defmodule Libremarket.Compras do
  @tabla :compras

  def comprar(compra_id, vendedor_id) do
    map =
          %{
            "vendedor" => vendedor_id,
            "infraccion" => nil,
            "reservado" => nil,
            "producto" => nil,
            "cantidad" => nil,
            "reservado" => nil,
            "confirmada" => nil,
            "envio" => nil,
            "pago" => nil,
          }
    map
  end

  def seleccionarProducto(compra_id, producto_id, cantidad) do
    resultado = Libremarket.Ventas.Server.reservarProducto(compra_id, producto_id, cantidad)

  end

  def seleccionarEnvio(tipoEnvio) do
    valor = :rand.uniform(100)
    costo = 0

    if valor < 80 do
      costo = Libremarket.Envios.calcularCosto()
    end

    %{"envio" => tipoEnvio, "costoEnvio" => costo}
  end

  def guardarEstado(state) do
    :dets.insert(@tabla, {:compras, state})
  end

  @spec siguiente_id(map()) :: number()
  def siguiente_id(state) do
    case Map.keys(state) do
      # Si no hay compras previas, empieza en 1
      [] -> 1
      # Incrementa el id más alto en 1
      keys -> Enum.max(keys) + 1
    end
  end

  def informarRechazo(compra_id) do
    IO.puts("Pago rechazado para la compra #{compra_id}")
  end

  def informarInfraccion(compra_id) do
    IO.puts("Infracción detectada para la compra #{compra_id}")
  end
end

defmodule Libremarket.Compras.Message do
  use GenServer
  use AMQP

  @queue "compras"

  # Public API para iniciar el proceso
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def detectar_infraccion(id_compras) do
    GenServer.cast(__MODULE__, {:detectar_infraccion, id_compras})
  end

  def reservar_producto(id_compras, id_producto, cantidad) do
    GenServer.cast(__MODULE__, {:reservar_producto, id_compras, id_producto, cantidad})
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

  @impl true
  def handle_cast({:detectar_infraccion, compra_id}, state) do
    payload = :erlang.term_to_binary(%{action: "detectar_infraccion", compra_id: compra_id})
    Basic.publish(state.chan, "", "infracciones", payload)
    IO.inspect(payload, label: "Mensaje publicado")
    {:noreply, state}
  end

  def handle_cast({:reservar_producto, compra_id, producto_id, cantidad}, state) do
    payload = :erlang.term_to_binary(%{action: "reservar_producto", compra_id: compra_id, producto_id: producto_id, cantidad: cantidad})
    Basic.publish(state.chan, "", "ventas", payload)
    IO.inspect(payload, label: "Mensaje publicado")
    {:noreply, state}
  end

  # Maneja el mensaje básico de confirmación de consumo
  @impl true
  def handle_info({:basic_consume_ok, _consumer_info}, chan) do
    {:noreply, chan}
  end

  # Handler para mensajes recibidos
  @impl true
  def handle_info({:basic_deliver, payload, _meta}, state) do
    message = :erlang.binary_to_term(payload)

    case message[:accion] do
      "detectar" ->
        IO.puts("Enviando mensaje a infracciones para compra #{message[:compra_id]}")
        Libremarket.Compras.Server.actualizar_infraccion(message[:result], message[:compra_id])

      "reservar" ->
        IO.puts("Recibiendo mensaje de ventar para compra #{message[:compra_id]}")
        Libremarket.Compras.Server.actualizar_reserva(message[:result], message[:compra_id], message[:producto_id])

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

defmodule Libremarket.Compras.Server do
  @moduledoc """
  Compras
  """

  use GenServer
  @tabla :compras
  @intervalo 60_000
  # API del cliente

  @doc """
  Crea un nuevo servidor de Compras
  """
  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def comprar(_ \\ __MODULE__, vendedor) do
    GenServer.call({:global, __MODULE__}, {:comprar, vendedor}, 15_000)
  end

  def seleccionarProducto(_ \\ __MODULE__, compra_id, producto_id, cantidad) do
    GenServer.call(
      {:global, __MODULE__},
      {:selecc_producto, compra_id, producto_id, cantidad},
      15_000
    )
  end

  def seleccionarEnvio(_ \\ __MODULE__, compra_id, tipoEnvio) do
    GenServer.call({:global, __MODULE__}, {:selecc_envio, compra_id, tipoEnvio}, 15_000)
  end

  def seleccionarPago(_ \\ __MODULE__, compra_id, tipoPago) do
    GenServer.call({:global, __MODULE__}, {:selecc_pago, compra_id, tipoPago}, 15_000)
  end

  def obtener_estado(_ \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :obtener_estado)
  end

  def confirmar_compra(_ \\ __MODULE__, compra_id) do
    GenServer.call({:global, __MODULE__}, {:confirmar_compra, compra_id})
  end

  def registrar_envio(_ \\ __MODULE__, compra_id, producto_id, cantidad) do
    GenServer.call({:global, __MODULE__}, {:registrar_envio, compra_id, producto_id, cantidad})
  end

  def guardar_estado(_ \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :guardar_estado)
  end

  def actualizar_infraccion(_ \\ __MODULE__, resultado, compra_id) do
    GenServer.call({:global, __MODULE__}, {:actualizar_infraccion, resultado, compra_id}, 15_000)
  end

  def actualizar_reserva(_ \\ __MODULE__, resultado, compra_id, producto_id) do
    GenServer.call({:global, __MODULE__}, {:actualizar_reserva, resultado, compra_id, producto_id}, 15_000)
  end


  # Callbacks

  @doc """
  Inicializa el estado del servidor
  """
  @impl true
  def init(_opts) do
    case :dets.open_file(@tabla, type: :set, file: ~c"compras.dets") do
      {:ok, _} ->
        state =
          case :dets.lookup(@tabla, :compras) do
            [] -> %{}
            [{_key, value}] -> value
          end

        :timer.send_interval(@intervalo, self(), :guardar_estado)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc """
  Callback para un call :comprar
  """
  @impl true
  def handle_call({:comprar, vendedor}, _from, state) do
    compra_id = Libremarket.Compras.siguiente_id(state)
    result = Libremarket.Compras.comprar(compra_id, vendedor)
    new_state = Map.put(state, compra_id, result)
    {:reply, compra_id, new_state}
  end

  @impl true
  def handle_call({:selecc_producto, compra_id, producto_id, cantidad}, _from, state) do
    Libremarket.Compras.Message.detectar_infraccion(compra_id)
    Libremarket.Compras.Message.reservar_producto(compra_id, producto_id, cantidad)
    #Libremarket.Compras.Message.seleccionar_pago(compra_id)
    IO.inspect({:procesando, compra_id, producto_id, cantidad}, label: "Seleccionando producto")
  end

  @impl true
  def handle_call({:selecc_envio, compra_id, tipoEnvio}, _from, state) do
    result = Libremarket.Compras.seleccionarEnvio(tipoEnvio)
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.merge(compra_state, result)
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:selecc_pago, compra_id, tipoPago}, _from, state) do
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.merge(compra_state, %{"pago" => tipoPago})
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, %{"pago" => tipoPago}, new_state}
  end

  @impl true
  def handle_call(:obtener_estado, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:guardar_estado, state) do
    Libremarket.Compras.guardarEstado(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:confirmar_compra, compra_id}, _from, state) do
    compra_state = Map.get(state, compra_id, %{})
    # Asegúrate de que la compra existe y maneja el caso donde no existe
    if compra_state == %{} do
      {:reply, {:error, "Compra no encontrada"}, state}
    else
      infraccion = Map.get(compra_state, "infraccion", "unknown")
      reservado = Map.get(compra_state, "reservado", "unknown")
      envio = Map.get(compra_state, "envio", "unknown")
      cantidad = Map.get(compra_state, "cantidad", "unknown")

      result =
        if infraccion == "ok" && reservado == true do
          autorizada = Map.get(Libremarket.Pagos.Server.autorizarPago(compra_id), "autorizada")

          if autorizada == true do
            if envio == "correo" do
              producto = Map.get(compra_state, "producto", "unknown")
              producto_id = producto[:id]
              Libremarket.Envios.Server.agendarEnvio(compra_id, producto_id, cantidad)
            end

            # Libremarket.Compras.Message.mandar_mensaje("Compra confirmada: #{compra_id}")
          else
            Libremarket.Ventas.Server.liberarProducto(compra_id, cantidad)
            Libremarket.Compras.informarRechazo(compra_id)
          end

          %{"confirmada" => true, "autorizada" => autorizada}
        else
          Libremarket.Ventas.Server.liberarProducto(compra_id, cantidad)
          Libremarket.Compras.informarInfraccion(compra_id)
          %{"confirmada" => false}
        end

      new_compra_state = Map.merge(compra_state, result)
      new_state = Map.put(state, compra_id, new_compra_state)

      {:reply, new_compra_state, new_state}
    end
  end

  @impl true
  def handle_call({:actualizar_infraccion, resultado, compra_id}, _from, state) do
    IO.puts(
      "Actualizando infracción para compra #{compra_id} con resultado: #{inspect(resultado)}"
    )

    compra_state = Map.get(state, compra_id, %{})

    if compra_state == %{} do
      {:reply, {:error, "Compra no encontrada"}, state}
    else
      # Actualizamos el valor de "infraccion" en compra_state con el resultado
      new_compra_state = Map.put(compra_state, "infraccion", resultado)

      # Actualizamos el estado general con el nuevo estado de la compra
      new_state = Map.put(state, compra_id, new_compra_state)

      {:reply, {:ok, new_compra_state}, new_state}
    end
  end

  @impl true
  def handle_call({:actualizar_reserva, resultado, compra_id}, _from, state) do
    IO.puts(
      "Actualizando reserva para compra #{compra_id} con resultado: #{inspect(resultado)}"
    )

    compra_state = Map.get(state, compra_id, %{})

    if compra_state == %{} do
      {:reply, {:error, "Compra no encontrada"}, state}
    else
      # Actualizamos el valor de "reservado" en compra_state con el resultado
      new_compra_state = Map.put(compra_state, "reservado", resultado)

      # Actualizamos el estado general con el nuevo estado de la compra
      new_state = Map.put(state, compra_id, new_compra_state)

      {:reply, {:ok, new_compra_state}, new_state}
    end
  end

  @impl true
  def handle_call({:actualizar_reserva, resultado, compra_id, producto_id}, _from, state) do
    IO.puts(
      "Actualizando reserva para compra #{compra_id} con resultado: #{inspect(resultado)}"
    )

    compra_state = Map.get(state, compra_id, %{})

    if compra_state == %{} do
      {:reply, {:error, "Compra no encontrada"}, state}
    else
      # Actualizamos el valor de "reserva" en compra_state con el resultado
      new_compra_state1 = Map.put(compra_state, "reservado", resultado)
      compra_state2 = Map.get(state, compra_id, %{})
      new_compra_state2 = Map.put(compra_state2, "producto", producto_id)

      # Actualizamos el estado general con el nuevo estado de la compra
      new_state = Map.put(state, compra_id, new_compra_state2)

      {:reply, {:ok, new_compra_state2}, new_state}
    end
  end
end
