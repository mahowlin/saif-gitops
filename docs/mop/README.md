# Day 2 Operations (MOPs)

Step-by-step procedures for common GitOps operations.

## Procedures

| Procedure | Description | When to Use |
|-----------|-------------|-------------|
| [01-add-application.md](01-add-application.md) | Add new application to cluster | Deploying new workloads |
| [02-add-operator.md](02-add-operator.md) | Add new OLM operator | Installing certified operators |
| [03-sealed-secrets.md](03-sealed-secrets.md) | Manage GitOps secrets | Creating/updating secrets |
| [04-troubleshooting.md](04-troubleshooting.md) | Common issues and solutions | When sync fails |

## Key Principle: Everything is Git

All Day 2 operations follow the same pattern:

```
1. Edit files in this repo
2. Commit and push
3. ArgoCD syncs automatically
4. Verify in ArgoCD UI
```

**No kubectl/oc commands needed** for normal operations.

## Quick Reference

### Add App to Cluster

```bash
cp clusters/ai-pod-1/tetragon.yaml clusters/ai-pod-1/my-app.yaml
# Edit my-app.yaml to point to apps/my-app/
git add . && git commit -m "Add my-app" && git push
```

### Remove App from Cluster

```bash
rm clusters/ai-pod-1/my-app.yaml
git add -u && git commit -m "Remove my-app" && git push
```

### Force Sync

```bash
gh workflow run gitops-sync.yaml -f cluster=ai-pod-1
```

### Inject Secrets

```bash
gh workflow run gitops-sync.yaml -f cluster=ai-pod-1 -f inject_secrets=true
```
