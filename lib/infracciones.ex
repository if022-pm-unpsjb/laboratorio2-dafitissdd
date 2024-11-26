defmodule Libremarket.Infracciones do
  @tabla :infracciones

  def detectarInfraccion() do
    if :rand.uniform(100) < 70 do
      "ok"
    else
      "infraccion"
    end
  end

  def guardarEstado(state) do
    :dets.insert(@tabla, {:infracciones, state})
  end
end

defmodule Libremarket.Infracciones.Message do
  use GenServer
  use AMQP

  @queue "infracciones"

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
    IO.puts("Infracciones: {Enviando actualización: #{inspect(message)}}")
    payload = :erlang.term_to_binary(%{result: message, compra_id: id, accion: "detectar"})

    Basic.publish(state.chan, "", "compras", payload)
    Basic.publish(state.chan, "", "ventas", payload)

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
    IO.puts("Infracciones: {Mensaje recibido: #{inspect(message)}}")

    case message[:action] do
      "detectar_infraccion" ->
        IO.puts("Infracciones: {Proceso de infraccion de la compra #{message[:compra_id]}}")
        Libremarket.Infracciones.Server.detectarInfraccion(message[:compra_id])

      _ ->
        IO.puts("Infracciones: acción desconocida: #{inspect(message)}")
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

defmodule Libremarket.Infracciones.Server do
  @moduledoc """
  infracciones
  """

  use GenServer

  # API del cliente

  @tabla :infracciones
  @intervalo 60_000
  @doc """
  Crea un nuevo servidor de infracciones
  """
  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def detectarInfraccion(pid \\ __MODULE__, compra_id) do
    GenServer.cast({:global, __MODULE__}, {:detectar_infraccion, compra_id})
  end

  def listarInfraccion(pid \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :listar)
  end

  def inspeccionar(pid \\ __MODULE__, id) do
    GenServer.call({:global, __MODULE__}, {:inspeccionar, id})
  end

  # Callbacks

  @doc """
  Inicializa el estado del servidor
  """
  @impl true
  def init(_opts) do
    case :dets.open_file(@tabla, type: :set, file: ~c"infracciones.dets") do
      {:ok, _} ->
        state =
          case :dets.lookup(@tabla, :infracciones) do
            [] -> %{}
            [{_key, value}] -> value
          end

        :timer.send_interval(@intervalo, self(), :guardarEstado)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:detectar_infraccion, compra_id}, state) do
    result = Libremarket.Infracciones.detectarInfraccion()
    Libremarket.Infracciones.Message.mandar_actualizacion(compra_id, result)
    new_state = Map.put(state, compra_id, result)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:listar, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:guardarEstado, state) do
    Libremarket.Infracciones.guardarEstado(state)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Libremarket.Infracciones.guardarEstado(state)
    :dets.close(@tabla)
    :ok
  end
end
