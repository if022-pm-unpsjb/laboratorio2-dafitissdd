defmodule Libremarket.Compras do
  @tabla :compras
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

  def guardarEstado(state) do
    :dets.insert(@tabla, {:compras, state})
    :timer.send_interval(@intervalo, :guardarEstado)
  end

  def siguiente_id(state) do
    case Map.keys(state) do
      [] -> 1  # Si no hay compras previas, empieza en 1
      keys -> Enum.max(keys) + 1  # Incrementa el id más alto en 1
    end
  end

end

defmodule Libremarket.Compras.Server do
  @moduledoc """
  Compras
  """

  use GenServer
  @intervalo 5_000
  @tabla :compras
  # API del cliente

  @doc """
  Crea un nuevo servidor de Compras
  """
  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts, name: {:global, __MODULE__})
  end

  def comprar(pid \\ __MODULE__, vendedor) do
    GenServer.call({:global, __MODULE__}, {:comprar, vendedor})
  end

  def seleccionarProducto(pid \\ __MODULE__, compra_id, producto_id, cantidad) do
    GenServer.call({:global, __MODULE__}, {:selecc_producto, compra_id, producto_id, cantidad})
  end

  def seleccionarEnvio(pid \\ __MODULE__, compra_id, tipoEnvio) do
    GenServer.call({:global, __MODULE__}, {:selecc_envio, compra_id, tipoEnvio})
  end

  def seleccionarPago(pid \\ __MODULE__, compra_id, tipoPago) do
    GenServer.call({:global, __MODULE__}, {:selecc_pago, compra_id, tipoPago})
  end

  def obtener_estado(pid \\ __MODULE__) do
    GenServer.call({:global, __MODULE__}, :obtener_estado)
  end

  def confirmar_compra(pid \\ __MODULE__, compra_id) do
    GenServer.call({:global, __MODULE__}, {:confirmar_compra, compra_id})
  end

  def registrar_envio(pid \\ __MODULE__, compra_id, producto_id, cantidad) do
    GenServer.call({:global, __MODULE__}, {:registrar_envio, compra_id, producto_id, cantidad})
  end

  # Callbacks

  @doc """
  Inicializa el estado del servidor
  """
  @impl true
  def init(state) do
    case :dets.open_file(@tabla,  [type: :set, file: 'compras.dets']) do
      {:ok, _} ->
        state =
          case :dets.lookup(@tabla, :compras) do
            [] -> %{}
            [{_key, value}] -> value
          end
          :timer.send_interval(@intervalo, :guardarEstado)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc """
  Callback para un call :comprar
  """
  @impl true
  def handle_call({:comprar, vendedor}, _from, state) do
    compra_id = Libremarket.Compras.siguiente_id(state)
    result = Libremarket.Compras.comprar(compra_id, vendedor)
    new_state = Map.put(state, compra_id, result)
    {:reply, compra_id, new_state}
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
    #Libremarket.Compras.guardarEstado(state)
    {:reply, state, state}
  end

  @impl true
  def handle_info(:guardarEstado, state) do
    Libremarket.Compras.guardarEstado(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:confirmar_compra, compra_id}, _from, state) do
    compra_state = Map.get(state, compra_id, %{})
    # Asegúrate de que la compra existe y maneja el caso donde no existe
    if compra_state == %{} do
      {:reply, {:error, "Compra no encontrada"}, state}
    else
      infraccion = Map.get(compra_state, "infraccion", "unknown")
      reservado = Map.get(compra_state, "reservado", "unknown")

      result =
        if infraccion == "ok" && reservado == true do
          %{"confirmada" => true}
        else
          %{"confirmada" => false}
        end

      new_compra_state = Map.merge(compra_state, result)
      new_state = Map.put(state, compra_id, new_compra_state)

      if new_compra_state["confirmada"] && new_compra_state["envio"] == "correo" do
        # Asegúrate de que "producto" es un mapa que contiene ":id"
        producto_id = Map.get(new_compra_state, "producto", %{}) |> Map.get(:id, nil)
        cantidad = Map.get(new_compra_state, "cantidad", 0)

        # Llama a la lógica de registrar envío
        handle_call({:registrar_envio, compra_id, producto_id, cantidad}, _from, new_state)
      else
        {:reply, new_compra_state, new_state}
      end
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
