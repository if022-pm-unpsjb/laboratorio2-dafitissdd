defmodule Comprador do
  def realizarCompra(
        pid \\ __MODULE__,
        idVendedor,
        idProducto,
        tipoPago,
        tipoEnvio,
        cantidad
      ) do
    idCompra = Libremarket.Compras.Server.comprar(idVendedor)
    if is_integer(idCompra) do
      Libremarket.Compras.Server.seleccionarProducto(idCompra, idProducto, cantidad)
      Libremarket.Compras.Server.seleccionarEnvio(idCompra, tipoEnvio)
      Libremarket.Compras.Server.seleccionarPago(idCompra, tipoPago)
      Libremarket.Compras.Server.confirmar_compra(idCompra)
    else
      {:error, "Error al generar ID de compra"}
    end
  end

  def realizarCompraRandom(pid \\ __MODULE__, cant) do
     for contador <- 1..cant do
      idVendedor = :rand.uniform(5)
      idProducto = :rand.uniform(10)
      valor = :rand.uniform(100)
      tipoEnvio = if valor < 80, do: "correo", else: "retira"

      valor = :rand.uniform(100)
      tipoPago = cond do
        valor < 40 -> "mercado pago"
        valor < 80 -> "crédito"
        true -> "efectivo"
      end

      cantidad = :rand.uniform(5)

      realizarCompra(
        __MODULE__,
        idVendedor,
        idProducto,
        tipoPago,
        tipoEnvio,
        cantidad
      )
    end
  end
end
