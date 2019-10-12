defmodule Sonex.DefaultHandler do
  use GenEvent
  require Logger

  def init(args) do
    Logger.info("Event handler added!")
    {:ok, args}
  end

  def handle_event({:test, msg}, state) do
    Logger.info("test event received: #{msg}")
    {:ok, state}
  end

  def handle_event({:start, device}, state) do
    Logger.info("start event received: #{inspect(device)}")

    {:ok, state}
  end

  def handle_event({:discovered, %ZonePlayer{} = new_device}, state) do
    Logger.info("discovered device! #{inspect(new_device)}")
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:renderer))
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:zone))
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:av))
    # Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:device))
    # is this device a coordinator?
    # case(new_device.uuid == new_device.coordinator_uuid) do
    {:ok, state}
  end

  def handle_event({:discovered, %SonosDevice{} = new_device}, state) do
    Logger.info("discovered device! #{inspect(new_device)}")
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:renderer))
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:zone))
    Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:av))
    # Sonex.SubMngr.subscribe(new_device, Sonex.Service.get(:device))
    # is this device a coordinator?
    # case(new_device.uuid == new_device.coordinator_uuid) do
    {:ok, state}
  end
end

defmodule Sonex.EventMngr do
  def start_link() do
    {:ok, pid} = GenEvent.start_link(name: __MODULE__)
    GenEvent.add_handler(__MODULE__, Sonex.DefaultHandler, [])
    {:ok, pid}
  end

  def add_handler(handler) do
    GenEvent.add_handler(__MODULE__, handler, [])
  end
end
