defmodule Libremarket.Envios do

  def calcularCosto() do
      {:rand.uniform(10000)}
  end

  def agendarEnvio() do
    {:ok}
  end

end

defmodule Libremarket.Envios.Server do
  @moduledoc """
  Envios
  """

  use GenServer

  # API del cliente

  @doc """
  Crea un nuevo servidor de Envios
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def calcularCosto(pid \\ __MODULE__, id) do
    GenServer.call({:global, __MODULE__}, {:calcular, id})
  end

  def agendarEnvio(pid \\ __MODULE__, id, cantidad) do
    GenServer.call({:global, __MODULE__}, {:agendar, id, cantidad})
  end

  def listarEnvio(pid \\ __MODULE__) do
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
  def init(state) do
    {:ok, state}
  end

  @doc """
  Callback para un call :autorizar
  """
  @impl true
  def handle_call({:calcular, id}, _from, state) do
    result = Libremarket.Envios.calcularCosto()
    {:reply, result, [{result, id} | state]}
  end

  @impl true
  def handle_call({:agendar, id, cantidad}, _from, state) do
    result = Libremarket.Envios.agendarEnvio()
    envio = Libremarket.Ventas.Server.enviarProducto(id, cantidad)
    {:reply, envio, [{result, id, cantidad} | state]}
  end

  @impl true
  def handle_call(:listar, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:inspeccionar, id}, _from, state) do
    raise "error"
  end

end
