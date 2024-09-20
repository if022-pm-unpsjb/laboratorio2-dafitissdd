defmodule Libremarket.Compras do
  def comprar(compra_id, vendedor_id) do
    vendedor = Libremarket.Ventas.Server.buscarVendedor(vendedor_id)

    map =
      case vendedor do
        {:ok, vendedor} ->
          %{
            "vendedor" => vendedor
          }

        {:error, _reason} ->
          %{}
      end
  end

  def seleccionarProducto(compra_id, producto_id, cantidad) do
    infraccion = Libremarket.Infracciones.Server.detectarInfraccion(compra_id)
    resultado = Libremarket.Ventas.Server.reservarProducto(producto_id, cantidad)

    map =
      case resultado do
        {:ok, producto_actualizado} ->
          %{
            "producto" => producto_actualizado,
            "cantidad" => cantidad,
            "infraccion" => infraccion,
            "reservado" => true
          }

        {:error, _reason} ->
          %{
            "producto" => producto_id,
            "cantidad" => cantidad,
            "infraccion" => infraccion,
            "reservado" => false
          }
      end

    # Retornamos el mapa
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

  def seleccionarPago() do
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

  def comprar(pid \\ __MODULE__, compra_id, vendedor) do
    GenServer.call(pid, {:comprar, compra_id, vendedor})
  end

  def seleccionarProducto(pid \\ __MODULE__, compra_id, producto_id, cantidad) do
    GenServer.call(pid, {:selecc_producto, compra_id, producto_id, cantidad})
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
  def handle_call({:comprar, compra_id, vendedor}, _from, state) do
    result = Libremarket.Compras.comprar(compra_id, vendedor)
    new_state = Map.put(state, compra_id, result)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:selecc_producto, compra_id, producto_id, cantidad}, _from, state) do
    result = Libremarket.Compras.seleccionarProducto(compra_id, producto_id, cantidad)
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.merge(compra_state, result)
    new_state = Map.put(state, compra_id, new_compra_state)
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
    result = Libremarket.Compras.seleccionarPago()
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.merge(compra_state, result)
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:obtener_estado, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:confirmar_compra, compra_id}, _from, state) do
    compra_state = Map.get(state, compra_id, %{})

    result =
      if compra_state["infraccion"] == {:ok} do
        %{"confirmada" => true}
      else
        %{"confirmada" => false}
      end

    new_compra_state = Map.merge(compra_state, result)
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, result, new_state}
  end
end
