# Security Rules

Flag the following as **critical** or **high** severity:

## Secrets
- Hardcoded API keys, tokens, passwords, private keys, connection strings.
- Secrets committed in config files, comments, or test fixtures.
- Use environment variables or secret managers instead.

## Input Validation
- SQL: raw string concatenation in queries → require parameterized queries.
- XSS: unescaped user input rendered into HTML/DOM.
- Path traversal: user-controlled paths passed to filesystem APIs without sanitization.
- Command injection: user input passed to shell commands.
- Deserialization of untrusted data.

## AuthN / AuthZ
- New HTTP endpoints must declare an authentication/authorization check.
- Flag any endpoint that bypasses existing auth middleware.
- Check for IDOR: ensure resource ownership is verified.

## Sensitive Data
- Do not log passwords, tokens, PII, full credit cards, or session IDs.
- Avoid sending sensitive data in URLs (use request body).

## Dependencies
- Flag pinned versions of packages with known CVEs if obvious.
- Flag use of deprecated or unmaintained crypto libraries.
