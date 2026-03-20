# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT** open a public issue
2. Email the maintainer or open a [private security advisory](https://github.com/YuHoYe/CCDock/security/advisories/new)
3. Include steps to reproduce the vulnerability

## Scope

CCDock reads local session files and does not make network requests. The main security considerations are:

- Local file access permissions
- AppleScript / Accessibility API usage for terminal activation
- Unix socket communication (if hook mode is used)
