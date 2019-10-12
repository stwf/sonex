defmodule Sonex do
  
  def get_zones do
    Sonex.Discovery.zones()
  end
end
