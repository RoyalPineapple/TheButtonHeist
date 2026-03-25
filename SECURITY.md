# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Button Heist, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please use [GitHub Security Advisories](https://github.com/RoyalPineapple/ButtonHeist/security/advisories/new) to report the vulnerability privately. This allows us to assess and address the issue before it becomes public.

### What to include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### What to expect

- We will acknowledge your report within 48 hours
- We will provide a timeline for a fix within 7 days
- We will credit you in the fix (unless you prefer to remain anonymous)

## Scope

### In scope

- Authentication bypass in token-based auth
- Unauthorized access to session-locked devices
- Buffer overflow or memory corruption in wire protocol handling
- Remote code execution via crafted messages

### Out of scope

Button Heist intentionally uses private iOS APIs for synthetic touch injection and accessibility inspection. The following are **by design** and not considered vulnerabilities:

- Use of private UIKit/IOKit APIs (`UIApplication.sendEvent`, IOHIDEvent creation, UIKeyboardImpl)
- ObjC runtime method swizzling and `+load` hooks
- Access to the accessibility hierarchy
- Local network TCP communication (this is the core transport mechanism)
- Token values visible in process environment variables (standard configuration method)

## Supported Versions

We apply security fixes to the latest release only.
