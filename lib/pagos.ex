defmodule Libremarket.Pagos.Message do
  use GenServer
  use AMQP

  @queue "pagos"

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
    IO.puts("Pagos: {Enviando actualización: #{inspect(message)}}")
    payload = :erlang.term_to_binary(%{result: message, compra_id: id, accion: "autorizar"})

    Basic.publish(state.chan, "", "compras", payload)
    {:noreply, state}
  end

  @impl true
  def handle_info({:basic_consume_ok, _consumer_info}, chan) do
    {:noreply, chan}
  end

  @impl true
  def handle_info({:basic_deliver, payload, _meta}, state) do
    message = :erlang.binary_to_term(payload)
    IO.puts("Pagos: {Mensaje recibido: #{inspect(message)}}")

    case message[:action] do
      "autorizar_pago" ->
        IO.puts("Pagos: {Proceso de autorizacion de la compra: #{message[:compra_id]}}")
        Libremarket.Pagos.Server.autorizarPago(message[:compra_id])
      _ ->
        IO.puts("Acción desconocida: #{inspect(message)}")
  end

    {:noreply, state}
  end
end

defmodule Libremarket.Pagos do
  @tabla :pagos
  @intervalo 60_000

  def autorizarPago(compra_id) do
    if :rand.uniform(100) < 70 do
      true
    else
      false
    end
  end

  def guardarEstado(state) do
    :dets.insert(@tabla, {:pagos, state})
    :timer.send_interval(@intervalo, :guardar_estado)
  end
end

defmodule Libremarket.Pagos.Server do
  @moduledoc """
  pagos
  """

  use GenServer
  @tabla :pagos
  # API del cliente

  @doc """
  Crea un nuevo servidor de pagos
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def autorizarPago(pid \\ __MODULE__, compra_id) do
    GenServer.call({:global, __MODULE__}, {:autorizar, compra_id})
  end

  def listarPagos(pid \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :listar)
  end

  def inspeccionar(pid \\ __MODULE__, compra_id) do
    GenServer.call({:global, __MODULE__}, {:inspeccionar, compra_id})
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
    case :dets.open_file(@tabla, type: :set, file: ~c"pagos.dets") do
      {:ok, _} ->
        state =
          case :dets.lookup(@tabla, :pagos) do
            [] -> %{}
            [{_key, value}] -> value
          end

        Libremarket.Pagos.guardarEstado(state)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc """
  Callback para un call :autorizar
  """
  @impl true
  def handle_call({:autorizar, compra_id}, _from, state) do
    result = Libremarket.Pagos.autorizarPago(compra_id)
    Libremarket.Pagos.Message.mandar_actualizacion(compra_id, result)
    new_state = Map.put(state, compra_id, result)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:listar, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:inspeccionar, compra_id}, _from, state) do
    raise "error"
  end

  @impl true
  def handle_info(:guardar_estado, state) do
    Libremarket.Pagos.guardarEstado(state)
    {:noreply, state}
  end
end
