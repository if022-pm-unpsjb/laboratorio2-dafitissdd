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

  def seleccionarEnvio(tipoEnvio) do
    valor = :rand.uniform(100)
    costo = 0
    if valor < 80 do
      costo = Libremarket.Envios.calcularCosto()
    end
    %{"envio" => tipoEnvio, "costoEnvio" => costo}
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

  def seleccionarEnvio(pid \\ __MODULE__, compra_id, tipoEnvio) do
    GenServer.call(pid, {:selecc_envio, compra_id, tipoEnvio})
  end

  def seleccionarPago(pid \\ __MODULE__, compra_id, tipoPago) do
    GenServer.call(pid, {:selecc_pago, compra_id, tipoPago})
  end

  def obtener_estado(pid \\ __MODULE__) do
    GenServer.call(pid, :obtener_estado)
  end

  def confirmar_compra(pid \\ __MODULE__, compra_id) do
    GenServer.call(pid, {:confirmar_compra, compra_id})
  end

  def registrar_envio(pid \\ __MODULE__, compra_id, producto_id, cantidad) do
    GenServer.call(pid, {:registrar_envio, compra_id, producto_id, cantidad})
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
  def handle_call({:selecc_envio, compra_id, tipoEnvio}, _from, state) do
    result = Libremarket.Compras.seleccionarEnvio(tipoEnvio)
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.merge(compra_state, result)
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:selecc_pago, compra_id, tipoPago}, _from, state) do
    compra_state = Map.get(state, compra_id, %{})
    new_compra_state = Map.merge(compra_state, %{"pago" => tipoPago})
    new_state = Map.put(state, compra_id, new_compra_state)
    {:reply, %{"pago" => tipoPago}, new_state}
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

    if new_compra_state["confirmada"] && new_compra_state["envio"] == "correo"do
      producto_id = new_compra_state["producto"].id
      cantidad = new_compra_state["cantidad"]

      # Llamar directamente a la lógica de registrar envío dentro del GenServer
      handle_call({:registrar_envio, compra_id, producto_id, cantidad}, _from, new_state)

    else
      {:reply, new_compra_state, new_state}
    end
  end

  @impl true
  def handle_call({:registrar_envio, compra_id, producto_id, cantidad}, _from, state) do
    # Obtener el estado actual de la compra desde el estado del GenServer
    compra_state = Map.get(state, compra_id, %{})

    if compra_state["envio"] == "correo" do
      {:ok, _} = Libremarket.Envios.Server.agendarEnvio(producto_id, cantidad)

      update_compra_state = Map.put(compra_state, "enviado", true)
      new_state = Map.put(state, compra_id, update_compra_state)
      {:reply, update_compra_state, new_state}
    else
      {:reply, compra_state, state}
    end
  end
end
