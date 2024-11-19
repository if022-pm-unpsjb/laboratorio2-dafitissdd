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

    # {:ok, _} = Queue.declare(chan, @queue, auto_delete: true)
    # {:ok, _consume_tag} = Basic.consume(chan, @queue, nil, no_ack: true)
    # {:ok, chan}

    Queue.declare(chan, @queue, auto_delete: true)
    Basic.consume(chan, @queue, nil, no_ack: true)

    {:ok, %{conn: conn, chan: chan}}
  end


  def mandar_actualizacion(id_compras, resultado) do
    GenServer.cast(__MODULE__, {:mandar_actualizacion, id_compras, resultado})
  end


  # @impl true
  # def handle_cast({:mandar_actualizacion, id, message}, chan) do
  #   IO.puts("Enviando actualización: #{inspect(message)}")
  #   payload = %{result: message, compra_id: id}
  #   Basic.publish(chan, "", "compras", :erlang.term_to_binary(payload))
  #   {:noreply, chan}
  # end

  @impl true
  def handle_cast({:mandar_actualizacion, id, message}, state) do
    IO.puts("Enviando actualización: #{inspect(message)}")
    payload = :erlang.term_to_binary(%{result: message, compra_id: id})
    IO.puts("Enviando payload: #{inspect(payload)}")

    Basic.publish(state.chan, "", "compras", payload)
    {:noreply, state}
  end

  # Maneja el mensaje básico de confirmación de consumo
  @impl true
  def handle_info({:basic_consume_ok, _consumer_info}, chan) do
    {:noreply, chan}
  end

  # Handler para mensajes recibidos
  # @impl true
  # def handle_info(
  #       {:basic_deliver, payload,
  #        %{delivery_tag: _tag, redelivered: _redelivered, correlation_id: id}},
  #       chan
  #     ) do
  #   message = :erlang.binary_to_term(payload)
  #   result = message[:result]
  #   compra_id = message[:compra_id]

  #   IO.puts("Estado de compra #{compra_id}: #{result}")
  #   Libremarket.Compras.Server.actualizar_infraccion(result, compra_id)

  #   {:noreply, chan}
  # end

  @impl true
  def handle_info({:basic_deliver, payload, _meta}, state) do
    message = :erlang.binary_to_term(payload)
    IO.puts("Mensaje recibido: #{inspect(message)}")

    case message[:action] do
      "detectar_infraccion" ->
        IO.puts("Enviando mensaje a infracciones para compra #{message[:compra_id]}")
        Libremarket.Infracciones.Server.detectarInfraccion(message[:compra_id])
      _ ->
        IO.puts("Acción desconocida: #{inspect(message)}")
  end


    #IO.puts("Estado de compra #{message[:compra_id]}: #{message[:result]}")
    #IO.inspect(message, label: "Mensaje deserializado")
    #Libremarket.Compras.Server.actualizar_infraccion(message[:result], message[:compra_id])
    #IO.puts("Recibido mensaje: #{inspect(message)}")
    #Process.sleep(10_000)

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

        :timer.send_interval(@intervalo, :guardarEstado)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # @impl true
  # def init(_) do
  #   case :dets.open_file(@tabla, type: :set, file: ~c"infracciones.dets") do
  #     {:ok, _} ->
  #       state = :dets.lookup(@tabla, :infracciones) |> Enum.into(%{})
  #       :timer.send_interval(@intervalo, self(), :guardar_estado)
  #       {:ok, state}

  #     {:error, reason} -> {:stop, reason}
  #   end
  # end

  @doc """
  Callback para un call :detectar
  """
  # @impl true
  # def handle_cast({:detectar_infraccion, id}, state) do
  #   result = Libremarket.Infracciones.detectarInfraccion()
  #   Libremarket.Infracciones.Message.mandar_actualizacion(id, inspect(result))
  #   new_state = Map.put(state, id, result)
  #   {:noreply, new_state}
  # end

  @impl true
  def handle_cast({:detectar_infraccion, compra_id}, state) do
    result = Libremarket.Infracciones.detectarInfraccion()
    Libremarket.Infracciones.Message.mandar_actualizacion(compra_id, result)
    #IO.inspect({:procesando, compra_id, result}, label: "Detectó infracción")
    new_state = Map.put(state, compra_id, result)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:listar, _from, state) do
    {:reply, state, state}
  end

  # @impl true
  # def handle_call({:inspeccionar, id}, _from, state) do
  #   raise "error"
  # end

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
