# Phase 3 Gmail Reply Workflow Design

## Goal

Close the daily email loop without sending mail automatically. Users can edit a suggested reply, open a prefilled Gmail compose window, and track whether the reply is drafted, opened, sent manually, or done.

## Scope

Phase 3 keeps the current Google OAuth scopes. It does not add Gmail send or Gmail draft-write permissions. The app only opens Gmail compose URLs and stores reply workflow state locally.

## Approach

The app turns the selected draft plus edited reply text into a Gmail compose URL. The URL pre-fills the recipient, subject, and body. The user still reviews and sends in Gmail.

Reply workflow state is local:

- `needsReply`: someone should respond.
- `drafted`: reply text was edited in the app.
- `copied`: reply was copied to the clipboard.
- `openedInGmail`: Gmail compose was opened with the reply.
- `sentManually`: user confirms they sent it in Gmail.
- `done`: no further reply action is needed.

Today only surfaces reply items that still need attention. `sentManually` and `done` are treated as closed for reply purposes.

## Data Flow

1. Gmail discovery imports an email.
2. Email intelligence suggests a reply when useful.
3. User edits the reply text.
4. App marks the reply `drafted`.
5. User opens Gmail compose or copies the reply.
6. App marks the state `openedInGmail` or `copied`.
7. User sends manually in Gmail.
8. User marks the reply `sentManually` or `done`.

## Error Handling

If there is no reply text, the app refuses to open Gmail compose and shows a local message. If the sender cannot be parsed into a clean email address, the app uses the sender string as Gmail's `to` field.

## Testing

Add tests for Gmail compose URL building, recipient parsing, reply status attention rules, and Today grouping after replies are sent manually.
