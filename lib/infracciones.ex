defmodule Libremarket.Infracciones do
  @tabla :infracciones
  @intervalo 60_000

  def detectarInfraccion() do
    if :rand.uniform(100) < 70 do
      "ok"
    else
      "infraccion"
    end
  end

  def guardarEstado(state) do
    :dets.insert(@tabla, {:infracciones, state})
    :timer.send_interval(@intervalo, :guardarEstado)
  end
end

defmodule Libremarket.Infracciones.Menssage do
  use GenServer
  use AMQP

  @queue "infracciones"

  @impl true
  def init(_state) do
    {:ok, conn} = Connection.open("amqps://sjyxztwd:nQ28DYT15fVo8thS6lxtyHvI6ZUw7GcK@cougar.rmq.cloudamqp.com/sjyxztwd", ssl_options: [verify: :verify_none])
    {:ok, chan} = Channel.open(conn)

    {:ok, _} = Queue.declare(chan, @queue, auto_delete: true)

    {:ok, _consume_tag} = Basic.consume(chan, @queue, nil, no_ack: true)
    {:ok, chan}
  end

  # Public API para iniciar el proceso
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def handle_cast({:confirmar_compra, id, message}, chan) do
    Basic.publish(chan, "", "compras", :binary.encode_unsigned(message))
    #IO.puts("Mensaje enviado de infracciones: #{message}")
    {:noreply, chan}
  end

  # defp recibir_mensaje(channel) do
  #   receive do
  #     {:basic_deliver, payload, _meta} ->
  #       IO.puts("Infracciones recibio: #{payload}")
  #       recibir_mensaje(channel)
  #   end
  # end

  # Handler para mensajes recibidos
  @impl true
  def handle_info({:basic_deliver, payload, %{delivery_tag: _tag, redelivered: _redelivered, correlation_id: id}}, chan) do
    # {eval_payload, _bindings} = Code.eval_string(payload)
    case id do
      "infracciones" ->
        resultado = :erlang.binary_to_term(payload)
        Compras.Server.actualizar_infraccion(resultado)
    end
    IO.puts("Infracciones recibio: #{payload}")
    {:noreply, chan}
  end
end

defmodule Libremarket.Infracciones.Server do
  @moduledoc """
  infracciones
  """

  use GenServer

  # API del cliente

  @tabla :infracciones
  @doc """
  Crea un nuevo servidor de infracciones
  """
  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def detectarInfraccion(pid \\ __MODULE__, compra_id) do
    GenServer.cast({:global, __MODULE__}, {:detectar, compra_id})
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

        Libremarket.Infracciones.guardarEstado(state)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc """
  Callback para un call :detectar
  """
  @impl true
  def handle_cast({:detectar, id}, state) do
    result = Libremarket.Infracciones.detectarInfraccion()
    Libremarket.Infracciones.Menssage.mandar_mensaje(inspect(result))
    new_state = Map.put(state, id, result)
    {:noreply, new_state}
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
