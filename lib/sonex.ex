defmodule Sonex do

  alias Sonex.Network.State

  def players_in_zone(zone_uuid) do
    State.players_in_zone(zone_uuid)
  end

  def get_zones() do
    State.zones()
  end

  def get_players() do
    State.players()
  end
end
