---
name: granola
description: Access Granola AI meeting notes via MCP using mcporter. Query meetings with natural language, list by date range, get full details, and pull verbatim transcripts. Use when the user asks about meeting notes, what was discussed, action items, decisions, follow-ups, or anything from their Granola meetings. Requires mcporter CLI and a Granola account with OAuth authentication.
---

# Granola MCP

Connect to [Granola](https://granola.ai) meeting notes via their official MCP server using mcporter.

## Setup

### 1. Configure the MCP server

```bash
mcporter config add granola --url https://mcp.granola.ai/mcp
```

### 2. Authenticate via OAuth

Granola uses browser-based OAuth 2.0 (PKCE). Run the setup script to complete the flow:

```bash
bash {baseDir}/scripts/setup_oauth.sh
```

This will:
- Register a dynamic OAuth client with Granola
- Open the browser for sign-in
- Capture tokens and save to `config/granola_oauth.json`
- Update `config/mcporter.json` with the bearer token

### 3. Set up auto-refresh (recommended)

Tokens expire every 6 hours. Add a cron job to refresh every 5 hours:

```bash
REFRESH_SCRIPT="{baseDir}/scripts/refresh_token.sh"
(crontab -l 2>/dev/null | grep -v granola_refresh; echo "0 */5 * * * $REFRESH_SCRIPT >> /tmp/granola_refresh.log 2>&1") | crontab -
```

## Tools

```
granola.query_granola_meetings  query=<string> [document_ids=<uuid[]>]
granola.list_meetings           [time_range=this_week|last_week|last_30_days|custom] [custom_start=<ISO>] [custom_end=<ISO>]
granola.get_meetings            meeting_ids=<uuid[]>  (max 10)
granola.get_meeting_transcript  meeting_id=<uuid>
```

## Usage

- For open-ended questions ("what did we discuss about X?"), use `query_granola_meetings`
- For listing meetings in a range, use `list_meetings`
- For full details on specific meetings, use `get_meetings` with IDs from list results
- For exact quotes or verbatim content, use `get_meeting_transcript`

Prefer `query_granola_meetings` over list+get for natural language questions.

Responses include citation links (e.g. `[[0]](url)`). Always preserve these in replies so the user can click through to original notes.

## Auth Recovery

If a call fails with 401/auth error:

```bash
bash {baseDir}/scripts/refresh_token.sh
```

If refresh also fails (expired refresh token), re-run the full OAuth setup:

```bash
bash {baseDir}/scripts/setup_oauth.sh
```

## Config Files

- `config/mcporter.json` — MCP server config with bearer token
- `config/granola_oauth.json` — OAuth credentials (client_id, refresh_token, access_token, token_endpoint)
