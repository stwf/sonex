defmodule Sonex do
  def get_zones do
    Sonex.Discovery.zones()
  end

  def players_in_zone(zone_uuid) do
    Sonex.Discovery.players_in_zone(zone_uuid)
  end
end
