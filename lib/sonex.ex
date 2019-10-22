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

  def get_grouped_players_in_zone(zone_uuid) do
    State.players_in_zone(zone_uuid)
    |> Enum.reduce(%{coord: [], player: []}, &accumulate_states(&1, &2))
  end


  defp accumulate_states(%{uuid: uuid, coordinator_uuid: coordinator_uuid} = player, acc)
    when uuid == coordinator_uuid do
      Map.put(acc, :coord, player)
  end

  defp accumulate_states(%{uuid: uuid} = player, acc) do
    case Map.get(acc, :player) do
      nil ->
        Map.put(acc, :player, [player])
      curr ->
        Map.put(acc, :player, [player | curr])
    end
  end
end
