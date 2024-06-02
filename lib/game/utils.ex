defmodule Game.Utils do
  alias Game.Run.State

  def get_topic(room_name), do: "game:#{room_name}"

  def get_pid(room_name), do: :global.whereis_name(room_name)

  def get_player_commands(%State{} = state, player_name) do
    state.players[player_name].commands
  end

  def get_player_target(%State{} = state, player_name) do
    state.players[player_name].target
  end
end
