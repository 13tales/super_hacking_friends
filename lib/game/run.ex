defmodule Game.Run do
  defmodule State do
    defstruct player_count: 1, life: 100, ms_words: nil, finish_at: nil, target: nil
  end

  @reward 5
  @damage 5
  @command_interval :timer.seconds(6)
  @max_level 10
  @run_length :timer.seconds(30)

  alias Game.ProcServer
  use GenServer

  # Interface
  def start(%State{} = init_state \\ %State{}) do
    ProcServer.start()
    GenServer.start(__MODULE__, init_state, name: __MODULE__)
  end

  def command(input) do
    GenServer.call(__MODULE__, {:command, input})
  end

  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  def stop() do
    GenServer.stop(__MODULE__)
  end

  # Callbacks
  def init(%State{} = init_state \\ %State{}) do
    finish_time = DateTime.utc_now() |> DateTime.add(@run_length, :millisecond)

    :timer.send_interval(@run_length, :tick)

    {:ok, %{init_state | finish_at: finish_time} |> set_new_target()}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:command, input}, _from, state) do
    case run_proc(state, input) do
      {_result, %State{life: 0} = new_state} ->
        {:stop, :normal, :game_lost, new_state}

      {result, new_state} ->
        {:reply, result, new_state |> set_new_target()}
    end
  end

  def handle_info({:proc_timeout, target}, %State{target: current} = state) do
    case target == current do
      true ->
        IO.puts("Timeout!")

        {:noreply,
         damage(state, @damage)
         |> set_new_target()}

      false ->
        {:noreply, state}
    end
  end

  def handle_info(:tick, state) do
    if DateTime.after?(DateTime.utc_now(), state.finish_at) do
      IO.puts("You win! Life remaining: #{state.life}")

      {:stop, :normal, state }
    else
      {:noreply, state}
    end
  end

  # Game logic

  def damage(%State{} = state, hit) when is_integer(hit),
    do: Map.update(state, :life, 0, &max(0, &1 - hit))

  def score(%State{} = state, points) when is_integer(points),
    do: Map.update(state, :life, 0, &min(100, &1 + points))

  def set_new_target(%State{} = state) do
    new_target = ProcServer.pick(@max_level)

    Process.send_after(self(), {:proc_timeout, new_target}, @command_interval)

    IO.puts("New target: #{ProcServer.format(new_target, true)}")

    %{state | target: new_target}
  end

  def check_command(proc, input)
      when is_binary(input) do
    target = ProcServer.format(proc)

    clean_input = input |> String.downcase() |> String.trim() |> String.replace("_", " ")

    String.equivalent?(target, clean_input)
  end

  def run_proc(%State{target: target} = state, command) when is_binary(command) do
    case check_command(target, command) do
      true ->
        IO.puts(
          "Succeeded! Target: #{ProcServer.format(target)}, Input: #{command}, Reward: #{@reward}"
        )

        {:success, score(state, @reward)}

      false ->
        IO.puts(
          "Failed! Target: #{ProcServer.format(target)}, Input: #{command}, Damage: #{@damage}"
        )

        {:failure, damage(state, @damage)}
    end
  end
end
