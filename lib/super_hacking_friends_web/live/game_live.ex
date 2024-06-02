defmodule SuperHackingFriendsWeb.GameLive do
  require Logger
  alias Phoenix.PubSub
  alias SuperHackingFriendsWeb.GamePresence
  alias Game.Run
  alias Game.Run.State
  alias Game.Utils
  import SuperHackingFriendsWeb.CoreComponents
  alias SuperHackingFriendsWeb.Components.Lobby
  alias SuperHackingFriendsWeb.Components.Game
  use SuperHackingFriendsWeb, :live_view

  # :status should be:
  # - :waiting, if they're in a lobby but the game hasn't started
  # - :running, if the game has started
  # - :won
  # - :lost
  # - {:err, reason}, if something went wrong trying to join or start
  #
  # :player_name
  # :room_name
  #
  # :target is the player's current target
  #
  # :commands is their available commands
  #
  # :mode should be:
  # - :join, if the player is joining a game
  # - :new, if they're starting one
  #
  # :players is the list of player info sourced from the Presence module
  #
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       player_name: nil,
       status: :outside,
       game_pid: nil,
       mode: :new,
       players: [],
       room_name: "",
       ready: false,
       target: nil,
       commands: nil
     )}
  end

  def handle_params(%{"room" => room_name}, _uri, socket) do
    {:noreply, assign(socket, room_name: room_name)}
  end

  def handle_params(%{"room" => _, "player" => _} = params, _uri, socket) do
    try_join(params, socket)
  end

  # No-op if there's no `room` param set
  def handle_params(_, _uri, socket), do: {:noreply, socket}

  def handle_event("start", _params, socket) do
    {:ok, %State{status: :running}} = Run.start_game(socket.assigns.game_pid)

    {:noreply, assign(socket, status: :running)}
  end

  def handle_event(
        "ready",
        _params,
        %{assigns: %{room_name: room_name, player_name: player_name, ready: ready}} = socket
      ) do
    topic = Utils.get_topic(room_name)

    GamePresence.update(self(), topic, player_name, fn p ->
      %{p | ready: !ready}
    end)

    {:noreply, assign(socket, ready: !ready)}
  end

  def handle_event(
        "config",
        %{"mode" => "new", "player_name" => player_name, "room_name" => room_name},
        socket
      ) do
    case Run.new_game(%Run.State{
           name: room_name,
           players: %{player_name => %Run.Player{name: player_name, host: true}}
         }) do
      {:ok, pid} ->
        {:noreply,
         assign(socket,
           game_pid: pid,
           status: :waiting,
           player_name: player_name,
           room_name: room_name
         )
         |> connect(room_name, player_name, true)}

      {:error, reason} ->
        {:noreply, assign(socket, status: {:error, reason})}
    end
  end

  def handle_event(
        "config",
        %{"mode" => "join"} = payload,
        socket
      ),
      do: try_join(payload, socket)

  def try_join(
        %{"mode" => "join", "player_name" => player_name, "room_name" => room_name},
        socket
      ) do
    with pid when is_pid(pid) <- Utils.get_pid(room_name),
         {:ok, _state} <- Run.add_lobby_player(pid, player_name) do
      {:noreply,
       assign(socket,
         game_pid: pid,
         status: :waiting,
         player_name: player_name,
         room_name: room_name
       )
       |> connect(room_name, player_name)}
    else
      {:err, reason} -> {:noreply, assign(socket, status: {:error, reason})}
      _ -> {:noreply, assign(socket, status: {:error, :unknown})}
    end
  end

  defp connect(socket, room_name, player_name, host \\ false) do
    topic = Utils.get_topic(room_name)

    PubSub.subscribe(SuperHackingFriends.PubSub, topic)

    {:ok, _} =
      GamePresence.track(self(), topic, player_name, %{
        username: player_name,
        ready: false,
        host: host
      })

    presences = GamePresence.list(topic) |> format_players()

    assign(socket, players: presences)
  end

  defp disconnect(%{assigns: %{room_name: room_name, player_name: player_name}}) do
    topic = Utils.get_topic(room_name)

    GamePresence.untrack(self(), topic, player_name)
  end

  defp format_players(presences) do
    Enum.into(presences, %{}, fn {playername, %{metas: [h | _]}} -> {playername, h} end)
  end

  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    new_socket =
      socket.assigns.players
      |> Map.drop(Map.keys(diff.leaves))
      |> Map.merge(format_players(diff.joins))
      |> (fn ps -> assign(socket, players: ps) end).()

    {:noreply, new_socket}
  end

  def handle_info(
        {:game_start, state},
        %{assigns: %{player_name: player_name, room_name: _room_name}} = socket
      ) do
    commands = Utils.get_player_commands(state, player_name)
    target = Utils.get_player_target(state, player_name)

    {:noreply, assign(socket, status: :running, target: target, commands: commands)}
  end

  def handle_info({:state_update, new_state}, socket) do
    commands = Utils.get_player_commands(new_state, socket.assigns.player_name)
    target = Utils.get_player_target(new_state, socket.assigns.player_name)

    {:noreply, assign(socket, target: target, commands: commands, status: new_state.status)}
  end

  def handle_event(
        "run-cmd",
        %{"cmd" => input},
        %{assigns: %{game_pid: pid, player_name: player_name}} = socket
      ) do
    Run.command(pid, input, player_name)
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div :if={@status == :lost}>
      <.header>YOU LOSE! <.px_icon name="hockey-mask" /></.header>
    </div>
    <div :if={@status == :won}>
      <.header>YOU WIN! <.px_icon name="thumbs-up" /></.header>
    </div>
    <.live_component
      :if={@status != :running}
      module={Lobby}
      id={self()}
      status={@status}
      game_pid={@game_pid}
      players={@players}
      room_name={@room_name}
    />
    <.live_component
      :if={@status == :running}
      module={Game}
      id="game"
      target={@target}
      commands={@commands}
    />
    """
  end

  # Logic
end
