# Copilot Bridge

This local HTTP service accepts text payloads and returns a theme summary.
It uses the GitHub Copilot SDK via your existing CLI auth session.

## Run

```sh
cd tools/copilot-bridge
npm install
npm start
```

Default endpoint:

```
http://127.0.0.1:32190/analyze
```

Health endpoint:

```
http://127.0.0.1:32190/health
```

## Payload

```json
{ "texts": ["string", "string"] }
```

## Response

```json
{
  "summary": "Bridge keyword scan",
  "themes": ["Frequent topics: ..."],
  "confidence": 0.4
}
```

## Copilot SDK

Auth uses your Copilot CLI session. Ensure you have logged in with:

```sh
gh auth login
gh copilot auth
```

The bridge will fall back to keyword analysis if Copilot is unavailable.
