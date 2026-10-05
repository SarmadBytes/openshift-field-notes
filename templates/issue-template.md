# Issue Template

Copy this template when creating a new issue.

## Files to Create

1. `problem.md` - Description of what went wrong
2. `logs.txt` - Relevant error logs and outputs  
3. `solution.md` - How the issue was resolved

## problem.md Template

```markdown
# Problem: [Brief Descriptive Title]

## Environment
- OpenShift Version: 
- Namespace: 
- Component: [pod/deployment/service/storage/network]
- When it occurred: [during deployment/scaling/update/etc]

## Description
[Explain what was expected vs what actually happened]

## Symptoms
- [First symptom observed]
- [Second symptom]
- [Error messages seen]

## Impact
- [Who/what was affected]
- [Business impact if any]
```

## solution.md Template

```markdown
# Solution

## Root Cause
[Explain why this happened]

## Fix Applied

### Step 1: [Investigation Step]
```bash
oc command used
```
Output showed...

### Step 2: [Fix Implementation]
```bash
oc fix command
```

### Step 3: [Verification]
```bash
oc verification command
```
Confirmed working by...

## Time to Resolution
- Investigation: X minutes
- Implementation: Y minutes
- Total: Z minutes

## Prevention
- [How to prevent this]
- [Monitoring to set up]
- [Best practice to follow]

## Related Issues
- Similar to issue #XXX
- See also: [link or reference]
```