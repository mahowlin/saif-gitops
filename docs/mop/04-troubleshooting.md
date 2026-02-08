# GitOps Troubleshooting

## Common Issues and Solutions

### Application Sync Status "Unknown"

**Symptoms:**
- ArgoCD shows "Unknown" status
- Application not syncing

**Causes:**
1. GitHub credentials expired
2. Repository not accessible
3. ArgoCD can't reach GitHub

**Solution:**

```bash
# Check credentials secret
oc get secret github-repo-creds -n openshift-gitops

# Re-run ArgoCD bootstrap
gh workflow run openshift-post-install.yaml \
  -f cluster_name=ai-pod-1 \
  -f apply_argocd=true \
  --repo mahowlin/saif-ai-pod

# Force refresh
gh workflow run gitops-sync.yaml -f cluster=ai-pod-1
```

---

### Application Sync Status "OutOfSync"

**Symptoms:**
- ArgoCD shows yellow "OutOfSync" status
- Resources differ from Git

**Causes:**
1. Manual changes made to cluster
2. Drift from desired state
3. Webhook or operator modified resources

**Solution:**

```bash
# Check what's different
oc get application <app-name> -n openshift-gitops -o yaml | grep -A 20 status

# Force sync from ArgoCD UI
# Or via CLI:
oc -n openshift-gitops patch application <app-name> \
  --type merge \
  --patch '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

---

### Application Sync Status "Degraded"

**Symptoms:**
- ArgoCD shows red "Degraded" status
- Some resources failed

**Causes:**
1. Resource creation failed
2. Pods not starting
3. Dependencies missing

**Solution:**

```bash
# Check application events
oc describe application <app-name> -n openshift-gitops

# Check resource status
oc get events -n <app-namespace> --sort-by='.lastTimestamp'

# Check pod logs
oc logs -n <app-namespace> -l app=<app-name>
```

---

### ImagePullBackOff

**Symptoms:**
- Pods stuck in `ImagePullBackOff`
- Image not found errors

**Causes:**
1. Image not mirrored
2. IDMS not applied
3. Wrong image tag

**Solution:**

```bash
# Check IDMS status
oc get imagedigestmirrorset

# Verify image exists in registry
curl -s https://registry.example.com:5000/v2/<image>/tags/list

# If missing, mirror the image
gh workflow run sync-images.yaml --repo mahowlin/saif-sys-admin

# Then sync IDMS
./scripts/sync-idms-from-sys-admin.sh
git add apps/platform-idms/
git commit -m "fix: Update IDMS"
git push
```

---

### Operator Installation Failed

**Symptoms:**
- CSV stuck in `Pending` or `Failed`
- Operator pod not starting

**Causes:**
1. CatalogSource unhealthy
2. Missing images
3. RBAC issues

**Solution:**

```bash
# Check CatalogSource
oc get catalogsource -n openshift-marketplace
oc describe catalogsource <name> -n openshift-marketplace

# Check InstallPlan
oc get installplan -n <operator-namespace>

# Check CSV
oc get csv -n <operator-namespace>
oc describe csv <csv-name> -n <operator-namespace>
```

---

### Sealed Secret Not Decrypting

**Symptoms:**
- SealedSecret exists but Secret not created
- Controller errors in logs

**Causes:**
1. Wrong key pair
2. Namespace mismatch
3. Controller not running

**Solution:**

```bash
# Check controller status
oc get pods -n sealed-secrets

# Check controller logs
oc logs -n sealed-secrets deployment/sealed-secrets-controller

# Verify key exists
oc get secret sealed-secrets-key -n sealed-secrets

# If key missing, re-run post-install
gh workflow run openshift-post-install.yaml \
  -f cluster_name=ai-pod-1 \
  --repo mahowlin/saif-ai-pod
```

---

### ArgoCD UI Not Accessible

**Symptoms:**
- Cannot reach ArgoCD web interface
- Connection timeout

**Causes:**
1. Route not created
2. ArgoCD pods not running
3. Network policy blocking

**Solution:**

```bash
# Check route
oc get route -n openshift-gitops

# Check pods
oc get pods -n openshift-gitops

# Check ArgoCD CR
oc get argocd openshift-gitops -n openshift-gitops

# Restart if needed
oc delete pod -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-server
```

---

### Sync Wave Order Issues

**Symptoms:**
- Resources created before dependencies
- CRD not found errors

**Causes:**
1. Missing sync-wave annotations
2. Incorrect wave numbers

**Solution:**

Verify sync-wave annotations:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # CatalogSources
    argocd.argoproj.io/sync-wave: "0"   # Subscriptions
    argocd.argoproj.io/sync-wave: "1"   # CRs
```

---

## Diagnostic Commands

### Check All Applications

```bash
oc get applications -n openshift-gitops
```

### Force Hard Refresh

```bash
oc -n openshift-gitops patch application <app-name> \
  --type merge \
  --patch '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### View Application Details

```bash
oc get application <app-name> -n openshift-gitops -o yaml
```

### Check ArgoCD Logs

```bash
# Application controller
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller

# Repo server
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-repo-server
```

### Test GitHub Connectivity

```bash
# From ArgoCD repo-server pod
oc exec -n openshift-gitops deployment/openshift-gitops-repo-server -- \
  git ls-remote https://github.com/mahowlin/saif-gitops.git
```

## Getting Help

If issues persist:

1. Check ArgoCD UI for detailed error messages
2. Review controller logs
3. Verify GitHub Actions workflow logs
4. Check repo documentation for known gotchas
