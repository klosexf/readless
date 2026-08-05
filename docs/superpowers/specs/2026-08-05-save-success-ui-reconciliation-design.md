# Save Success UI Reconciliation Design

## Problem

The voice-service editor can show `凭据已保存` and `无法保存语音服务设置，请重试。` at the same time even though both the credential file and the selected voice configuration were durably updated. This is a false-negative UI state.

The existing recovery check only asks whether any credential exists in the slot. That is insufficient when replacing a credential because an older credential can make the check pass or fail ambiguously. The editor also retains its previous error until a later save explicitly clears it.

## Desired Behavior

- Clear a stale save error as soon as a new save attempt starts.
- Treat a save as successful when the requested configuration and, when supplied, the exact normalized credential can be read back from durable storage.
- On success, clear the credential field and remove the orange error.
- Show the persistence error only when the requested state cannot be read back exactly.
- Never expose, log, or display the credential during verification.

## Design

`VoiceServiceSaveCoordinator` remains the single owner of save verification.

1. Normalize and validate the submitted credential.
2. Save the credential when a replacement value is supplied.
3. Save the voice-service configuration.
4. If either operation throws, read both stores again:
   - the stored configuration must equal the submitted configuration;
   - when a replacement credential was supplied, the stored credential must equal that normalized value;
   - when no replacement was supplied, the credential slot only needs to contain a non-empty credential.
5. Return success only when those checks pass.

`VoiceServiceEditor` clears its displayed error before invoking the save action. It continues to trust the coordinator's final result and clears the credential field only on success.

## Error Handling

Storage exceptions remain internal. The UI receives `.persistenceFailed` only after exact post-save verification fails. Secret values are never included in errors or diagnostics.

## Testing

- Coordinator recovery succeeds when a replacement credential and configuration both persist before an exception.
- Coordinator recovery fails when only an older credential exists after a replacement save throws.
- Saving without a replacement credential succeeds when the configuration persists and the existing slot remains populated.
- Source/layout regression test confirms the editor clears stale error state at the beginning of a save attempt.
- Run the full Swift package tests and signed Xcode build.

## Out of Scope

- Validating credentials against the remote TTS provider during local save.
- Changing API-key acquisition or provider configuration UX.
- Committing the user's existing sidebar icon change.
