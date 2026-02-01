# Openclaw Azure Marketplace - Zero-Friction Onboarding Challenge

## The Goal
User deploys VM from Azure Marketplace → SSHs in → runs ONE command → everything works.

## Current Pain Points

### 1. GitHub Copilot Authentication
- Copilot CLI requires GitHub authentication
- `gh auth login` is interactive (device flow or browser)
- User needs: GitHub account + Copilot subscription
- Token needs to be stored securely

### 2. Openclaw Gateway Setup  
- `openclaw onboard` is interactive wizard
- Requires choosing: LLM provider, API keys, channels
- WhatsApp requires QR code scanning
- Telegram requires BotFather token

### 3. OpenCode Authentication
- Also uses GitHub Copilot tokens
- Shares auth with `gh` CLI or needs COPILOT_GITHUB_TOKEN

## Authentication Options to Consider

### Option A: Device Flow (Current)
```bash
gh auth login --web
# Opens browser, user authenticates
# Works but requires browser access
```

### Option B: Pre-shared Token
```bash
# User generates PAT on github.com, pastes it
export GITHUB_TOKEN=ghp_xxx
gh auth login --with-token
```

### Option C: Cloud-Init with Secrets
```yaml
# ARM template parameter for GitHub token
# Injected at deploy time via Azure Key Vault or parameter
```

### Option D: OAuth App Redirect
- Build a web service that handles OAuth
- User clicks link, authenticates, token delivered to VM
- Most seamless but requires infrastructure

## Questions to Solve

1. **How to authenticate GitHub Copilot with minimal friction?**
   - Device flow requires browser
   - Token paste requires user to generate PAT
   - Can we pre-auth somehow?

2. **How to handle LLM provider selection?**
   - Default to GitHub Copilot (comes with auth)
   - Allow adding Anthropic/OpenAI keys later

3. **How to set up messaging channels?**
   - WhatsApp: QR code (unavoidable, requires phone)
   - Telegram: BotFather token (can be prompted)
   - Discord: Bot token + server invite (can be prompted)
   - Option: Start with NO channels, just CLI access?

4. **What should the "one command" experience look like?**
   ```bash
   openclaw quickstart
   # or
   ./setup-openclaw.sh
   ```

5. **Can we use Azure Managed Identity for anything?**
   - VM has Azure identity
   - Could use Azure Key Vault for secrets
   - But GitHub auth is separate

## Proposed Architecture

### Tier 1: Instant CLI Access (no auth needed)
- Openclaw CLI works immediately for local tasks
- `openclaw agent --local "hello"` works with NO setup
- Uses a bundled/free model? Or requires first auth?

### Tier 2: GitHub Copilot (one-time device auth)
- `openclaw auth github` triggers device flow
- Token stored in `~/.openclaw/credentials/`
- Enables: Copilot models, OpenCode, coding agents

### Tier 3: Messaging Channels (optional, per-channel)
- `openclaw channel add whatsapp` → QR code
- `openclaw channel add telegram` → paste token
- Each channel is opt-in

## Ideal User Journey

1. Deploy VM from Azure Marketplace
2. SSH in, see welcome MOTD
3. Run: `openclaw quickstart`
4. Quickstart:
   - "Let's authenticate with GitHub Copilot"
   - Shows device code: "Go to github.com/login/device, enter: ABCD-1234"
   - Waits for auth completion
   - "✅ Authenticated! You have Copilot Enterprise access"
   - "Want to add a messaging channel? (WhatsApp/Telegram/Skip)"
   - If WhatsApp: shows QR code in terminal
   - "✅ Setup complete! Try: openclaw agent 'hello world'"
5. Done in <5 minutes

## Files to Create/Update

1. `scripts/setup.sh` - Pre-install gh CLI
2. `scripts/first-login.sh` - Runs on first SSH, triggers quickstart
3. Update MOTD to guide user
4. Consider: Custom `openclaw quickstart` command? Or wrapper script?

## Open Questions for Deep Thinking

1. Is there a way to pre-authenticate GitHub during VM deployment?
   - Azure Key Vault integration?
   - ARM template secure parameter?
   
2. Should we support multiple auth methods?
   - Device flow (default)
   - Token paste (advanced)
   - OAuth redirect (if we build infrastructure)

3. What's the minimum viable onboarding?
   - Just GitHub auth + no channels = still useful for coding agents

4. How to handle token refresh/expiry?
   - GitHub tokens expire
   - Need background refresh mechanism

5. Can we detect Copilot subscription status?
   - User might auth but not have Copilot access
   - Need graceful fallback

