# Someday / Maybe

Plans that are parked, not scheduled. Nothing here is on the roadmap. Each
entry says why it was parked and what would bring it back.

## OAuth login (replacing email codes)

**Deferred on 2026-10-09.** Robert had planned this because he believed AWS was
retiring the email service the app sends codes through. A Claude session
checked: the 2027 retirement is Amazon WorkMail, and the app uses SES, which
had no end-of-support notice as of 2026-10-09. Email-code login keeps working,
so nothing forces this work.

**What would bring it back:** SES actually being retired, email delivery
becoming unreliable, or wanting provider-side 2FA for free.

Decisions Robert made on 2026-10-09, to keep when this resumes:
- Direct OpenID Connect against each provider, written in-app with
  `fetch` and `node:crypto`. No dependency (about 100 lines to own).
- Users are identified by the provider's issuer and account ID (`sub`), never
  by the email claim (Microsoft's is user-editable).
- Bootstrap: log in with an email code, then link the provider account to
  record its ID. After both users have linked, OAuth becomes primary.
- Email-code login stays as a fallback for one month after that, then is
  retired.
- Providers: Microsoft personal accounts (`consumers` endpoint) for Lyndzie.
  Robert uses Google via his defore.st account, unless he has moved off Google
  by then.
- The callback must be a GET redirect (no `form_post`): the session cookie is
  `sameSite: 'lax'` and would not ride a cross-site POST.

## Self-hosted identity provider (Authelia, then Keycloak)

**Deferred per priority shift (2026-10-07).** Robert moved his working
energy to a new venture, and RentCoordinator is no longer slated to become
something he sells or sells access to. The educational and teaching reasons
behind this plan no longer apply to this project.

**What would bring it back:** Robert moving off Google services, or his
long-term goal of running his own OAuth provider. Either would be a separate
project on its own VM (one service per VM), with RentCoordinator as one of
its clients — not work done inside this repo.

See also the OAuth entry above, which is the smaller plan for this project.

**Checked on 2026-10-09 by a Claude session:** Authelia only acts as an OpenID
Connect *provider*. It cannot hand sign-in off to Google or Microsoft (relying
party support was at "Planning" on its roadmap), so it could not have served
the "log in with Microsoft" need on its own. Keycloak can broker external
providers. Re-check both before picking this up.

The plan as it stood in `CLAUDE.md` before 2026-10-09:

*Phase 1: Email verification (what shipped)*
- Email verification codes with 90-day sessions
- Minimal login frequency due to long session duration
- Adequate security for a 2-user application

*Phase 2: Authelia (Learning Project)*
- Lightweight self-hosted OAuth provider
- Low operational complexity (<30MB footprint, 1-2 hrs/month maintenance)
- Learning experience with OAuth/OIDC
- Resources: single instance with Redis for sessions
- Target: educational value + control over auth

*Phase 3: Keycloak (Teaching Platform)*
- Upgrade to enterprise-grade OAuth provider
- Better for teaching friends about IAM
- Full OAuth 2.0 / OpenID Connect compliance
- Industry-standard skills transferable to enterprise
- Resources: single instance + PostgreSQL (~$30/month)
- Target: educational platform for helping friends learn tech

The original text said both could run on existing infrastructure. Robert's
one-service-per-VM rule rules that out; each would need its own instance.
