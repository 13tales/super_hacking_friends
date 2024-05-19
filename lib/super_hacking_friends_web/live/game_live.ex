defmodule SuperHackingFriendsWeb.GameLive do
  use SuperHackingFriendsWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, term_input: "")}
  end

  def handle_event("proc", params, socket) do
    IO.inspect(params)

    {:noreply, assign(socket, term_input: "")}
  end

  def handle_event("term_input", params, socket) do
    {:noreply, assign(socket, term_input: params["term_input"])}
  end
end
