defmodule SuperHackingFriendsWeb.Components.Lobby do
  use Phoenix.LiveComponent
  import SuperHackingFriendsWeb.CoreComponents

  @impl true
  def mount(socket) do
    {:ok, assign(socket, mode: "new", room_name: "", player_name: "")}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp all_ready?(players) do
    Enum.all?(players, fn {_name, %{ready: ready}} -> ready == true end)
  end

  def render(assigns) do
    ~H"""
    <div class="h-full w-full" id="lobby">
      <%= if @game_pid == nil do %>
        <.game_details mode={@mode} />
      <% else %>
        <div class="lobby">
          <.player_list players={@players} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :players, :map,  required: true
  def player_list(assigns) do
    ~H"""
    <div class="player-list">
      <.header>
        Current Players <.px_icon name="users" />
      </.header>
      <ul>
        <.user :for={{name, %{ready: ready, host: host}} <- @players} ready={ready} host={host}>
          <%= name %>
        </.user>
      </ul>
      <.button phx-click="ready">
        Ready
      </.button>
      <.button class="mt-4" phx-click="start" disabled={!all_ready?(@players)}>
        Start
      </.button>
    </div>
    """
  end

  slot :inner_block, required: true
  attr :ready, :boolean, required: true
  attr :host, :boolean, default: false

  def user(assigns) do
    ~H"""
    <li>
      <%= if @ready do %>
        <.px_icon name="user-check" />
      <% else %>
        <.px_icon name="user" />
      <% end %>
      <%= render_slot(@inner_block) %>
      <.px_icon :if={@host} name="crown" />
    </li>
    """
  end

  attr :mode, :string, default: "new"

  def game_details(assigns) do
    ~H"""
    <form class="grid max-w-prose" phx-submit="config">
      <.input
        type="radio"
        id="mode_new"
        name="mode"
        value="new"
        label="New game"
        checked={true}
      />
      <.input
        type="radio"
        id="mode_join"
        name="mode"
        value="join"
        label="Join game"
      />
      <.input type="text" id="room_name" name="room_name" label="Room name" value="" required />
      <.input type="text" id="player_name" name="player_name" label="Player name" value="" required />
      <.button class="mt-4" type="submit">Submit</.button>
    </form>
    """
  end
end
