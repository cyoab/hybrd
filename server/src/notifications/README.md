# Notifications

Device registration/revocation is implemented in the foundation API; tokens are stored only for the owning athlete and cleared on revocation. No APNs request is sent yet.

Add a server-only APNs adapter when there is an actual remote notification use case. Read signing keys from runtime secrets, separate sandbox/production tokens, handle invalid-token feedback, and never log tokens. Predictable workout reminders belong to local iOS notifications; no queue or worker is provisioned.
