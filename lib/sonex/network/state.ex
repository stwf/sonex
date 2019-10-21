defmodule Sonex.Network.State do
  defmodule NetState do
    defstruct current_zone: "", players: %{}
  end

  use GenServer
  require Logger

  alias Sonex.Network.State.NetState

  def start_link(_vars) do
    GenServer.start_link(__MODULE__, initial_data(), name: __MODULE__)
  end

  def get_player(name: _name) do

  end

  def players do
    GenServer.call(__MODULE__, :players)
  end

  def update_device(%SonosDevice{} = device) do
    GenServer.call(__MODULE__, {:update_device, device})
  end

  def players_in_zone(zone_uuid) do
    GenServer.call(__MODULE__, {:players_in_zone, zone_uuid})
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def zones() do
    GenServer.call(__MODULE__, :zones)
  end

  def set_coordinator(uuid, coordinator_uuid) do
    GenServer.call(__MODULE__, {:set_coordinator, uuid, coordinator_uuid})
  end

  def set_name(uuid, name) do
    GenServer.call(__MODULE__, {:set_name, uuid, name})
  end

  def init(data) do
    {:ok, data}
  end

  def handle_call(:get_state, _from, %NetState{} = state) do
    {:reply, state, state}
  end

  def handle_call({:player_by_name, name}, _from, %NetState{players: players} = state) do
    res =
      players
      |> Map.values()
      |> Enum.find(nil, fn player ->
          player.name == name
         end)

    {:reply, res, state}
  end

  def handle_call({:set_coordinator, uuid, coordinator_uuid}, _from, %NetState{players: players} = state) do
    players =
      players
      |> Map.get(uuid)
      |> case do
        nil ->
          players
        player ->
          Process.send(self(), {:broadcast, player, :updated}, [])
          Map.put(players, uuid, %{player | coordinator_uuid: coordinator_uuid})
        end


    {:reply, players, %{state | players: players}}
  end

  def handle_call({:set_name, uuid, name}, _from, %NetState{players: players} = state) do
    players =
      players
      |> Map.get(uuid)
      |> case do
        nil ->
          players
        player ->
          Process.send(self(), {:broadcast, player, :updated}, [])
          Map.put(players, uuid, %{player | name: name})
        end


    {:reply, players, %{state | players: players}}
  end

  def handle_call(:players, _from, %NetState{players: players} = state) do
    {:reply, Map.values(players), state}
  end

  def handle_call(:zones, _from, %NetState{players: players} = state) do
    zone_coordinators =
      players
      |> Map.values()
      |> Enum.filter(&is_coordinator?(&1))

    {:reply, zone_coordinators, state}
  end

  def handle_call({:zone_by_name, name}, _from, %NetState{players: players} = state) do
    players_in_zone =
      players
      |> Map.values()
      |> Enum.filter(&is_coordinator?(&1))
      |> Enum.filter(fn coordinator -> coordinator.name == name end)
      |> case do
        [] ->
          {:error, "Not a Coordintator"}

        [zone] ->
          Enum.filter(state.players, fn p -> zone.uuid == p.coordinator_uuid end)
          |> Enum.reverse()
      end

    {:reply, players_in_zone, state}
  end

  def handle_call({:players_in_zone, uuid}, _from, %NetState{players: players} = state) do
    players_in_zone =
      players
      |> Map.values
      |> Enum.filter(fn p -> uuid == p.coordinator_uuid end)
      |> Enum.reverse()

    {:reply, players_in_zone, state}
  end

  def handle_call(:count, _from, %NetState{players: players} = state) do
    {:reply, Enum.count(players), state}
  end

  def handle_call(:discovered, _from, %NetState{players: players} = state) do
    {:reply, not Enum.empty?(players), state}
  end

  def handle_call({:update_device, %SonosDevice{uuid: uuid} = device}, _from, %NetState{players: players} = state) do
    players
    |> Map.get(uuid)
    |> case do
      nil ->
        Process.send(self(), {:broadcast, device, :discovered}, [])
      _dev ->
        Process.send(self(), {:broadcast, device, :updated}, [])
    end

  
    {:reply, :ok, %NetState{state | players: Map.put(players, uuid, device)}}
  end

  def terminate(reason, _state) do
    Logger.error("exiting Sonex.Network.State due to #{inspect(reason)}")
  end

  def handle_info({:broadcast, device, key}, state) do
    Registry.dispatch(Sonex, "devices", fn entries ->
      for {pid, _} <- entries do
        IO.inspect(pid, label: "pid in send")
        send(pid, {key, device})
      end
    end)

    {:noreply, state}
  end

  defp is_coordinator?(%SonosDevice{uuid: uuid, coordinator_uuid: coordinator_uuid}) do
    uuid == coordinator_uuid
  end

  defp initial_data do
    %NetState{}
  end
end
