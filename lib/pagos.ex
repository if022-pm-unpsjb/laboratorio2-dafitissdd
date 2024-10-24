defmodule Libremarket.Pagos do
  @tabla :pagos
  @intervalo 60_000

  def autorizarPago(compra_id) do
    if :rand.uniform(100) < 70 do
      %{"autorizada" => true}
    else
      %{"autorizada" => false}
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
