# Local audio conversion MCP server

In the macOS app, open **Settings → MCP Server**, choose a port (default 8765), and select **Start server**. Keep Opra open. Copy the connection configuration into an MCP client that supports Streamable HTTP and custom authorization headers. Configuration formats vary by client; the endpoint and Authorization header shown in Settings are authoritative.

The endpoint is `http://127.0.0.1:8765/mcp`. Use `Authorization: Bearer <token shown in Settings>`. The server implements the JSON-response variant of MCP Streamable HTTP (protocol 2025-11-25), with no server-initiated SSE stream. POST requests need `Content-Type: application/json`; GET returns 405. It supports initialize, ping, tools/list, tools/call, resources/list, and resources/read.

Tools:

- `convert_text_to_audio`: `{ "text": "Read this aloud", "provider": "kokoro" }`. Provider can be `kokoro` (default), `ollama`, or `openai`. Returns a jobID immediately. Uses the voice configured in Opra, at normal narration speed. Install Kokoro's model or configure the other provider before calling it. OpenAI sends the text to the provider and incurs usage charges on the configured API account.
- `audio_status`: `{ "jobID": "…" }`. Returns state and progress. Completed jobs return a local `filePath` and `resourceURI`.
- `cancel_audio`: `{ "jobID": "…" }`. Cancels pending work. An inference already in progress finishes before cancellation takes effect.

Read a completed `opra-audio://…` resource using `resources/read` to obtain base64 audio. WAV is used for Kokoro/Ollama; MP3 for OpenAI. Resources over 24 MB must be copied from the returned local file path. Reading a PDF through MCP currently requires the client to extract its text and pass it to `convert_text_to_audio`.

Limits: one active conversion, 100,000 text characters, 20 jobs per server session, 1 MB request bodies, and 16 simultaneous HTTP connections. Temporary exports are deleted when the server stops. Copy files you want to keep before stopping. Restarting creates a new token and clears completed jobs; clients must update their header.

The listener binds only to IPv4 loopback, validates Host and Origin, and requires a random per-start bearer token. It accepts no arbitrary file paths. It is deliberately unavailable from an iPhone, another computer, or the public Internet. The iOS Ollama connection is separate and uses the Ollama host's URL.

Run `bash scripts/test-mcp.sh` for the HTTP/protocol regression suite. Tests use synthetic engines and never download models or call paid providers.
