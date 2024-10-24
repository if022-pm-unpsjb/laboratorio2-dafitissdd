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
    GenServer.call({:global, __MODULE__}, {:calcular, compra_id})
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
  def handle_call({:calcular, compra_id}, _from, state) do
    result = Libremarket.Envios.calcularCosto()
    new_state = Map.put(state, compra_id, result)
    {:reply, result, new_state}
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
