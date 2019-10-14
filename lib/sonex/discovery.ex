defmodule DiscoverState do
  defstruct socket: nil, players: [], player_count: 0
  @type t :: %__MODULE__{socket: pid, players: list, player_count: integer}
end

defmodule Sonex.Discovery do
  use GenServer

  require Logger

  @playersearch ~S"""
  M-SEARCH * HTTP/1.1
  HOST: 239.255.255.250:1900
  MAN: "ssdp:discover"
  MX: 1
  ST: urn:schemas-upnp-org:device:ZonePlayer:1
  """
  @multicastaddr {239, 255, 255, 250}
  @multicastport 1900

  def get_ip do
    _eth0 = to_charlist("eth0")
    en0 = to_charlist("en0")
    {:ok, test_socket} = :inet_udp.open(8989, [])

    ip_addr =
      case :inet.ifget(test_socket, en0, [:addr]) do
        {:ok, [addr: ip]} ->
          ip

        {:ok, []} ->
          {:ok, [addr: ip]} = :prim_inet.ifget(test_socket, en0, [:addr])
          ip
      end

    :inet_udp.close(test_socket)
    {:ok, ip_addr}
  end

  def start_link() do
    GenServer.start_link(__MODULE__, %DiscoverState{}, name: __MODULE__)
  end

  def init(%DiscoverState{} = state) do
    # not really sure why i need an IP, does not seem to work on 0.0.0.0 after some timeout occurs...
    # needs to be passed a interface IP that is the same lan as sonos DLNA multicasts
    {:ok, ip_addr} = get_ip()

    {:ok, socket} =
      :gen_udp.open(0, [
        :binary,
        :inet,
        {:ip, ip_addr},
        {:active, true},
        {:multicast_if, ip_addr},
        {:multicast_ttl, 4},
        {:add_membership, {@multicastaddr, ip_addr}}
      ])

    # fire two udp discover packets immediately
    :gen_udp.send(socket, @multicastaddr, @multicastport, @playersearch)
    :gen_udp.send(socket, @multicastaddr, @multicastport, @playersearch)
    {:ok, %DiscoverState{state | socket: socket}}
  end

  def terminate(_reason, %DiscoverState{socket: socket} = _state) when socket != nil do
    :ok = :gen_udp.close(socket)
  end

  @doc """
  Fires a UPNP discover packet onto the LAN,
  all Sonos devices should respond, refresing player attributes stored in state
  """
  def discover() do
    GenServer.cast(__MODULE__, :discover)
  end

  @doc """
  Retuns a single Sonos Player Struct, or nil of does not exist.
  """
  def playerByName(name) do
    GenServer.call(__MODULE__, {:player_by_name, name})
  end

  def players_in_zone(zone_uuid) do
    GenServer.call(__MODULE__, {:players_in_zone, zone_uuid})
  end

  @doc """
  Retuns a single Sonos Player Struct, or nil of does not exist.
  """
  def zoneByName(name) do
    GenServer.call(__MODULE__, {:zone_by_name, name})
  end

  @doc """
  Retuns a list of all Sonos Device Structs discovered on the LAN
  """
  def players() do
    GenServer.call(__MODULE__, :players)
  end

  @doc """
  Retuns returns number of devices discoverd on lan
  """
  def count() do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Returns true if devices were discovered on lan
  """
  def discovered?() do
    GenServer.call(__MODULE__, :discovered)
  end

  @doc """
  Fires a UPNP discover packet onto the LAN,
  all Sonos devices should respond, refresing player attributes stored in state
  """
  def zones() do
    GenServer.call(__MODULE__, :zones)
  end

  @doc """
  Terminates Sonex.Discovery GenServer
  """
  def kill() do
    GenServer.stop(__MODULE__, "Done")
  end

  def handle_call({:player_by_name, name}, _from, %DiscoverState{players: players_list} = state) do
    res =
      Enum.find(players_list, nil, fn player ->
        player.name == name
      end)

    {:reply, res, state}
  end

  def handle_call(:zones, _from, %DiscoverState{} = state) do
    zone_coordinators =
      Enum.filter(state.players, fn player ->
        player.uuid == player.coordinator_uuid
      end)

    {:reply, zone_coordinators, state}
  end

  def handle_call({:zone_by_name, name}, _from, %DiscoverState{} = state) do
    players_in_zone =
      Enum.filter(state.players, fn player -> player.uuid == player.coordinator_uuid end)
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

  def handle_call({:players_in_zone, uuid}, _from, %DiscoverState{} = state) do
    players_in_zone =
      Enum.filter(state.players, fn p -> uuid == p.coordinator_uuid end)
        |> Enum.reverse()

    {:reply, players_in_zone, state}
  end

  def handle_call(:players, _from, %DiscoverState{} = state) do
    {:reply, state.players, state}
  end

  def handle_call(:count, _from, state) do
    {:reply, state.player_count, state}
  end

  def handle_call(:discovered, _from, state) do
    {:reply, state.player_count > 0, state}
  end

  def handle_cast(:kill, state) do
    :ok = :gen_udp.close(state.socket)
    {:noreply, state}
  end

  def handle_cast(:discover, state) do
    :gen_udp.send(state.socket, @multicastaddr, @multicastport, @playersearch)
    {:noreply, state}
  end

  def handle_info({:udp, socket, ip, _fromport, packet}, state) do
    %DiscoverState{players: players_list} = state
    this_player = parse_upnp(ip, packet)

    return_state =
      {:noreply,
       %DiscoverState{state | players: players_list, player_count: Enum.count(players_list)}}

    return_state =
      if this_player do
        case(knownplayer?(players_list, this_player.uuid)) do
          # Match one
          player_index when is_nil(player_index) == false ->
            {name, icon, config} = attributes(this_player)
            {_, zone_coordinator, _} = group_attributes(this_player)

            updated_player = %SonosDevice{
              this_player
              | name: name,
                icon: icon,
                config: config,
                coordinator_uuid: zone_coordinator
            }

            {:noreply,
             %DiscoverState{
               state
               | players: List.replace_at(players_list, player_index, updated_player)
             }}

          # Match two
          player_index when is_nil(player_index) == true ->
            {name, icon, config} = attributes(this_player)

            if name != "BRIDGE" do
              {_, zone_coordinator, _} = group_attributes(this_player)

              player = %SonosDevice{
                this_player
                | name: name,
                  icon: icon,
                  config: config,
                  coordinator_uuid: zone_coordinator
              }

              # send discovered event
              build(this_player.uuid, this_player.ip, zone_coordinator, name, icon, config)
              |> Sonex.PlayerMonitor.create()

              GenEvent.notify(Sonex.EventMngr, {:discovered, player})
              GenEvent.notify(Sonex.EventMngr, {:start, player})
              # new_players = [this_player | players_list ]
              new_players = [player | players_list]

              {:noreply,
               %DiscoverState{state | players: new_players, player_count: Enum.count(new_players)}}
            else
              {:noreply,
               %DiscoverState{
                 state
                 | players: players_list,
                   player_count: Enum.count(players_list)
               }}
            end
        end
      else
        return_state
      end

    return_state
  end

  defp build(id, ip, coord_id, name, icon, config) do
    new_player = %ZonePlayer{}

    %ZonePlayer{
      new_player
      | id: id,
        name: name,
        coordinator_id: coord_id,
        info: %{
          new_player.info
          | ip: ip,
            icon: icon,
            config: config
        }
    }
  end

  defp knownplayer?(players, uuid) do
    Enum.find_index(players, fn player -> player.uuid == uuid end)
  end

  defp attributes(%SonosDevice{} = player) do
    import SweetXml
    {:ok, res_body} = Sonex.SOAP.build(:device, "GetZoneAttributes") |> Sonex.SOAP.post(player)

    {xpath(res_body, ~x"//u:GetZoneAttributesResponse/CurrentZoneName/text()"s),
     xpath(res_body, ~x"//u:GetZoneAttributesResponse/CurrentIcon/text()"s),
     xpath(res_body, ~x"//u:GetZoneAttributesResponse/CurrentConfiguration/text()"i)}
  end

  defp group_attributes(%SonosDevice{} = player) do
    import SweetXml
    {:ok, res_body} = Sonex.SOAP.build(:zone, "GetZoneGroupAttributes") |> Sonex.SOAP.post(player)

    {zone_name, zone_id, player_list} =
      {xpath(res_body, ~x"//u:GetZoneGroupAttributesResponse/CurrentZoneGroupName/text()"s),
       xpath(res_body, ~x"//u:GetZoneGroupAttributesResponse/CurrentZoneGroupID/text()"s),
       xpath(
         res_body,
         ~x"//u:GetZoneGroupAttributesResponse/CurrentZonePlayerUUIDsInGroup/text()"ls
       )}

    clean_zone =
      case String.split(zone_id, ":") do
        [one, _] ->
          one

        [""] ->
          ""
      end

    case(zone_name) do
      "" ->
        {nil, clean_zone, player_list}

      _ ->
        {zone_name, clean_zone, player_list}
    end
  end

  def zone_group_state(%SonosDevice{} = player) do
    import SweetXml

    {:ok, res} =
      Sonex.SOAP.build(:zone, "GetZoneGroupState", [])
      |> Sonex.SOAP.post(player)

    xpath(res, ~x"//ZoneGroupState/text()"s)
    |> xpath(~x"//ZoneGroups/ZoneGroup"l,
      coordinator_uuid: ~x"//./@Coordinator"s,
      members: [
        ~x"//./ZoneGroup/ZoneGroupMember"el,
        name: ~x"//./@ZoneName"s,
        uuid: ~x"//./@UUID"s,
        addr: ~x"//./@Location"s,
        config: ~x"//./@Configuration"i,
        icon: ~x"//./@Icon"s
      ]
    )
  end

  defp parse_upnp(ip, good_resp) do
    split_resp = String.split(good_resp, "\r\n")
    vers_model = Enum.fetch!(split_resp, 4)

    if String.contains?(vers_model, "Sonos") do
      ["SERVER:", "Linux", "UPnP/1.0", version, model_raw] = String.split(vers_model)
      model = String.lstrip(model_raw, ?() |> String.rstrip(?))
      "USN: uuid:" <> usn = Enum.fetch!(split_resp, 6)
      uuid = String.split(usn, "::") |> Enum.at(0)
      "X-RINCON-HOUSEHOLD: " <> household = Enum.fetch!(split_resp, 7)

      %SonosDevice{
        ip: format_ip(ip),
        version: version,
        model: model,
        uuid: uuid,
        household: household
      }
    end
  end

  defp format_ip({a, b, c, d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end
end
