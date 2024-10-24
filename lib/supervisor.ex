defmodule Libremarket.Supervisor do
  use Supervisor

  @doc """
  Inicia el supervisor
  """
  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    topologies = [
      gossip: [
        strategy: Cluster.Strategy.Gossip,
        config: [
          port: 45892,
          if_addr: "0.0.0.0",
          multicast_addr: "192.168.25.255",
          broadcast_only: true,
          secret: "dafiti"
        ]
      ]
    ]

    children = [
      {Cluster.Supervisor, [topologies, [name: MyApp.ClusterSupervisor]]},
      Libremarket.Compras.Server,
      Libremarket.Infracciones.Server,
      Libremarket.Pagos.Server,
      Libremarket.Envios.Server,
      Libremarket.Ventas.Server,
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
