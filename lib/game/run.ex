defmodule Game.Run do
  defmodule Player do
    defstruct name: "", commands: Map.new(), hits: 0, misses: 0, target: nil
  end

  defmodule State do
    defstruct players: %{},
              running: false,
              life: 100,
              finish_at: nil,
              all_targets: Map.new(),
              all_commands: Map.new()
  end

  @reward 5
  @damage 5
  @command_interval :timer.seconds(6)
  @max_level 10
  @run_length :timer.seconds(30)
  @hand_limit 9

  require Logger
  import Access, only: [key!: 1]
  alias Game.ProcServer.Proc
  alias Game.ProcServer
  use GenServer

  # Interface
  def new_game(%State{} = init_state \\ %State{}) do
    ProcServer.start()
    GenServer.start(__MODULE__, init_state)
  end

  def start_game(pid) do
    GenServer.call(pid, :start_game)
  end

  def add_lobby_player(pid, name) do
    GenServer.call(pid, {:add_player, name})
  end

  def remove_lobby_player(pid, name) do
    GenServer.call(pid, {:remove_player, name})
  end

  def command(pid, input) do
    GenServer.call(pid, {:command, input})
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  # Callbacks
  def init(%State{} = init_state \\ %State{}) do
    {:ok, init_state}
  end

  def handle_call({:add_player, new_player}, _from, state) do
    case add_player(state, new_player) do
      {:ok, new_state} -> {:reply, {:ok, new_state}, new_state}
      {:err, reason} -> {:reply, {:err, reason}, state}
    end
  end

  def handle_call({:remove_player, name}, _from, state) do
    new_state = remove_player(state, name)
    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call(:start_game, _from, state) do
    finish_time = DateTime.utc_now() |> DateTime.add(@run_length, :millisecond)

    new_state =
      %{state | running: true, finish_at: finish_time}
      |> deal_all()
      |> assign_all()

    :timer.send_interval(@run_length, :tick)

    {:reply, {:ok, new_state}, new_state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:command, input, player_name}, _from, state) do
    case handle_input(state, player_name, input) do
      {_result, %State{life: 0} = new_state} ->
        Logger.info("Game over! Players lose!")
        {:stop, :normal, :game_lost, new_state}

      {result, new_state} ->
        {:reply, result, new_state}
    end
  end

  def handle_info({:proc_timeout, target}, %State{} = state) do
    Logger.info("Timeout for target: #{ProcServer.format(target)}")
    target_key = ProcServer.format(target)

    case check_target_match(state, target_key) do
      {:match, owner, _old_target} ->
        state
        |> damage(@damage)
        |> assign_new_target(owner)

      :nomatch ->
        state
    end
  end

  def handle_info(:tick, state) do
    Logger.info("Tick")

    if DateTime.after?(DateTime.utc_now(), state.finish_at) do
      IO.puts("You win! Life remaining: #{state.life}")

      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  # Game logic

  # Remove a player from the game
  def remove_player(state, name) do
    Map.update!(state, :players, &Map.delete(&1, name))
  end

  # Add a player to the game
  def add_player(state, new_name) do
    case state do
      %{running: false, players: players} when is_map_key(players, new_name) ->
        {:err, :exists}

      %{running: false} ->
        new_state = put_in(state, [key!(:players), new_name], %Player{name: new_name})
        {:ok, new_state}

      %{running: true} ->
        {:err, :in_progress}
    end
  end

  # Deal random commands to all players, up to the hand limit
  def deal_all(%State{} = state) do
    new_players =
      for {name, data} <- state.players, into: %{} do
        {name,
         %{
           data
           | commands:
               Map.new(1..@hand_limit, fn _ ->
                 cmd = ProcServer.pick(@max_level)
                 {ProcServer.format(cmd), cmd}
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
        {ProcServer.format(target), {target, player_name}}
      end)
      |> Map.new()

    # For each new target; send a timeout message after the designated interval
    for {_key, {new_target, _name}} <- new_target_pool do
      Process.send_after(self(), {:proc_timeout, new_target}, @command_interval)
    end

    %{state | players: new_players, all_targets: new_target_pool}
  end

  # Subtract health
  def damage(%State{} = state, hit) when is_integer(hit),
    do: Map.update(state, :life, 0, &max(0, &1 - hit))

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
        Map.delete(ts, ProcServer.format(current_target))
        |> Map.put(new_key, {new_target, player_name})
      end)

    Process.send_after(self(), {:proc_timeout, new_target}, @command_interval)

    new_state
  end

  # Check if a typed command matches a proc data structure
  def input_matches_proc(proc, input)
      when is_binary(input) do
    target = ProcServer.format(proc)

    clean_input = input |> String.downcase() |> String.trim() |> String.replace("_", " ")

    String.equivalent?(target, clean_input)
  end

  # Replace a command belonging to a named player
  def replace_player_command(%State{} = state, %Proc{} = command, player_name)
      when is_map_key(state.players, player_name) do
    current_key = ProcServer.format(command)
    new_command = ProcServer.pick(@max_level)
    new_key = ProcServer.format(new_command)

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

        {:match, new_state}

      :nomatch ->
        new_state = damage(state, @damage)

        {:nomatch, new_state}
    end
  end
end
