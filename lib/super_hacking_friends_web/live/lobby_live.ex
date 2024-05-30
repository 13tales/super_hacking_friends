defmodule SuperHackingFriendsWeb.LobbyLive do
  alias Phoenix.PubSub
  alias SuperHackingFriendsWeb.GamePresence
  alias Game.Run
  use SuperHackingFriendsWeb, :live_view

  # :status should be:
  # - :outside, if the player isn't in a lobby yet
  # - :waiting, if they're in a lobby but the game hasn't started
  # - {:err, reason}, if something went wrong trying to join or start
  #
  # :player name
  #
  # :mode should be:
  # - :join, if the player is joining a game
  # - :new, if they're starting one
  #
  # :players is the list of player info sourced from the Presence module
  #
  def mount(_params, _session, socket) do
    {:ok, assign(socket, player_name: nil, status: :outside, game_pid: nil, mode: :new)}
  end

  # def handle_params(%{"room" => room_name}, _uri, socket) do
  #   case :global.whereis_name(room_name) do
  #     :undefined ->
  #       {:noreply, socket}

  #     pid ->
  #       assign(socket, game_pid: pid)
  #   end
  # end

  # No-op if there's no `room` param set
  def handle_params(_, _uri, socket), do: {:noreply, socket}

  def handle_event(
        "config",
        %{"mode" => "new", "player_name" => player_name, "room_name" => room_name},
        socket
      ) do
    case Run.new_game(%Run.State{
           name: room_name,
           players: %{player_name => %Run.Player{name: player_name}}
         }) do
      {:ok, pid} ->
        {:noreply,
         assign(socket, game_pid: pid, status: :waiting, player_name: player_name)
         |> connect(room_name, player_name)}

      {:error, reason} ->
        {:noreply, assign(socket, status: {:error, reason})}
    end
  end

  def handle_event(
        "config",
        %{"mode" => "join", "player_name" => player_name, "room_name" => room_name},
        socket
      ) do
    with pid when is_pid(pid) <- :global.whereis_name(room_name),
         {:ok, _state} <- Run.add_lobby_player(pid, player_name) do
      {:noreply,
       assign(socket, game_pid: pid, status: :waiting, player_name: player_name)
       |> connect(room_name, player_name)}
    else
      {:err, reason} -> {:noreply, assign(socket, status: {:error, reason})}
      _ -> {:noreply, assign(socket, status: {:error, :unknown})}
    end
  end

  defp get_topic(room_name), do: "game:#{room_name}"

  defp connect(socket, room_name, player_name) do
    topic = get_topic(room_name)

    PubSub.subscribe(SuperHackingFriends.PubSub, topic)
    {:ok, _} =
      GamePresence.track(self(), topic, player_name, %{
        username: player_name,
        ready: false
      })

    presences = GamePresence.list(topic) |> format_players()

    assign(socket, players: presences)
  end

  defp disconnect(%{assigns: %{room_name: room_name, player_name: player_name}}) do
    topic = get_topic(room_name)

    GamePresence.untrack(self(), topic, player_name)
  end

  def format_players(presences) do
    Enum.into(presences, %{}, fn {playername, %{metas: [h | _]}} -> {playername, h} end)
  end

  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    new_socket = socket.assigns.players
      |> Map.drop(Map.keys(diff.leaves))
      |> Map.merge(format_players(diff.joins))
      |> fn (ps) -> assign(socket, players: ps) end.()

    {:noreply, new_socket}
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
          <input type="radio" id="mode_new" name="mode" value="new" checked /> New game
        </label>
        <label for="mode_join">
          <input type="radio" id="mode_join" name="mode" value="join" /> Join game
        </label>
        <label for="room_name">Room name:</label>
        <input type="text" id="room_name" name="room_name" required />
        <label for="player_name">Player name:</label>
        <input type="text" id="player_name" name="player_name" required />
        <button type="submit">Submit</button>
      </form>
    <% else %>
      <div>
        <h2>Current Players</h2>
        <ul>
          <li :for={{name, %{ready: ready}} <- @players}><%= name %>, ready: <%= ready %></li>
        </ul>
      </div>
    <% end %>
    """
  end

  # Logic
end
