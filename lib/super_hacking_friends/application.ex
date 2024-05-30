defmodule SuperHackingFriends.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SuperHackingFriendsWeb.Telemetry,
      SuperHackingFriends.Repo,
      {DNSCluster, query: Application.get_env(:super_hacking_friends, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SuperHackingFriends.PubSub},
      SuperHackingFriendsWeb.GamePresence,
      # Start the Finch HTTP client for sending emails
      {Finch, name: SuperHackingFriends.Finch},
      # Start a worker by calling: SuperHackingFriends.Worker.start_link(arg)
      # {SuperHackingFriends.Worker, arg},
      # Start to serve requests, typically the last entry
      SuperHackingFriendsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SuperHackingFriends.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SuperHackingFriendsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
