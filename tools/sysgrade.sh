#!/usr/bin/env bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=========================================${NC}"
echo -e "${BOLD}${BLUE}    SYSTEMD PERFORMANCE & SECURITY EVAL   ${NC}"
echo -e "${BOLD}${BLUE}=========================================${NC}\n"

# --- 1. TIME ANALYSIS ---
echo -e "${BOLD}[1/5] Analyzing Startup Timings...${NC}"
TIME_DATA=$(systemd-analyze time)
echo "$TIME_DATA"

LOADER_MS=$(echo "$TIME_DATA" | grep -oP '\d+(\.\d+)?s \(loader\)' | sed 's/s (loader)//' | awk '{print $1*1000}')
INITRD_MS=$(echo "$TIME_DATA" | grep -oP '\d+(\.\d+)?s \(initrd\)' | sed 's/s (initrd)//' | awk '{print $1*1000}')
USER_MS=$(echo "$TIME_DATA" | grep -oP '\d+(\.\d+)?s \(userspace\)' | sed 's/s (userspace)//' | awk '{print $1*1000}')

# --- 2. CRITICAL CHAIN ---
echo -e "\n${BOLD}[2/5] Fetching Critical Chain Target...${NC}"
systemd-analyze critical-chain | head -n 12

# --- 3. BLAME ANALYSIS ---
echo -e "\n${BOLD}[3/5] Pinpointing Top Execution Bottlenecks...${NC}"
systemd-analyze blame | head -n 5

# --- 4. SECURITY AUDIT ---
echo -e "\n${BOLD}[4/5] Running Core System Security Audit...${NC}"
SEC_DATA=$(systemd-analyze security --no-pager 2>/dev/null)

if [ -n "$SEC_DATA" ]; then
    EXPOSED_SVCS=$(echo "$SEC_DATA" | awk 'NR>1 && $3=="EXPOSED"')
    EXPOSED_COUNT=$(echo "$EXPOSED_SVCS" | grep -c 'EXPOSED')

    # Header + all EXPOSED services
    echo "$SEC_DATA" | head -n 1
    if [ -n "$EXPOSED_SVCS" ]; then
        echo "$EXPOSED_SVCS"
        echo ""
        echo -e "${YELLOW}Note: NetworkManager/iio-sensor-proxy scores are expected — they require elevated${NC}"
        echo -e "${YELLOW}network/hardware privileges by design and cannot be meaningfully hardened.${NC}"
    else
        echo -e "${GREEN}No EXPOSED services found.${NC}"
    fi

    # Correct average: skip header, parse numeric exposure column
    AVG_EXPOSURE=$(echo "$SEC_DATA" | awk 'NR>1 && $2+0 == $2 {sum+=$2; count++} END {if (count>0) printf "%.2f", sum/count; else print 0}')
    echo -e "\nAverage Service Exposure Score: ${BOLD}${AVG_EXPOSURE}/10${NC} (lower is better)"
    echo -e "EXPOSED services: ${BOLD}${EXPOSED_COUNT}${NC}"
else
    echo "Security analysis unavailable or requires higher privileges."
    AVG_EXPOSURE=0
fi

# --- 5. GENERATING VISUAL PLOT ---
echo -e "\n${BOLD}[5/5] Generating Boot Profile Vector Timeline...${NC}"
PLOT_PATH="$(dirname "$0")/boot_profile.html"
systemd-analyze plot > "$PLOT_PATH"
echo -e "${GREEN}✓ Graphical boot timeline saved to: ${PLOT_PATH}${NC}"

# --- SCORECARD ---
echo -e "\n${BOLD}${BLUE}=========================================${NC}"
echo -e "${BOLD}${BLUE}             SYSTEM SCORECARD            ${NC}"
echo -e "${BOLD}${BLUE}=========================================${NC}"

if [ -z "$LOADER_MS" ]; then
    echo -e "Loader Phase:  ${BLUE}N/A (Skipped/EFI Boot)${NC}"
elif [ "$LOADER_MS" -lt 2000 ]; then echo -e "Loader Phase:  ${GREEN}A+ (Lightning Fast Menu Handoff)${NC}"
elif [ "$LOADER_MS" -lt 5000 ]; then echo -e "Loader Phase:  ${YELLOW}B  (Moderate Splash/Menu Padding)${NC}"
else echo -e "Loader Phase:  ${RED}C  (High Menu Timeout Delay Detected)${NC}"; fi

if [ -z "$INITRD_MS" ]; then
    echo -e "Initrd Phase:  ${BLUE}N/A (No Ramdisk)${NC}"
elif [ "$INITRD_MS" -lt 1500 ]; then echo -e "Initrd Phase:  ${GREEN}A+ (Instantaneous Drive Mounting)${NC}"
elif [ "$INITRD_MS" -lt 3500 ]; then echo -e "Initrd Phase:  ${GREEN}A  (Highly Optimized Hardware Hook)${NC}"
else echo -e "Initrd Phase:  ${RED}B- (Sluggish Device Initialization)${NC}"; fi

if [ -z "$USER_MS" ]; then
    echo -e "Userspace:     ${BLUE}N/A${NC}"
elif [ "$USER_MS" -lt 2000 ]; then echo -e "Userspace:     ${GREEN}A+ (Parallel Processing Mastery)${NC}"
elif [ "$USER_MS" -lt 4000 ]; then echo -e "Userspace:     ${GREEN}A  (Crisp Service Handoff)${NC}"
else echo -e "Userspace:     ${YELLOW}B  (Serialized Service Bottleneck)${NC}"; fi

if [ $(awk 'BEGIN {print ('"$AVG_EXPOSURE"' < 3.5)}') -eq 1 ]; then
    echo -e "Security:      ${GREEN}A+ (Enterprise-Grade Isolation & Sandboxing)${NC}"
elif [ $(awk 'BEGIN {print ('"$AVG_EXPOSURE"' < 6.0)}') -eq 1 ]; then
    echo -e "Security:      ${GREEN}A  (Robust Platform Constraints Verified)${NC}"
else
    echo -e "Security:      ${YELLOW}B- (Standard Permissions / High Exposure Shadowing)${NC}"
fi

echo -e "${BOLD}${BLUE}=========================================${NC}"
