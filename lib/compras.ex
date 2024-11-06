defmodule Libremarket.Compras.Menssage do
  use GenServer
  use AMQP

  # Public API para iniciar el proceso
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def mandar_mensaje(exchange_name, routing_key, message) do
    {:ok, connection} = Connection.open("amqps://sjyxztwd:nQ28DYT15fVo8thS6lxtyHvI6ZUw7GcK@cougar.rmq.cloudamqp.com/sjyxztwd", ssl_options: [verify: :verify_none])
    {:ok, channel} = Channel.open(connection)

    #queue_name = "compras_queue"
    #exchange_name = "Libremarket_compras_exchange"

    Queue.declare(channel, "compras_queue", durable: true)
    Exchange.declare(channel, exchange_name, :direct, durable: true)

    # Enlazar la cola con el exchange
    Queue.bind(channel, "compras_queue", exchange_name)

    # Publicar el mensaje
    Basic.publish(channel, exchange_name, routing_key, message)

    IO.puts("Mensaje enviado de compras: #{message}")

    # Cerrar conexión
    Channel.close(channel)
    Connection.close(connection)
  end

  defp recibir_mensaje(channel) do
    receive do
      {:basic_deliver, payload, _meta} ->
        IO.puts("Compras recibio: #{payload}")
        recibir_mensaje(channel)
    end
  end

  # Handler para mensajes recibidos
  def handle_info({:basic_deliver, payload, _meta}, state) do
    {eval_payload, _bindings} = Code.eval_string(payload)
    case eval_payload do
      {:confirmar_compra, id} -> GenServer.call({:global, Libremarket.Infracciones.Server}, {:confirmar_compra, id})
      _ -> IO.puts("#{eval_payload}")
    end
    IO.puts("Compras recibio: #{payload}")
    {:noreply, state}
  end
end

defmodule Libremarket.Compras do
  @tabla :compras
  @intervalo 60_000
  def comprar(compra_id, vendedor_id) do
    vendedor = Libremarket.Ventas.Server.buscarVendedor(vendedor_id)

    map =
      case vendedor do
        {:ok, vendedor} ->
          %{
            "vendedor" => vendedor
          }

        {:error, _reason} ->
          %{}
      end
  end

  def seleccionarProducto(compra_id, producto_id, cantidad) do
    infraccion = Libremarket.Infracciones.Server.detectarInfraccion(compra_id)
    resultado = Libremarket.Ventas.Server.reservarProducto(producto_id, cantidad)

    map =
      case resultado do
        {:ok, producto_actualizado} ->
          %{
            "producto" => producto_actualizado,
            "cantidad" => cantidad,
            "infraccion" => infraccion,
            "reservado" => true
          }

        {:error, _reason} ->
          %{
            "producto" => producto_id,
            "cantidad" => cantidad,
            "infraccion" => infraccion,
            "reservado" => false
          }
      end

    # Retornamos el mapa
    map
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
    :timer.send_interval(@intervalo, :guardar_estado)
  end

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
    GenServer.call({:global, __MODULE__}, {:comprar, vendedor})
  end

  def seleccionarProducto(_ \\ __MODULE__, compra_id, producto_id, cantidad) do
    GenServer.call({:global, __MODULE__}, {:selecc_producto, compra_id, producto_id, cantidad})
  end

  def seleccionarEnvio(_ \\ __MODULE__, compra_id, tipoEnvio) do
    GenServer.call({:global, __MODULE__}, {:selecc_envio, compra_id, tipoEnvio})
  end

  def seleccionarPago(_ \\ __MODULE__, compra_id, tipoPago) do
    GenServer.call({:global, __MODULE__}, {:selecc_pago, compra_id, tipoPago})
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

        Libremarket.Compras.guardarEstado(state)
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
    result = Libremarket.Compras.seleccionarProducto(compra_id, producto_id, cantidad)
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.merge(compra_state, result)
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, result, new_state}
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
            Libremarket.Compras.Menssage.mandar_mensaje("Libremarket_compras_exchange", "compra.confirmada", "Compra confirmada: #{compra_id}")
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
end
