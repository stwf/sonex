defmodule Sonex.PlayerMonitor do
  use GenServer

  def start_link(%ZonePlayer{} = empty_state) do
    GenServer.start_link(__MODULE__, empty_state, name: ref(empty_state.id))
  end

  def create(%ZonePlayer{} = empty_state) do
    case GenServer.whereis(ref(empty_state.id)) do
      nil ->
        Supervisor.start_child(Sonex.Player.Supervisor, [empty_state])

      _zone ->
        {:error, :player_already_exists}
    end
  end

  def player_by_name(name) do
    player =
      Enum.flat_map(Sonex.Discovery.players(), fn player ->
        [GenServer.whereis({:global, {:player, player.uuid}})]
      end)
      |> Enum.filter(fn pid -> name == GenServer.call(pid, {:name}) end)

    case(player) do
      [zone_player] ->
        {:ok, zone_player}

      [] ->
        {:error, "Player of that name does not exist"}
    end
  end

  def player_by_name!(name) do
    player =
      Enum.flat_map(Sonex.Discovery.players(), fn player ->
        [GenServer.whereis({:global, {:player, player.uuid}})]
      end)
      |> Enum.filter(fn pid -> name == GenServer.call(pid, {:name}) end)

    case(player) do
      [zone_player] ->
        zone_player

      [] ->
        :error
    end
  end

  def player_details(name) do
    case(player_by_name!(name)) do
      :error -> "Player does not exist"
      player -> GenServer.call(player, {:details})
    end
  end

  def init(%ZonePlayer{} = player) do
    # triggers subscription
    Registry.dispatch(Sonex, "devices", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:discovered, player})
    end)

    {:ok, player}
  end

  # ...

  def handle_cast({:set_name, new_name},
        %ZonePlayer{name: name} = player) when new_name != name do
    new_player = %ZonePlayer{player | name: name}
    update_device(new_player)
    IO.puts("set_name")

    {:noreply, new_player}
  end

  def handle_cast({:set_coordinator, coordinator},
        %ZonePlayer{coordinator_id: coordinator_id} = player) when coordinator_id != coordinator do

    IO.puts("set_coordinator")
    new_player = %ZonePlayer{player | coordinator_id: coordinator}
    update_device(new_player)

    {:noreply, new_player}
  end

  def handle_cast({:set_volume, volume_map},
        %ZonePlayer{player_state: %PlayerState{volume: volume}} = player) when volume_map != volume do
    new_player = 
      %ZonePlayer{player | player_state: %PlayerState{player.player_state | volume: volume_map}}

    IO.inspect(volume_map, label: "set_volume")
    update_device(new_player)
    {:noreply, new_player}
  end

  def handle_cast({:set_mute, new_mute},
        %ZonePlayer{player_state: %PlayerState{mute: mute}} = player) when new_mute != mute do
    new_player =
      %ZonePlayer{player | player_state: %PlayerState{player.player_state | mute: new_mute}}

    IO.puts("set_mute")
    update_device(new_player)
    {:noreply, new_player}
  end

  def handle_cast({:set_treble, new_treble},
        %ZonePlayer{player_state: %PlayerState{treble: treble}} = player) when new_treble != treble do
    new_player =
      %ZonePlayer{player | player_state: %PlayerState{player.player_state | treble: new_treble}}

    IO.puts("set_treble #{treble} => #{new_treble}")
    IO.puts("set_treble")
    update_device(new_player)
    {:noreply, new_player}
  end

  def handle_cast({:set_bass, new_bass},
        %ZonePlayer{player_state: %PlayerState{bass: bass}} = player) when new_bass != bass do
    new_player =
      %ZonePlayer{player | player_state: %PlayerState{player.player_state | bass: bass}}

    IO.puts("set_bass #{bass} => #{new_bass}")
    update_device(new_player)
    {:noreply, new_player}
  end

  def handle_cast({:set_loudness, new_loudness},
          %ZonePlayer{player_state: %PlayerState{loudness: loudness}} = player) when loudness != new_loudness do
    new_player =
      %ZonePlayer{player | player_state: %PlayerState{player.player_state | loudness: loudness}}

    IO.puts("set_loudness #{loudness} => #{new_loudness}")

    update_device(new_player)
    {:noreply, new_player}
  end

  def handle_cast({:set_state, new_player_state}, %ZonePlayer{} = player) do
    new_player =
      %ZonePlayer{
       player
       | player_state: %PlayerState{
           player.player_state
           | current_state: new_player_state.current_state,
             current_mode: new_player_state.mode,
             total_tracks: new_player_state.tracks_total,
             track_number: new_player_state.current_track,
             track_info: new_player_state.track_info
         }
     }
    IO.puts("set_state")
    update_device(new_player)     
    {:noreply, new_player}
  end

  def handle_cast(_, state), do: {:noreply, state}

  def handle_call({:name}, _from, %ZonePlayer{} = player) do
    {:reply, player.name, player}
  end

  def handle_call({:details}, _from, %ZonePlayer{} = player) do
    {:reply, player, player}
  end

  defp ref(player_id) do
    {:global, {:player, player_id}}
  end

  defp try_call(player_id, message) do
    case GenServer.whereis(ref(player_id)) do
      nil ->
        {:error, :invalid_player}

      player ->
        GenServer.call(player, message)
    end
  end

  defp update_device(%SonosDevice{name: name} = device) do
    IO.inspect(name, label: "device updated")
    Registry.dispatch(Sonex, "devices", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:updated, device})
    end)
  end

  defp update_device(%ZonePlayer{name: name} = player) do
    IO.inspect(name, label: "player updated")
    Registry.dispatch(Sonex, "players", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:updated, player})
    end)
  end
end
