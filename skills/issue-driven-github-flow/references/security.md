# Security and secret hygiene

The workflow must never turn credentials into repository history. Treat secret
hygiene as a blocking safety requirement, not a review nit.

## Never commit

- API keys, OAuth client secrets, personal access tokens, deploy keys, SSH keys,
  cloud credentials, database passwords, or service-account JSON files.
- `.env`, `.env.local`, `.npmrc`, `.pypirc`, kubeconfigs, Terraform variable
  files, or config files containing live credentials.
- Generated private keys, certificates, signing keys, recovery codes, or seed
  phrases.
- Test fixtures that contain real customer data, production tokens, or secrets
  copied from logs.

If a user asks to commit a secret, refuse that part of the request and explain
how to wire the value safely.

## Safe alternatives

- Use environment variables for local development.
- Use GitHub Actions Secrets or organization/repository/environment secrets for
  CI and deployments.
- Use Dependabot secrets for Dependabot workflows.
- Use an approved cloud secret manager or vault for runtime services.
- Commit `.env.example` or documented variable names with fake placeholder
  values only.

## Push protection

Recommend enabling GitHub secret scanning and push protection so accidental
commits are blocked before they land:

```bash
gh api --method PATCH repos/{owner}/{repo} \
  --input - <<'JSON'
{
  "security_and_analysis": {
    "secret_scanning": {
      "status": "enabled"
    },
    "secret_scanning_push_protection": {
      "status": "enabled"
    }
  }
}
JSON
```

Repository security settings may require admin permissions. Offer to apply them
only with explicit user consent.

## If a secret was already committed

1. Stop using it immediately.
2. Revoke or rotate the credential at the provider.
3. Remove it from the working tree.
4. Follow the repository owner's incident process for history cleanup. Do not
   rewrite `main` casually; coordinate because history rewrites affect every
   clone and may not erase exposed secrets from forks or logs.
5. Add a regression guard such as secret scanning, a safer example file, or a
   documented secret source.
