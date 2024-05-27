defmodule Game.ProcServer do
  defmodule Proc do
    defstruct noun: "", verb: "", modifier: "", arg: nil

    def format(%{} = proc, screen \\ false) do
      "#{proc.verb} #{if screen do
        "the "
      else
        ""
      end}#{if Map.has_key?(proc, :modifier) do
        proc.modifier <> " "
      else
        ""
      end}#{proc.noun}"
      |> String.downcase()
    end
  end

  use GenServer

  @fragments File.read!("lib/game/fragments.json") |> Jason.decode!(keys: :atoms)
  @complete_phrases File.read!("lib/game/phrases.json") |> Jason.decode!(keys: :atoms)

  # Interface

  def start() do
    GenServer.start_link(__MODULE__, %{})
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  def pick(pid, max_level) do
    GenServer.call(pid, {:pick, max_level})
  end

  # Callbacks

  @impl true
  def init(_arg) do
    {:ok, %{used: MapSet.new()}}
  end

  @impl true
  def handle_call({:pick, level}, _from, %{used: used} = state) do
    phrase = get_new(level, used)

    {:reply, phrase, %{state | used: MapSet.put(used, phrase)}}
  end

  @impl true
  def handle_info(msg, state) do
    IO.puts("Unexpected msg received: #{inspect(msg)}")

    {:noreply, state}
  end

  # Logic

  def get_new(max_level, used) do
    phrase = generate(max_level)

    case MapSet.member?(used, phrase) do
      false -> phrase
      true -> get_new(max_level, used)
    end
  end

  def generate(max_level) do
    actual_level = Enum.random(1..max_level)
    lengths = word_lengths(actual_level)

    types =
      if Enum.count(lengths) == 2 do
        [:verb, :noun]
      else
        [:verb, :modifier, :noun]
      end

    Enum.zip_reduce([types, lengths], %{}, fn [type, length], acc ->
      Map.get(@fragments, type)
      |> Map.get(length)
      |> Enum.random()
      |> String.downcase()
      |> (fn w -> Map.put(acc, type, w) end).()
    end)
  end

  def word_lengths(difficulty) when difficulty >= 1 and difficulty <= 15 do
    result =
      case difficulty do
        1 -> [:short, :short]
        2 -> [:short, :mid]
        3 -> [:short, :long]
        4 -> [:mid, :mid]
        5 -> [:mid, :long]
        6 -> [:long, :long]
        7 -> [:short, :long]
        8 -> [:short, :short, :short]
        9 -> [:short, :short, :mid]
        10 -> [:short, :mid, :mid]
        11 -> [:mid, :mid, :mid]
        12 -> [:short, :mid, :long]
        13 -> [:mid, :mid, :long]
        14 -> [:mid, :long, :long]
        15 -> [:long, :long, :long]
      end

    Enum.shuffle(result)
  end
end
