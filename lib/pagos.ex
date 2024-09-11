defmodule Libremarket.Pagos do

  def autorizarPago() do
    if :rand.uniform(100) < 70 do
      {:ok}
    else
      {:error}
    end
  end

end

defmodule Libremarket.Pagos.Server do
  @moduledoc """
  pagos
  """

  use GenServer

  # API del cliente

  @doc """
  Crea un nuevo servidor de pagos
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def autorizarPago(pid \\ __MODULE__, id) do
    GenServer.call(pid, {:autorizar, id})
  end

  def listarPagos(pid \\ __MODULE__) do
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
  Callback para un call :autorizar
  """
  @impl true
  def handle_call({:autorizar, id}, _from, state) do
    result = Libremarket.Pagos.autorizarPago()
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
