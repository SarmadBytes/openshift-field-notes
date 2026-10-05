# Contributing to OpenShift Second Brain

Thank you for helping the OpenShift community! Every issue you document saves someone hours of debugging.

## How to Contribute

### 1. Adding a New Issue

1. **Fork this repository**
2. **Find the next issue number** (check highest number in `issues/`)
3. **Create your issue directory**: `issues/XXX-brief-description/`
4. **Add three files**:
   - `problem.md` - Describe what went wrong
   - `logs.txt` - Include relevant error logs
   - `solution.md` - Explain how you fixed it

### 2. File Formats

#### problem.md
```markdown
# Problem: [Brief Title]

## Environment
- OpenShift Version: 4.x
- Namespace: example-namespace
- Component: [pods/storage/network/etc]

## Description
What was happening when the error occurred?

## Symptoms
- Pod status showing...
- Error messages indicating...
- Unexpected behavior like...
```

#### logs.txt
```
$ oc logs pod-name
Error: container has runAsNonRoot and image has non-numeric user (operator)
$ oc describe pod pod-name
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Warning  Failed     1m    kubelet            Error: InvalidImageName
```

#### solution.md
```markdown
# Solution

## Root Cause
The issue was caused by...

## Fix Applied
1. First, I checked...
2. Then I applied this fix:
   ```bash
   oc command here
   ```
3. Verified it worked by...

## Prevention
To avoid this in future:
- Always check...
- Set up monitoring for...
- Use this pattern...
```

### 3. Adding Quick Wins

If you have a one-liner solution, add it to the appropriate file in `quick-wins/`:
- `pod-issues.md`
- `storage-issues.md`
- `networking-issues.md`
- `security-issues.md`

Format:
```markdown
## Issue: [Brief description]
**Fix**: `oc command or solution`
**When to use**: [Context when this applies]
```

### 4. Privacy and Security

⚠️ **Before submitting, ensure you:**
- Remove all sensitive data (passwords, tokens, API keys)
- Replace real namespace/project names with generic ones
- Remove internal URLs and IPs
- Anonymize any company-specific information

### 5. Submit Pull Request

1. Commit your changes with clear message:
   ```
   Add issue #045: Pod failing due to SCC constraints
   ```
2. Push to your fork
3. Create pull request with:
   - Issue number in title
   - Brief description of the problem solved
   - Mention if it's a common/recurring issue

## Guidelines

### ✅ Good Contributions
- Real issues you actually solved
- Clear problem description
- Actual logs (sanitized)
- Step-by-step solutions
- Prevention tips

### ❌ Avoid
- Theoretical issues
- Incomplete solutions
- Sensitive information
- Duplicate issues (search first!)

## Recognition

Contributors will be recognized in:
- Pull request history
- Future contributors section
- Community acknowledgments

Thank you for making OpenShift easier for everyone! 🙏