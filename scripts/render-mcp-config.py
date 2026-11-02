#!/usr/bin/env python3
"""Render optional MCP URLs from local environment without site defaults."""

import json
import os
import pathlib
import re
import sys


URL_VARIABLES = {
    "{{CMDS_AGENT_MCP_URL}}": "CMDS_AGENT_MCP_URL",
    "{{WIKI_MCP_URL}}": "WIKI_MCP_URL",
    "{{GITLAB_MCP_URL}}": "GITLAB_MCP_URL",
}


def render_config(template_text: str, environment: dict[str, str]) -> str:
    """Return valid MCP JSON, omitting optional remote servers without URLs."""
    config = json.loads(template_text)
    obsidian = config.get("mcpServers", {}).get("obsidian", {})
    headers = obsidian.get("headers", {})
    headers["Authorization"] = f"Bearer {environment.get('OBSIDIAN_API_KEY', '')}"
    obsidian["serverUrl"] = (
        f"http://127.0.0.1:{environment.get('OBSIDIAN_REST_PORT', '0')}/mcp/"
    )
    servers = config.get("mcpServers")
    if not isinstance(servers, dict):
        raise ValueError("template must contain an mcpServers object")

    server_variables = {
        "cmds-agent": "CMDS_AGENT_MCP_URL",
        "wiki": "WIKI_MCP_URL",
        "gitlab": "GITLAB_MCP_URL",
    }
    for server_name, variable in server_variables.items():
        url = environment.get(variable, "").strip()
        if url:
            if not url.startswith(("https://", "http://")):
                raise ValueError(f"{variable} must be an http(s) URL")
            servers[server_name]["serverUrl"] = url
        else:
            servers.pop(server_name, None)

    # Keep this assertion close to rendering: never write a partially rendered config.
    rendered = json.dumps(config, indent=2) + "\n"
    if re.search(r"\{\{[^{}]+\}\}", rendered):
        raise ValueError("rendered MCP config contains an unresolved template variable")
    return rendered


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: render-mcp-config.py TEMPLATE DEST")

    template_path = pathlib.Path(sys.argv[1])
    destination = pathlib.Path(sys.argv[2])
    rendered = render_config(template_path.read_text(), dict(os.environ))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(rendered)
    os.chmod(destination, 0o600)
    print(destination)


if __name__ == "__main__":
    main()
