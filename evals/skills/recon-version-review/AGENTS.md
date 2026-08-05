# Version-review skill maintenance

Read [SKILL.md](SKILL.md) completely. Its behavior is bounded by the
[version-review schema](../../version-reviews/schema.yaml), implemented by the
[rail](../../../tools/version-review.py), and explained in the
[laboratory README](../../version-reviews/README.md).

Keep this file and the skill as routers: do not duplicate field lists,
lifecycle transitions, capture paths, or validation logic. Live review roots
remain private and external; no task-specific Jira facts belong here.
