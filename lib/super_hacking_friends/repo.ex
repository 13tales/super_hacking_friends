defmodule SuperHackingFriends.Repo do
  use Ecto.Repo,
    otp_app: :super_hacking_friends,
    adapter: Ecto.Adapters.Postgres
end
