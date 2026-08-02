# Clipboard Reading Hotkey Design

## Goal

Let users explicitly read copied text through a dedicated global shortcut, without
changing the existing selection-reading shortcut or making clipboard access an
implicit fallback.

## Scope and boundaries

- Keep the existing selection shortcut (`⌥R`) and its behavior unchanged.
- Add a separately configurable clipboard-reading shortcut, defaulting to
  `⌥⇧R`.
- Persist the two shortcut configurations independently.
- Register the two shortcuts independently, so a conflict while registering one
  does not unregister or replace the other working shortcut.
- Triggering the clipboard shortcut calls the existing explicit clipboard
  reading flow; it does not access Accessibility APIs.
- Keep clipboard text transient: do not log, persist, or otherwise retain its
  contents outside the active reading flow.

Out of scope: automatic fallback from a failed or empty selection to the
clipboard, new permissions, changes to the Carbon event mechanism, and changes
to the existing selection-shortcut preference format.

## Design

### Configuration and UI

`HotKeyConfiguration` provides a second default for clipboard reading.
`HotKeyConfigurationStore` stores the selection and clipboard configurations
under separate keys, preserving the current selection key and decoding behavior.
The shortcut settings UI displays two individually recordable controls, each
with its own restore-default action and clear label for its text source.

### Registration

`AppDelegate` owns one global-hotkey controller for selection reading and one
for clipboard reading. Each controller receives a distinct Carbon identifier and
callback. The selection callback continues to invoke
`ReadingCoordinator.handleReadShortcut()`; the clipboard callback invokes
`ReadingCoordinator.readClipboard()`.

When a user changes either configuration, only that controller is re-registered.
The candidate is saved only after registration succeeds. If registration fails,
the previously registered and persisted configuration for that source is restored
and the user sees the existing shortcut-conflict error.

### Reading behavior and errors

The clipboard callback reuses `ReadingCoordinator.readClipboard()`, including
text sanitization, voice-service configuration gating, speech lifecycle, state
updates, and non-interrupting clipboard errors. An empty clipboard or rejected
clipboard content never stops an active reading session. A selection failure
never invokes the clipboard reader.

### Tests and verification

Core tests will cover the new default and independent store round-trip, and will
retain the explicit clipboard-reading and no-automatic-fallback tests. App-level
behavior will be verified by building the Xcode project. Manual verification
will confirm both shortcuts work independently, each can be customized, and a
registration conflict leaves the previous shortcut usable.

## Risks and rollback

This is an L3 change because it expands global shortcut registration and adds a
persisted preference. The compatibility risk is limited by leaving the existing
selection preference untouched. Revert the feature commit to remove the new
shortcut; the unused clipboard preference key is harmless and does not alter the
selection shortcut.
