defmodule SuperHackingFriendsWeb.Components.Game do
  alias Game.ProcServer.Proc
  use Phoenix.LiveComponent
  import SuperHackingFriendsWeb.CoreComponents

  def render(assigns) do
    ~H"""
    <div>
      <.header>Target</.header>
      <.target proc={@target} />
      <.header>Commands</.header>
      <.commands commands={@commands} />
      <form class="terminal-wrapper" phx-submit="run-cmd">
        <input name="cmd" class="terminal-input" />
      </form>
    </div>
    """
  end

  attr :proc, :map, required: true

  def target(assigns) do
    ~H"""
    <div><%= Proc.format(@proc, true) %></div>
    """
  end

  attr :commands, :map, required: true

  def commands(assigns) do
    ~H"""
    <ul class="commands">
      <%= if @commands do %>
        <li class="border border-amber-400 p-2 m-3" :for={{_key, cmd} <- @commands}>
          <%= Proc.format(cmd, false) |> String.replace(" ", "_") %>()
        </li>
      <% end %>
    </ul>
    """
  end
end
