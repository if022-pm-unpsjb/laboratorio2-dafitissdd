defmodule Libremarket.Infracciones do

  def detectarInfraccion() do
    if :rand.uniform(100) < 70 do
      {:ok}
    else
      {:infraccion}
    end
  end

end

defmodule Libremarket.Infracciones.Server do
  @moduledoc """
  infracciones
  """

  use GenServer

  # API del cliente

  @doc """
  Crea un nuevo servidor de infracciones
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def detectarInfraccion(pid \\ __MODULE__, compra_id) do
    GenServer.call(pid, {:detectar, compra_id})
  end

  def listarInfraccion(pid \\ __MODULE__) do
    GenServer.call(pid, :listar)
  end

  def inspeccionar(pid \\ __MODULE__, id) do
    GenServer.call(pid, {:inspeccionar, id})
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
  Callback para un call :detectar
  """
  @impl true
  def handle_call({:detectar, id}, _from, state) do
    result = Libremarket.Infracciones.detectarInfraccion()
    {:reply, result, [{result, id} | state]}
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
