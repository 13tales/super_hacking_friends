defmodule Game.RunTest do
  use ExUnit.Case
  alias Game.ProcServer
  alias Game.Run

  describe "new_game/0" do
    test "Starts the game server" do
      {:ok, pid} = Run.new_game()

      assert Process.alive?(pid)
      Run.stop(pid)
    end
  end

  describe "add_player/2" do
    test "Adds a player when the name is unique" do
      {_, state} =
        %Run.State{}
        |> Run.add_player("player1")
        |> (fn {:ok, state} -> Run.add_player(state, "player2") end).()

      assert Enum.count(state.players) == 2
    end

    test "Fails to add a player when the name already exists" do
      {:ok, state} = Run.add_player(%Run.State{}, "player1")
      {:err, :exists} = Run.add_player(state, "player1")
    end
  end

  describe "remove_lobby_player/2" do
    test "Removes a player" do
      {:ok, pid} = Run.new_game()
      assert Process.alive?(pid)

      {:ok, _state} = Run.add_lobby_player(pid, "player1")
      {:ok, state} = Run.add_lobby_player(pid, "player2")

      assert Enum.count(state.players) == 2

      {:ok, state} = Run.remove_lobby_player(pid, "player1")
      assert Enum.count(state.players) == 1

      Run.stop(pid)
    end
  end

  describe "start_game/1" do
    test "Sets running to true when the game starts" do
      {:ok, pid} = Run.new_game()
      assert Process.alive?(pid)

      {:ok, _state} = Run.add_lobby_player(pid, "player1")
      {:ok, _state} = Run.add_lobby_player(pid, "player2")

      {:ok, state} = Run.start_game(pid)
      assert state.running == true

      Run.stop(pid)
    end

    test "Every player has a non-nil target after the game starts" do
      {:ok, pid} = Run.new_game()
      assert Process.alive?(pid)

      {:ok, _state} = Run.add_lobby_player(pid, "player1")
      {:ok, _state} = Run.add_lobby_player(pid, "player2")
      {:ok, _state} = Run.add_lobby_player(pid, "player3")

      {:ok, state} = Run.start_game(pid)
      assert state.running == true

      Enum.each(state.players, fn {_, player} ->
        assert player.target != nil
      end)

      Run.stop(pid)
    end

    test "All targets in state.all_targets match player targets" do
      {:ok, pid} = Run.new_game()
      assert Process.alive?(pid)

      {:ok, _state} = Run.add_lobby_player(pid, "player1")
      {:ok, _state} = Run.add_lobby_player(pid, "player2")
      {:ok, _state} = Run.add_lobby_player(pid, "player3")

      {:ok, state} = Run.start_game(pid)
      assert state.running == true

      player_targets =
        Enum.map(state.players, fn {_, player} -> player.target end) |> MapSet.new()

      assert Enum.sort(
               state.all_targets
               |> Map.values()
               |> Enum.map(&elem(&1, 0))
               |> MapSet.new()
             ) ==
               Enum.sort(player_targets)

      Run.stop(pid)
    end

    test "state.all_commands is equal to the superset of every player's :commands value" do
      {:ok, pid} = Run.new_game()
      assert Process.alive?(pid)

      {:ok, _state} = Run.add_lobby_player(pid, "player1")
      {:ok, _state} = Run.add_lobby_player(pid, "player2")
      {:ok, _state} = Run.add_lobby_player(pid, "player3")

      {:ok, state} = Run.start_game(pid)
      assert state.running == true

      player_commands =
        Enum.flat_map(state.players, fn {_, player} -> player.commands end) |> MapSet.new()

      assert MapSet.equal?(MapSet.new(state.all_commands), player_commands)

      Run.stop(pid)
    end

    test "Every player target is a command belonging to another player" do
      {:ok, pid} = Run.new_game()
      assert Process.alive?(pid)

      {:ok, _state} = Run.add_lobby_player(pid, "player1")
      {:ok, _state} = Run.add_lobby_player(pid, "player2")
      {:ok, _state} = Run.add_lobby_player(pid, "player3")

      {:ok, state} = Run.start_game(pid)
      assert state.running == true

      player_commands =
        Enum.flat_map(state.players, fn {_, player} ->
          Enum.map(player.commands, &elem(&1, 1))
        end)
        |> MapSet.new()

      Enum.each(state.players, fn {_, player} ->
        assert MapSet.member?(player_commands, player.target)
      end)

      Run.stop(pid)
    end
  end

  describe "assign_new_target/2" do
    test "Assigns a new target that is a command belonging to another player" do
      {:ok, pid} = Run.new_game()
      assert Process.alive?(pid)

      {:ok, _state} = Run.add_lobby_player(pid, "player1")
      {:ok, _state} = Run.add_lobby_player(pid, "player2")
      {:ok, _state} = Run.add_lobby_player(pid, "player3")

      {:ok, state} = Run.start_game(pid)
      assert state.running == true

      state = Run.assign_new_target(state, "player1")

      player_commands =
        Enum.flat_map(state.players, fn {_, player} ->
          Enum.map(player.commands, &elem(&1, 1))
        end)
        |> MapSet.new()

      player1 = state.players["player1"]
      assert MapSet.member?(player_commands, player1.target)

      Run.stop(pid)
    end

    test "New target is stored in state.all_targets with correct tuple format" do
      {:ok, pid} = Run.new_game()
      assert Process.alive?(pid)

      {:ok, _state} = Run.add_lobby_player(pid, "player1")
      {:ok, _state} = Run.add_lobby_player(pid, "player2")
      {:ok, _state} = Run.add_lobby_player(pid, "player3")

      {:ok, state} = Run.start_game(pid)
      assert state.running == true

      state = Run.assign_new_target(state, "player1")

      player1 = state.players["player1"]
      target_tuple = {player1.target, "player1"}

      assert Map.get(state.all_targets, Proc.format(player1.target)) == target_tuple

      Run.stop(pid)
    end
  end
end
