defmodule Comprador do


  def realizarCompra(pid \\ __MODULE__, idProducto,pago,tipoEnvio,cantidad) do
    idCompra = {:rand.uniform(100)}
    idVendedor = {:rand.uniform(2)}
    listaProductos =  Libremarket.Ventas.Server.productos()

    #if not Enum.any?(listaProductos, fn producto -> producto[:id] == idProducto end) do
      #{:reply, {:error, "no se encontro el producto"}}
    #end

    producto=Libremarket.Compras.Server.seleccionarProducto(idCompra, idProducto, cantidad)
    producto = Map.put(producto,"envio",tipoEnvio)
    producto = Map.put(producto,"pago",pago)

    if(producto["reservado"]== false) do
      {:reply,{:error,"no se pudo realizar la compra"}}
    else
      {:ok, Libremarket.Compras.Server.confirmar_compra(idCompra)}
    end

  end


end
