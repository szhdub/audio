defmodule HolaamigoGg do
  def init() do
    Photon.GenTCPAcceptor.start_link(443, Https)
  end
end
