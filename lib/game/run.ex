defmodule Game.Run do
  defmodule Player do
    defstruct name: "", commands: Map.new(), hits: 0, misses: 0, target: nil, host: false
  end

  defmodule State do
    defstruct players: %{},
              # :waiting, :running, :won, :lost
              status: :waiting,
              life: 100,
              finish_at: nil,
              all_targets: Map.new(),
              all_commands: Map.new(),
              name: "",
              procserver: nil,
              topic: nil
  end

  @reward 5
  @damage 20
  @command_interval :timer.seconds(10)
  @max_level 10
  @run_length :timer.seconds(120)
  @hand_limit 9

  require Logger
  import Access, only: [key!: 1]
  alias Phoenix.PubSub
  alias Game.ProcServer.Proc
  alias Game.ProcServer
  alias Game.Utils
  use GenServer

  # Interface
  def new_game(%State{name: name} = init_state \\ %State{}) do
    {:ok, pid} = ProcServer.start()
    GenServer.start(__MODULE__, %State{init_state | procserver: pid}, name: {:global, name})
  end

  def start_game(pid) do
    GenServer.call(pid, :start_game)
  end

  def add_lobby_player(pid, name, host \\ false) do
    GenServer.call(pid, {:add_player, name, host})
  end

  def remove_lobby_player(pid, name) do
    GenServer.call(pid, {:remove_player, name})
  end

  def command(pid, input, player_name) do
    GenServer.cast(pid, {:command, input, player_name})
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  # Callbacks
  def init(%State{} = init_state \\ %State{}) do
    topic = Utils.get_topic(init_state.name)
    PubSub.subscribe(SuperHackingFriends.PubSub, topic)

    {:ok, %State{init_state | topic: topic}}
  end

  def handle_call({:add_player, new_player, host}, _from, %State{} = state) do
    case add_player(state, new_player, host) do
      {:ok, new_state} -> {:reply, {:ok, new_state}, new_state}
      {:err, reason} -> {:reply, {:err, reason}, state}
    end
  end

  def handle_call({:remove_player, name}, _from, %State{} = state) do
    new_state = remove_player(state, name)
    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call(:start_game, _from, %State{} = state) do
    finish_time = DateTime.utc_now() |> DateTime.add(@run_length, :millisecond)

    new_state =
      %State{state | status: :running, finish_at: finish_time}
      |> deal_all()
      |> assign_all()

    :timer.send_interval(@run_length, :tick)

    Logger.info("Starting game with name: #{state.name}")

    # TODO: Replace with the generic broadcast message
    PubSub.broadcast(
      SuperHackingFriends.PubSub,
      state.topic,
      {:game_start, new_state}
    )

    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call(:get_state, _from, %State{} = state) do
    {:reply, state, state}
  end

  def handle_cast({:command, input, player_name}, _from, %State{} = state) do
    case handle_input(state, player_name, input) do
      {_result, %State{life: 0} = new_state} ->
        Logger.info("Game over! Players lose!")
        {:noreply, new_state |> broadcast_new_state}

      {result, new_state} ->
        {:noreply, new_state |> broadcast_new_state}
    end
  end

  def handle_info({:proc_timeout, target}, %State{} = state) do
    Logger.info("Timeout for target: #{Proc.format(target)}")
    target_key = Proc.format(target)

    new_state =
      case check_target_match(state, target_key) do
        {:match, owner, _old_target} ->
          state
          |> damage(@damage)
          |> assign_new_target(owner)

        :nomatch ->
          state
      end

    {:noreply, new_state |> broadcast_new_state}
  end

  def handle_info(:tick, %State{} = state) do
    Logger.info("Tick")

    if DateTime.after?(DateTime.utc_now(), state.finish_at) && state.status == :running do
      IO.puts("You win! Life remaining: #{state.life}")

      {:noreply, %State{state | status: :won} |> broadcast_new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        %{event: "presence_diff", payload: %{joins: _joins, leaves: leaves}},
        %State{} = state
      ) do
    # new_state = Enum.reduce(leaves, state, fn {name, _}, acc -> remove_player(acc, name) end)

    # Logger.info("Players updated. New state: #{inspect Map.values(new_state.players)}")
    # if Enum.count(new_state.players) == 0 do
    #   Logger.info("Stopping #{new_state.name} because last player left.")
    #   {:stop, :normal, new_state}
    # else
    #   {:noreply, new_state}
    # end
    {:noreply, state}
  end

  def handle_info(:game_start, %State{} = state) do
    {:noreply, state}
  end

  def handle_info(msg, %State{} = state) do
    # Logger.warning("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Game logic

  def broadcast_new_state(%State{topic: topic} = state) do
    PubSub.broadcast!(SuperHackingFriends.PubSub, topic, {:state_update, state})

    state
  end

  # Remove a player from the game
  def remove_player(%State{} = state, name) do
    Map.update!(state, :players, &Map.delete(&1, name))
  end

  # Add a player to the game
  def add_player(%State{} = state, new_name, host \\ false) do
    case state do
      %State{status: :running} ->
        {:err, :in_progress}

      %State{status: _, players: players} when is_map_key(players, new_name) ->
        {:err, :exists}

      %State{status: _} ->
        new_state = put_in(state, [key!(:players), new_name], %Player{name: new_name, host: host})
        {:ok, new_state}
    end
  end

  # Deal random commands to all players, up to the hand limit
  def deal_all(%State{procserver: procserver} = state) do
    new_players =
      for {name, data} <- state.players, into: %{} do
        {name,
         %{
           data
           | commands:
               Map.new(1..@hand_limit, fn _ ->
                 cmd = ProcServer.pick(procserver, @max_level)
                 {Proc.format(cmd), cmd}
               end)
         }}
      end

    command_pool =
      Enum.reduce(new_players, %{}, fn {_name, player}, acc -> Map.merge(player.commands, acc) end)

    %{state | players: new_players, all_commands: command_pool}
  end

  # Assign targets for all players
  def assign_all(%State{players: players, all_commands: all_commands} = state) do
    new_players =
      players
      |> Enum.map(fn {name, data} ->
        {_, new_target} = Enum.random(all_commands)
        {name, %{data | target: new_target}}
      end)
      |> Map.new()

    new_target_pool =
      Map.values(new_players)
      |> Enum.map(fn %Player{target: target, name: player_name} ->
        {Proc.format(target), {target, player_name}}
      end)
      |> Map.new()

    # For each new target; send a timeout message after the designated interval
    for {_key, {new_target, _name}} <- new_target_pool do
      Process.send_after(self(), {:proc_timeout, new_target}, @command_interval)
    end

    %{state | players: new_players, all_targets: new_target_pool}
  end

  # Subtract health
  def damage(%State{} = state, hit) when is_integer(hit) do
    new_life = max(0, state.life - hit)

    status =
      if new_life == 0 do
        :lost
      else
        state.status
      end

    Logger.info("Damage taken: #{hit}, new life value: #{new_life}")
    %State{state | life: new_life, status: status}
  end

  # Increase health/score
  def score(%State{} = state, points) when is_integer(points),
    do: Map.update(state, :life, 0, &min(100, &1 + points))

  # Pick a new random target for the specified player name
  def assign_new_target(%State{} = state, player_name)
      when is_map_key(state.players, player_name) do
    current_target = get_in(state, [key!(:players), player_name, key!(:target)])

    {new_key, new_target} = Enum.random(state.all_commands)

    Logger.info("New target for #{player_name}: #{new_key}")

    new_state =
      put_in(state, [key!(:players), player_name, key!(:target)], new_target)
      |> Map.update!(:all_targets, fn ts ->
        Map.delete(ts, Proc.format(current_target))
        |> Map.put(new_key, {new_target, player_name})
      end)

    Process.send_after(self(), {:proc_timeout, new_target}, @command_interval)

    new_state
  end

  # Check if a typed command matches a proc data structure
  def input_matches_proc(proc, input)
      when is_binary(input) do
    target = Proc.format(proc)

    clean_input = input |> String.downcase() |> String.trim() |> String.replace("_", " ")

    String.equivalent?(target, clean_input)
  end

  # Replace a command belonging to a named player
  def replace_player_command(
        %State{procserver: procserver} = state,
        %Proc{} = command,
        player_name
      )
      when is_map_key(state.players, player_name) do
    current_key = Proc.format(command)
    new_command = ProcServer.pick(procserver, @max_level)
    new_key = Proc.format(new_command)

    state
    |> update_in([Access.key!(:players), player_name, Access.key!(:commands)], fn cs ->
      cs |> Map.delete(current_key) |> Map.put(new_key, new_command)
    end)
    |> update_in([:all_commands], fn cs ->
      cs |> Map.delete(current_key) |> Map.put(new_key, new_command)
    end)
  end

  # Check if a typed command matches *any* current target, and return the name of the player it belongs to
  def check_target_match(%State{all_targets: target_pool} = state, input) when is_binary(input) do
    clean_input = input |> String.downcase() |> String.trim() |> String.replace("_", " ")

    case Map.get(target_pool, clean_input) do
      {target, player_name} ->
        {:match, player_name, target}

      nil ->
        :nomatch
    end
  end

  # Respond to an input event from a player
  def handle_input(%State{players: players} = state, player_name, input)
      when is_binary(input) and is_map_key(players, player_name) do
    case check_target_match(state, input) do
      {:match, owner, command} ->
        new_state =
          state
          |> score(@reward)
          |> replace_player_command(command, player_name)
          |> assign_new_target(owner)

          Logger.info("Matched! New state: #{new_state}")

        {:match, new_state}

      :nomatch ->
        new_state = damage(state, @damage)

        Logger.info("No match! New state: #{new_state}")
        {:nomatch, new_state}
    end
  end
end
