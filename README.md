# A `dev-container` for the Distributed Systems lectures

To use it, fork the repository (or copy the `.devcontainer/`) and open this folder in VS Code.
Then a pop-up "Reopen in Container?" should appear, press Yes, and enjoy.
The first boot might take longer because the Docker image is being built.

For elixir start with:

```bash
mix new .
```

For Erlang:

```bash
rebar3 new app example
```
