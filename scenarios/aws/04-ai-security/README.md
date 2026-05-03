# AI Security

Scenarios focused on AI/ML service vulnerabilities in cloud environments.

## Scenarios

| # | Scenario | Difficulty | Summary |
|---|---|---|---|
| 1 | [bedrock-kb-poisoning](./bedrock-kb-poisoning) | Hard | Indirect prompt injection through a Bedrock RAG corpus. A `bpo_editor` poisons a Bedrock Knowledge Base via the FAQ-editor write path; the citation-link Lambda then mints a presigned URL for an admin-only customer export because it skips the per-document permission re-check, escalating the attacker into seller-admin-only data. |
