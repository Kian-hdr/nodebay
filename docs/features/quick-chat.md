# Quick Chat

Quick Chat is implemented in the local **1.2.0 (25)** candidate. It is not in
the public 1.1.0 release or current Homebrew cask. Both real OpenAI Responses API
connection validation and a synthetic native chat passed with `gpt-5-mini`.
The visible API key field and compact message bubble were also verified.
The [release verification matrix](../release-verification-matrix.md)
distinguishes completed checks from outstanding provider, native UI and hardware
coverage. No final packaging, notarization or Homebrew result is implied by the
API and native UI checks.

## Choose a provider

Open **Settings → AI & Quick Chat**. New installations default to **Off**.
The chat tab is hidden until a provider is enabled. Selecting a provider or
turning Quick Chat off cancels the active request and clears its temporary chat.

| Mode | Setup | Request path |
|---|---|---|
| Off | No credentials required | No Quick Chat provider requests |
| Codex CLI | A supported signed CLI and its existing sign-in | OpenAI through the restricted Codex worker; account limits apply |
| OpenAI API | A key saved to macOS Keychain and usable API billing | Direct OpenAI Responses API requests; billing is separate from a ChatGPT subscription |

Both providers deliver complete replies. Token streaming is not enabled.
The historical App Server isolation failure applies to that disabled streaming
route. The active API path submits no remote tools; the supported Codex CLI
path uses its separate restricted worker. Neither is represented as an enabled
App Server connection.
The current API model default is `gpt-5-mini` and can be changed in settings;
model access depends on the API account. Nodebay does not bundle Codex or require
an AI provider for media, shelf or other base features.

## Verify OpenAI API setup

1. Choose **OpenAI API**. Under the **API key** heading, paste the key into the
   bordered secure field labelled **Paste API key here (⌘V)** and select
   **Save to Keychain**. Never paste a key into chat, a shell command,
   a screenshot or a setup document. Manage keys through the
   [OpenAI API key page](https://platform.openai.com/api-keys).
2. Use **Validate Connection**. It makes a small real API request and may incur
   API usage. A saved key alone does not establish authorization or model access.
3. Open Quick Chat and send a harmless synthetic question. Verify the returned
   answer in the native app. Connection validation does not replace this chat test.

Missing keys, rejected authorization, rate limits and failed requests are
reported in the app. Resolve account or billing issues in the provider's normal
interface. A failed test does not authorize switching accounts, reading another
app's credentials or weakening provider restrictions.

## Verified native behavior

On the signed 1.2.0 (25) build, the synthetic question **Reply exactly OK.**
returned **OK** through OpenAI API with `gpt-5-mini`. The saved Keychain key was
reused and no Knowledge Folder was enabled. This verifies that the native chat
can send a question and display the provider's answer; it does not establish
Knowledge Folder retrieval or provider-wide retention behavior.

Native screenshots verified the API key heading, instructions and bordered
secure field, plus a compact right-aligned question bubble. Bubbles now fit
their text after resizing. Regression tests cover short and multiline text,
emoji, Arabic, long wrapping and the previously failing resize case. The full
198-test suite passed after both UI changes. Final clean-source packaging,
notarization and Homebrew validation remain separate release steps.

## Temporary conversations and optional knowledge

Closing the notch keeps the current draft and conversation in memory. The default
inactivity timeout is three hours, configurable in settings; explicit saved
timeout choices are preserved. New Chat, expiry, changing provider, turning the
feature off or quitting clears Nodebay's temporary chat. It does not delete saved
notes or provider history. **Copy Context** is an explicit export action.

Questions and conversation context go to OpenAI through the selected provider.
API requests set `store: false` and supply no remote tools. This is not a promise
of provider-wide deletion; retention follows the account and provider.

A Knowledge Folder is optional. Choosing it grants local read-only access and
does not authorize cloud transmission. Separate **Allow Relevant Excerpts**
consent and enabling the folder for a question allow a local search to include
up to four small matching passages, relative paths and citation metadata in that
question. The full folder is not uploaded. You can disable cloud excerpts or
disconnect the folder in settings. Use a synthetic question without a Knowledge
Folder for connection testing.

See [privacy](../../PRIVACY.md) and the [setup prompt](../../SETUP-PROMPT.md).
