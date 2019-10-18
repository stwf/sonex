defmodule Sonex.EventMngr do
  use GenServer
  require Logger

  def start_link(_vars) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end


  def init(args) do
    {:ok, _} = Registry.register(Sonex, "devices", [])

    {:ok, args}
  end

   def handle_event({:test, msg}, state) do
    Logger.info("test event received: #{msg}")
    {:ok, state}
  end

  def handle_event({:execute, device}, state) do
   Logger.info("execute event received: #{inspect(device.name)}")

   {:ok, state}
 end

 def handle_info({:start, device}, state) do
  Logger.info("start event received: #{inspect(device.name)}")

  {:noreply, state}
end

def handle_info({:discovered, %ZonePlayer{} = new_device}, state) do
    Logger.info("discovered device! #{inspect new_device.name}")
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:renderer))
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:zone))
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:av))
    #Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:device))
    #is this device a coordinator?
    #case(new_device.uuid == new_device.coordinator_uuid) do
    {:noreply, state}
  end

  def handle_info({:discovered, %SonosDevice{} = new_device}, state) do
    Logger.info("discovered device! #{inspect new_device.name}")
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:renderer))
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:zone))
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:av))
    #Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:device))
    #is this device a coordinator?
    #case(new_device.uuid == new_device.coordinator_uuid) do
    {:noreply, state}
  end
end
