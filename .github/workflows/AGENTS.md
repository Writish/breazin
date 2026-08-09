# Workflow rules

- Pull requests get read-only contents permission and no production secrets.
- Write-capable repair automation requires an explicit protected approval signal and an isolated branch/worktree.
- Build/test, compatibility, bundle smoke, and independent review are separate from merge and publication authority.
- Production release jobs use a protected environment with human approval and promote one immutable artifact.
