# Working agreement

- Use pstack for nontrivial work: ground the existing code, compare designs, implement, independently review, and verify the real result. If a configured provider is disabled, unavailable, or out of quota, fall back to an available model and continue. State the fallback; do not ask the user to choose models again. Independent reviews still apply when all available agents use one model family.
- Finish authorized work by committing and pushing the task's changes. Do not stop at an uncommitted implementation or wait for another push instruction. Preserve unrelated changes in this shared workspace.
- After a successful push, remove this task's finished worktrees and temporary files. Keep concise verification evidence outside the repository. Do not remove another active task's worktree, dirty files, shared build caches, or release signing keys.
- User-facing releases use the version in `VERSION` and curated notes in `releases/<version>.md`. Bump the patch version and describe the changes before shipping a later user-facing release. Never reuse a published version for different code. Internal build numbers remain monotonic.
- Run the relevant checks in `docs/testing-policy.md`. Publication and app replacement must use the verified artifacts, not only passing mocks.
