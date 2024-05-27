defmodule SuperHackingFriendsWeb.LobbyLive do
  alias Game.Run
  use SuperHackingFriendsWeb, :live_view

  # :status should be:
  # - :outside, if the player isn't in a lobby yet
  # - :waiting, if they're in a lobby but the game hasn't started
  # - {:err, reason}, if something went wrong trying to join or start
  #
  # :mode should be:
  # - :join, if the player is joining a game
  # - :new, if they're starting one
  #
  # :players should be a list of player names
  def mount(_params, _session, socket) do
    {:ok, assign(socket, player_name: nil, status: :outside, game_pid: nil, mode: :new)}
  end

  def handle_params(%{ "room" => room_name }, _uri, socket) do
    case :global.whereis_name(room_name) do
      :undefined -> {:noreply, socket}
      pid ->
        assign(socket, game_pid: pid)
    end
  end

  # No-op if there's no `room` param set
  def handle_params(_, _uri, socket), do: {:noreply, socket}

  def handle_event("config", %{ "mode" => "new", "player_name" => player_name, "room_name" => room_name }, socket) do
    case Run.new_game(%Run.State{ name: room_name, players: %{ player_name => %Run.Player{ name: player_name }}}) do
      {:ok, pid} ->
        {:noreply, assign(socket, game_pid: pid, status: :waiting) }

      {:error, reason} ->
        {:noreply, assign(socket, status: {:error, reason})}
    end
  end

  def handle_event("config", %{ "mode" => "join", "player_name" => player_name, "room_name" => room_name }, socket) do
    with pid when is_pid(pid) <- :global.whereis_name(room_name),
      {:ok, _state} <- Run.add_lobby_player(pid, player_name) do
        {:noreply, assign(socket, game_pid: pid, status: :waiting)}
    else
      {:err, reason} -> {:noreply, assign(socket, status: {:error, reason})}
      _ -> {:noreply, assign(socket, status: {:error, :unknown})}
    end
  end

  def render(assigns) do
    ~H"""
    <h1>Lobby</h1>
    <div>
      <p>Status: <%= inspect(@status) %></p>
    </div>
    <%= if @game_pid == nil do %>
      <form class="grid max-w-prose" phx-submit="config">
        <label for="mode_new">
          <input type="radio" id="mode_new" name="mode" value="new" checked>
          New game
        </label>
        <label for="mode_join">
          <input type="radio" id="mode_join" name="mode" value="join">
          Join game
        </label>
        <label for="room_name">Room name:</label>
        <input type="text" id="room_name" name="room_name" required />
        <label for="player_name">Player name:</label>
        <input type="text" id="player_name" name="player_name" required />
        <button type="submit">Submit</button>
      </form>
    <% end %>
    """
  end

  # Logic
end
