defmodule Libremarket.Compras do
  @tabla :compras

  def comprar(compra_id, vendedor_id) do
    map =
          %{
            "vendedor" => vendedor_id,
            "infraccion" => "proceso",
            "reservado" => "proceso",
            "producto" => nil,
            "cantidad" => nil,
            #"reservado" => nil,
            "confirmada" => nil,
            "envio" => nil,
            "pago" => nil,
            "pago autorizado" => "proceso"
          }
    map
  end

  def seleccionarProducto(compra_id, producto_id, cantidad) do
    resultado = Libremarket.Ventas.Server.reservarProducto(compra_id, producto_id, cantidad)
    resultado
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
    IO.puts("Compras: Pago rechazado para la compra #{compra_id}")
  end

  def informarInfraccion(compra_id) do
    IO.puts("Compras: Infracción detectada para la compra #{compra_id}")
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

  def autorizar_pago(id_compras) do
    GenServer.cast(__MODULE__, {:autorizar_pago, id_compras})
  end

  def calcular_costo(compra_id) do
    GenServer.cast(__MODULE__, {:calcular_costo,compra_id})
  end

  @impl true
  def init(_state) do
    {:ok, conn} =
      Connection.open(
        "amqps://sjyxztwd:nQ28DYT15fVo8thS6lxtyHvI6ZUw7GcK@cougar.rmq.cloudamqp.com/sjyxztwd",
        ssl_options: [verify: :verify_none]
      )

    {:ok, chan} = Channel.open(conn)

    Queue.declare(chan, @queue, auto_delete: false)
    Basic.consume(chan, @queue, nil, no_ack: true)

    {:ok, %{conn: conn, chan: chan}}
  end

  @impl true
  def handle_cast({:detectar_infraccion, compra_id}, state) do
    payload = :erlang.term_to_binary(%{action: "detectar_infraccion", compra_id: compra_id})
    Basic.publish(state.chan, "", "infracciones", payload)
    {:noreply, state}
  end

  def handle_cast({:reservar_producto, compra_id, producto_id, cantidad}, state) do
    IO.puts("Compras: enviando mensaje a Ventas -reservar_producto: #{compra_id}")
    payload = :erlang.term_to_binary(%{action: "reservar_producto", compra_id: compra_id, producto_id: producto_id, cantidad: cantidad})
    Basic.publish(state.chan, "", "ventas", payload)
    {:noreply, state}
  end

  def handle_cast({:calcular_costo, compra_id}, state) do
    IO.puts("Compras: enviando mensaje a Envios -calcular_costo: #{compra_id}")
    payload = :erlang.term_to_binary(%{action: "calcular_costo", compra_id: compra_id})
    Basic.publish(state.chan, "", "envios", payload)
    {:noreply, state}
  end

  def handle_cast({:autorizar_pago, compra_id}, state) do
    IO.puts("Compras: enviando mensaje a Pagos -autorizar_pago: #{compra_id}")
    payload = :erlang.term_to_binary(%{action: "autorizar_pago", compra_id: compra_id})
    Basic.publish(state.chan, "", "pagos", payload)
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
        IO.puts("Compras: {Recibiendo mensaje de Infracciones -actualizar_infraccion: #{message[:compra_id]}}")
        Libremarket.Compras.Server.actualizar_infraccion(message[:result], message[:compra_id])

      "reservar" ->
        IO.puts("Compras: {Recibiendo mensaje de Ventas -actualizar_reserva: #{message[:compra_id]}}")
        Libremarket.Compras.Server.actualizar_reserva(message[:result], message[:compra_id], message[:producto_id])

      "autorizar" ->
        IO.puts("Compras: {Recibiendo mensaje de Pagos -actualizar_autorizacion: #{message[:compra_id]}}")
        Libremarket.Compras.Server.actualizar_autorizacion(message[:result], message[:compra_id])

      "calcular" ->
        IO.puts("Compras: {Recibiendo mensaje de Envios -actualizar_costo: #{message[:compra_id]}}")
        Libremarket.Compras.Server.actualizar_costo(message[:result], message[:compra_id])

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

  def seleccionarProducto(_ \\ __MODULE__, compra_id, producto_id, cantidad, tipoPago, tipoEnvio) do
    GenServer.cast(
      {:global, __MODULE__},
      {:selecc_producto, compra_id, producto_id, cantidad, tipoPago, tipoEnvio}#,
#      15_000
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

  def actualizar_autorizacion(_ \\ __MODULE__, resultado, compra_id) do
    GenServer.call({:global, __MODULE__}, {:actualizar_autorizacion, resultado, compra_id}, 15_000)
  end

  def actualizar_costo(_ \\ __MODULE__, resultado, compra_id) do
    GenServer.call({:global, __MODULE__}, {:actualizar_costo, resultado, compra_id}, 15_000)
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
  def handle_cast({:selecc_producto, compra_id, producto_id, cantidad, tipoPago, tipoEnvio}, state) do
    Libremarket.Compras.Message.detectar_infraccion(compra_id)
    Libremarket.Compras.Message.reservar_producto(compra_id, producto_id, cantidad)
    new_state = update_in(state[compra_id], fn compra_state ->
      compra_state
      |> Map.put("producto", producto_id)
      |> Map.put("cantidad", cantidad)
    end)

    GenServer.cast(self(), {:selecc_envio, compra_id, tipoEnvio})
    GenServer.cast(self(), {:selecc_pago, compra_id, tipoPago})
    # IO.inspect({:procesando, compra_id, producto_id, cantidad}, label: "Seleccionando producto")

    # Responder al cliente
    #{:reply, :ok, state}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:selecc_envio, compra_id, tipoEnvio}, state) do
    if (tipoEnvio == "correo") do
      Libremarket.Compras.Message.calcular_costo(compra_id)
    end
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.put(compra_state, "envio", tipoEnvio)
    new_state = Map.put(state, compra_id, new_compra_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:selecc_pago, compra_id, tipoPago}, state) do
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.put(compra_state, "pago", tipoPago)
    new_state = Map.put(state, compra_id, new_compra_state)
    Libremarket.Compras.Message.autorizar_pago(compra_id)
    GenServer.cast(self(), {:confirmar_compra, compra_id})
    {:noreply, new_state}
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
  def handle_info({:confirmar_compra, compra_id}, state) do
    # Llama directamente a `handle_cast` para reutilizar la lógica
    handle_cast({:confirmar_compra, compra_id}, state)
  end

  @impl true
  def handle_cast({:confirmar_compra, compra_id}, state) do
    compra_state = Map.get(state, compra_id, %{})
    # Asegúrate de que la compra existe y maneja el caso donde no existe
    if compra_state == %{} do
      #{:reply, {:error, "Compra no encontrada"}, state}
      Logger.error("Compra #{compra_id} no encontrada")
      {:noreply, state}
    else
      infraccion = Map.get(compra_state, "infraccion", "unknown")
      reservado = Map.get(compra_state, "reservado", "unknown")
      envio = Map.get(compra_state, "envio", "unknown")
      cantidad = Map.get(compra_state, "cantidad", "unknown")
      autorizada = Map.get(compra_state, "pago autorizado", "unknown")

      if infraccion == "proceso" || reservado == "proceso" || autorizada == "proceso" do
        # Reintentar después de 1000 ms (1 segundo)
        Process.send_after(self(), {:confirmar_compra, compra_id}, 6000)
        {:noreply, state}
      else

        result =
          if infraccion == "ok" && reservado == true do

            if autorizada == true do
              if envio == "correo" do
                producto_id = Map.get(compra_state, "producto", "unknown")
                #producto_id = producto[:id]
                Libremarket.Envios.Server.agendarEnvio(compra_id, producto_id, cantidad)
              end

              # Libremarket.Compras.Message.mandar_mensaje("Compra confirmada: #{compra_id}")
            else
              Libremarket.Ventas.Server.liberarProducto(compra_id, cantidad)
              Libremarket.Compras.informarRechazo(compra_id)
            end

            true #%{"confirmada" => true}#, "autorizada" => autorizada}
          else
            Libremarket.Ventas.Server.liberarProducto(compra_id, cantidad)
            Libremarket.Compras.informarInfraccion(compra_id)
            false #%{"confirmada" => false}
          end

        IO.puts("Compras: compra #{compra_id} confirmada")
        new_compra_state = Map.put(compra_state, "confirmada", result)
        new_state = Map.put(state, compra_id, new_compra_state)

        {:noreply, new_state}
      end
    end
  end

  @impl true
  def handle_call({:actualizar_infraccion, resultado, compra_id}, _from, state) do
    IO.puts(
      "Compras: {Actualizando infracción para compra #{compra_id} con resultado: #{inspect(resultado)}}"
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
  def handle_call({:actualizar_reserva, resultado, compra_id, producto_id}, _from, state) do
    IO.puts(
      "Compras: {Actualizando reserva para compra #{compra_id} con resultado: #{inspect(resultado)}}"
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
  def handle_call({:actualizar_autorizacion, resultado, compra_id}, _from, state) do
    IO.puts(
      "Compras: {Actualizando autorización para compra #{compra_id} con resultado: #{inspect(resultado)}}"
    )

    compra_state = Map.get(state, compra_id, %{})

    if compra_state == %{} do
      {:reply, {:error, "Compra no encontrada"}, state}
    else
      # Actualizamos el valor de "pago autorizado" en compra_state con el resultado
        new_state = update_in(state[compra_id], fn compra_state ->
          compra_state
          |> Map.put("pago autorizado", resultado)
        end)

      {:reply, {:ok, compra_state}, new_state}
    end
  end

  @impl true
  def handle_call({:actualizar_reserva, resultado, compra_id, producto_id}, _from, state) do
    IO.puts(
      "Compras: {Actualizando reserva para compra #{compra_id} con resultado: #{inspect(resultado)}}"
    )

    compra_state = Map.get(state, compra_id, %{})

    if compra_state == %{} do
      {:reply, {:error, "Compra no encontrada"}, state}
    else
      # Actualizamos el valor de "reserva" en compra_state con el resultado
        new_state = update_in(state[compra_id], fn compra_state ->
          compra_state
          |> Map.put("reservado", resultado)
          |> Map.put("producto", producto_id)
        end)

      {:reply, {:ok, compra_state}, new_state}
    end
  end

  @impl true
  def handle_call({:actualizar_costo, resultado, compra_id}, _from, state) do
    IO.puts(
      "Compras: {Actualizando costo para compra #{compra_id} con resultado: #{inspect(resultado)}}"
    )

    compra_state = Map.get(state, compra_id, %{})

    if compra_state == %{} do
      {:reply, {:error, "Compra no encontrada"}, state}
    else
      # Actualizamos el valor de "costo" en compra_state con el resultado
      new_compra_state = Map.put(compra_state, "costo envio", resultado)

      # Actualizamos el estado general con el nuevo estado de la compra
      new_state = Map.put(state, compra_id, new_compra_state)

      {:reply, {:ok, new_compra_state}, new_state}
    end
  end
end
