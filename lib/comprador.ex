defmodule Comprador do
  def realizarCompra(
        pid \\ __MODULE__,
        idCompra,
        idVendedor,
        idProducto,
        tipoPago,
        tipoEnvio,
        cantidad
      ) do
    Libremarket.Compras.Server.comprar(idCompra, idVendedor)
    Libremarket.Compras.Server.seleccionarProducto(idCompra, idProducto, cantidad)
    Libremarket.Compras.Server.seleccionarEnvio(idCompra, tipoEnvio)
    Libremarket.Compras.Server.seleccionarPago(idCompra, tipoPago)
    Libremarket.Compras.Server.confirmar_compra(idCompra)
  end

  def realizarCompraRandom(pid \\ __MODULE__, cant) do
    for contador <- 1..cant do
      idCompra = contador
      idVendedor = :rand.uniform(5)
      idProducto = :rand.uniform(10)
      valor = :rand.uniform(100)
      tipoEnvio = "error"

      if valor < 80 do
        tipoEnvio = "correo"
      else
        tipoEnvio = "retira"
      end

      # if

      valor = :rand.uniform(100)
      tipoPago = "error"

      if valor < 40 do
        tipoPago = "mercado pago"
      else
        if valor >= 40 and valor < 80 do
          tipoPago = "crédito"
        else
          tipoPago = "efectivo"
        end

        # if
      end

      # if

      cantidad = :rand.uniform(5)

      realizarCompra(
        __MODULE__,
        idCompra,
        idVendedor,
        idProducto,
        tipoPago,
        tipoEnvio,
        cantidad
      )
    end
  end
end
