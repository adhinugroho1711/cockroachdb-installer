# Multi-Site Update Plan for index.html

## Problem
Currently, after user selects Multi-Site (7 VMs) in Section 01, all subsequent sections (03-09) still assume Single-Site (3 nodes). This creates confusion and incorrect instructions.

## Sections That Need Updates

### ✅ Section 01 - Architecture Selection
**Status**: Already updated
- Now offers clear choice between Single-Site (4 VMs) and Multi-Site (7 VMs)
- Provides locality flag preview for Multi-Site users

### ❌ Section 03 - CockroachDB Setup
**Current Issue**: No mention of locality flags
**Required Fix**: 
- Add conditional note explaining when to add `--locality` flags
- Update join command to mention all 5 nodes for Multi-Site

### ❌ Section 04 - SQL Testing  
**Current Issue**: Assumes 3 nodes only
**Required Fix**:
- Update node status check to show "3 nodes (Single-Site) or 5 nodes (Multi-Site)"
- Update test examples to mention n1-n5 for Multi-Site

### ❌ Section 05 - HA & Failover Testing
**Current Issue**: Failover test assumes 3-node cluster
**Required Fix**:
- Add Multi-Site failover scenario (stop n1 & n2, verify n3/n4/n5 maintain quorum)
- Update expected results for both scenarios

### ❌ Section 06 - HAProxy Setup
**Current Issue**: Shows only 1 LB configuration
**Required Fix**:
- Add conditional instructions for LB-A and LB-B (Multi-Site)
- Explain site-aware routing strategy

### Section 07 - PgBouncer
**Status**: Generic, no update needed

### Section 08 - Optimization
**Status**: Generic, no update needed

### ❌ Section 09 - Security Setup (TLS)
**Current Issue**: Certificate generation for 3 nodes only
**Required Fix**:
- Update `generate_certs.sh` script prompt to ask for node count
- Show example for 5 nodes in Multi-Site

### Section 10 - Security Hardening
**Status**: Generic, no update needed

### Section 11 - Migration
**Status**: Generic, no update needed

## Implementation Strategy

Option A: **Dual-Path Approach** (Recommended)
- Add conditional notes at the beginning of each affected section
- Use color-coded boxes (Blue for Single-Site, Purple for Multi-Site)
- Keep instructions in the same section with clear branching

Option B: **Tabbed Interface**
- Requires JavaScript modification
- More complex but cleaner UI
- Higher effort

## Decision: Go with Option A (Conditional Notes)

## Update Order
1. Section 03 - CockroachDB Setup (CRITICAL)
2. Section 04 - SQL Testing
3. Section 05 - HA & Failover
4. Section 06 - HAProxy
5. Section 09 - Security (TLS)
6. Update scripts (generate_certs.sh)

## Notes for Future
- Consider adding a "deployment mode" selector that persists across sections
- Could add local storage to remember user's choice (Single vs Multi-Site)
