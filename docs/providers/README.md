# Provider Documentation

Detailed implementation notes for each Bairometer data source.

| Provider | Document | Default | Experimental |
| --- | --- | --- | --- |
| OpenAI Codex | [codex-app-server.md](codex-app-server.md) | App-server (`codex app-server`) | Yes |
| Claude Code | [claude-code-statusline.md](claude-code-statusline.md) | `statusLine` helper → SQLite | No |
| Claude Code | [claude-usage-cli.md](claude-usage-cli.md) | `/usage` CLI | Yes |
| Ollama Cloud | [ollama-web-page.md](ollama-web-page.md) | Web page (isolated WebKit) | Yes |
| MiniMax | [minimax.md](minimax.md) | Token Plan remains API (Global Default Team) | Yes |
| OpenRouter | [openrouter.md](openrouter.md) | Research: current-key API | No |

See the main [README](../README.md) for the provider overview and the
[plan](../plan.md) for full provider research and adapter contracts.
