defmodule Libremarket.Compras do
  def comprar(id) do
    id
  end

  def seleccionarProducto(compra_id, producto_id) do
    infraccion = Libremarket.Infracciones.Server.detectarInfraccion(compra_id)
    resultado = Libremarket.Ventas.Server.reservarProducto(producto_id, 3)
    map = %{"producto" => producto_id, "infraccion" => infraccion, "reservado" => true}
    map
  end

  def seleccionarEnvio() do
    valor = :rand.uniform(100)

    if valor < 80 do
      costo = Libremarket.Envios.calcularCosto()
      %{"envio" => "correo", "costo" => costo}
    else
      %{"envio" => "retira"}
    end
  end

  def seleccionarPago(compra_id) do
    valor = :rand.uniform(100)

    if valor < 40 do
      %{"pago" => "mercado pago"}
    else
      if valor >= 40 and valor < 80 do
        %{"pago" => "crédito"}
      else
        %{"pago" => "efectivo"}
      end
    end
  end
end

defmodule Libremarket.Compras.Server do
  @moduledoc """
  Compras
  """

  use GenServer

  # API del cliente

  @doc """
  Crea un nuevo servidor de Compras
  """
  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def comprar(pid \\ __MODULE__, compra_id) do
    GenServer.call(pid, {:comprar, compra_id})
  end

  def seleccionarProducto(pid \\ __MODULE__, compra_id, producto_id) do
    GenServer.call(pid, {:selecc_producto, compra_id, producto_id})
  end

  def seleccionarEnvio(pid \\ __MODULE__, compra_id) do
    GenServer.call(pid, {:selecc_envio, compra_id})
  end

  def seleccionarPago(pid \\ __MODULE__, compra_id) do
    GenServer.call(pid, {:selecc_pago, compra_id})
  end

  def obtener_estado(pid \\ __MODULE__) do
    GenServer.call(pid, :obtener_estado)
  end


  def confirmar_compra(pid \\ __MODULE__, compra_id) do
    GenServer.call(pid, {:confirmar_compra, compra_id})
  end

  # Callbacks

  @doc """
  Inicializa el estado del servidor
  """
  @impl true
  def init(state) do
    state = %{}
    {:ok, state}
  end

  @doc """
  Callback para un call :comprar
  """
  @impl true
  def handle_call({:comprar, compra_id}, _from, state) do
    result = Libremarket.Compras.comprar(compra_id)
    new_state = Map.put(state, compra_id, %{})
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:selecc_producto, compra_id, producto_id}, _from, state) do
    result = Libremarket.Compras.seleccionarProducto(compra_id, producto_id)
    new_state = Map.put(state, compra_id, result)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:selecc_envio, compra_id}, _from, state) do
    result = Libremarket.Compras.seleccionarEnvio()
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.merge(compra_state, result)
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:selecc_pago, compra_id}, _from, state) do
    result = Libremarket.Compras.seleccionarPago(compra_id)
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.merge(compra_state, result)
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:obtener_estado, _from, state) do
    {:reply, state, state}
  end


  def  handle_call({:confirmar_compra, compra_id}, _from, state) do
    compra_state = Map.get(state, compra_id, %{})
    result = if compra_state["infraccion"] == {:ok} do
      %{"confirmada" => true}
    else
      %{"confirmada" => false}
    end
    new_compra_state = Map.merge(compra_state, result)
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, result, new_state}
  end

end
