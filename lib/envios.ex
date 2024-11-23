defmodule Libremarket.Envios.Message do
  use GenServer
  use AMQP

  @queue "envios"

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

  def mandar_actualizacion(id_compras, resultado) do
    GenServer.cast(__MODULE__, {:mandar_actualizacion, id_compras, resultado})
  end

  @impl true
  def handle_cast({:mandar_actualizacion, id, message}, state) do
    IO.puts("Envios: {Enviando actualización: #{inspect(message)}}")
    payload = :erlang.term_to_binary(%{result: message, compra_id: id, accion: "calcular"})
    #IO.puts("Enviando payload: #{inspect(payload)}")

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
    IO.puts("Envios: {Mensaje recibido: #{inspect(message)}}")

    case message[:action] do
      "calcular_costo" ->
        IO.puts("Envios: {Calculando costo de la compra #{message[:compra_id]}}")
        Libremarket.Envios.Server.calcularCosto(message[:compra_id])

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

defmodule Libremarket.Envios do
  @tabla :envios
  @intervalo 60_000
  def calcularCosto() do
    {:rand.uniform(10000)}
  end

  def agendar(compra_id, producto_id, cantidad) do
    %{"estado" => "agendada"}
  end

  def guardarEstado(state) do
    :dets.insert(@tabla, {:envios, state})
    :timer.send_interval(@intervalo, :guardar_estado)
  end
end

defmodule Libremarket.Envios.Server do
  @moduledoc """
  Envios
  """

  use GenServer
  @tabla :envios

  # API del cliente

  @doc """
  Crea un nuevo servidor de Envios
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def calcularCosto(pid \\ __MODULE__, compra_id) do
    GenServer.cast({:global, __MODULE__}, {:calcular, compra_id})
  end

  def agendarEnvio(pid \\ __MODULE__, compra_id, producto_id, cantidad) do
    GenServer.call({:global, __MODULE__}, {:agendar, compra_id, producto_id, cantidad})
  end

  def listarEnvios(pid \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :listar)
  end

  def inspeccionar(pid \\ __MODULE__, id) do
    GenServer.call({:global, __MODULE__}, {:inspeccionar, id})
  end

  def guardar_estado(pid \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :guardar_estado)
  end


  # Callbacks

  @spec init(any()) :: {:ok, any()} | {:stop, any()}
  @doc """
  Inicializa el estado del servidor
  """
  @impl true
  def init(state) do
    case :dets.open_file(@tabla, type: :set, file: ~c"envios.dets") do
      {:ok, _} ->
        state =
          case :dets.lookup(@tabla, :envios) do
            [] -> %{}
            [{_key, value}] -> value
          end

        Libremarket.Envios.guardarEstado(state)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc """
  Callback para un call :autorizar
  """
  @impl true
  def handle_cast({:calcular, compra_id}, state) do
    result = Libremarket.Envios.calcularCosto()
    Libremarket.Envios.Message.mandar_actualizacion(compra_id, result)
    new_state = Map.put(state, compra_id, result)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:agendar, compra_id, producto_id, cantidad}, _from, state) do
    result = Libremarket.Envios.agendar(compra_id, producto_id, cantidad)
    new_state = Map.put(state, compra_id, result)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:listar, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:inspeccionar, id}, _from, state) do
    raise "error"
  end

  @impl true
  def handle_info(:guardar_estado, state) do
    Libremarket.Envios.guardarEstado(state)
    {:noreply, state}
  end
end
