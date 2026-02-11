---
name: check-cdr
description: View recent call detail records from any FreePBX server
disable-model-invocation: false
allowed-tools: Bash, Read, Grep
argument-hint: [server-ip] [count|ext=NNN|date=YYYY-MM-DD]
---

# Check CDR - View Call Records

**Required argument:** First word of `$ARGUMENTS` = FreePBX server IP/hostname

**Optional filters (remaining arguments):**
- A number (e.g., `20`) = number of records to show (default: 15)
- `ext=204` = filter by extension (src or dst)
- `date=2025-01-15` = filter by specific date
- `cid=John` = filter by caller ID name
- `today` = show only today's calls

Parse `$ARGUMENTS` to extract the server IP (first word) and any filters from the remaining words.

## Base Query
```bash
ssh root@$1 "mysql -N -B asteriskcdrdb -e \"SELECT calldate, clid, src, dst, dcontext, lastapp, duration, billsec, disposition FROM cdr ORDER BY calldate DESC LIMIT 15;\""
```

## Filtered Queries

### By count:
```bash
ssh root@$1 "mysql -N -B asteriskcdrdb -e \"SELECT calldate, clid, src, dst, dcontext, lastapp, duration, billsec, disposition FROM cdr ORDER BY calldate DESC LIMIT $COUNT;\""
```

### By extension:
```bash
ssh root@$1 "mysql -N -B asteriskcdrdb -e \"SELECT calldate, clid, src, dst, dcontext, lastapp, duration, billsec, disposition FROM cdr WHERE src='$EXT' OR dst='$EXT' ORDER BY calldate DESC LIMIT 25;\""
```

### By date:
```bash
ssh root@$1 "mysql -N -B asteriskcdrdb -e \"SELECT calldate, clid, src, dst, dcontext, lastapp, duration, billsec, disposition FROM cdr WHERE DATE(calldate)='$DATE' ORDER BY calldate DESC LIMIT 50;\""
```

### By caller ID:
```bash
ssh root@$1 "mysql -N -B asteriskcdrdb -e \"SELECT calldate, clid, src, dst, dcontext, lastapp, duration, billsec, disposition FROM cdr WHERE clid LIKE '%$CID%' ORDER BY calldate DESC LIMIT 25;\""
```

### Today:
```bash
ssh root@$1 "mysql -N -B asteriskcdrdb -e \"SELECT calldate, clid, src, dst, dcontext, lastapp, duration, billsec, disposition FROM cdr WHERE DATE(calldate)=CURDATE() ORDER BY calldate DESC LIMIT 50;\""
```

## Output Format

Display a formatted table:
| Time | Caller ID | Src | Dst | Context | App | Duration | Disposition |
|------|-----------|-----|-----|---------|-----|----------|-------------|

- **Time**: Format as `HH:MM:SS` (with date if not today)
- **Duration**: Show as `Xm Ys` format
- **Disposition**: ANSWERED, NO ANSWER, BUSY, FAILED (color-code in description)

## Summary
- Total calls shown
- Breakdown: answered / no answer / busy / failed
- If filtering by extension, show inbound vs outbound count

## Common Contexts
- `from-internal` = outbound call from an extension
- `from-trunk-*` or `from-pstn` = inbound call
- `ext-local` = internal extension-to-extension
