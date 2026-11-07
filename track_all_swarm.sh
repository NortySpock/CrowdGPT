#!/bin/bash

# Configuration
CONTAINER_NAME="crowdgpt"
# Using a case-insensitive regex search pattern to bypass the emoji completely
SEARCH_PATTERN="[Ss]ubmitted [Ss]uccessfully!"

echo "=================================================="
echo "    CrowdGPT Historical & Live Swarm Tracker      "
echo "=================================================="

# --- PHASE 1: HISTORICAL SCAN ---
echo -n "[...] Scanning historical container logs... "

# Use grep -E for robust regex matching over raw container bytes
historical_count=$(sudo docker logs "$CONTAINER_NAME" 2>&1 | grep -E -c "$SEARCH_PATTERN")
success_count=$historical_count

# Calculate tokens (1.47456 Million tokens per successful round)
total_tokens=$(echo "scale=2; $success_count * 1.47456" | bc)
current_time=$(date +"%Y-%m-%d %H:%M:%S")

echo "Done!"
echo -e "Found \e[1;36m$historical_count\e[0m past submissions in log history."
echo "--------------------------------------------------"
echo -e "[$current_time] Initial Baseline: \e[1;32m${total_tokens}M\e[0m tokens processed."
echo "Now monitoring for live updates... Press [CTRL+C] to stop."
echo "--------------------------------------------------"

# Print initial dashboard row
printf "[\e[34m★\e[0m] %s | Total Rounds: \e[1;36m%d\e[0m | Total Contribution: \e[1;32m%sM\e[0m tokens" \
       "$current_time" "$success_count" "$total_tokens"

# --- PHASE 2: LIVE WATCHER ---
# Stream lines live and pass them to grep for robust, immediate processing
sudo docker logs -f --tail 0 "$CONTAINER_NAME" 2>&1 | grep --line-buffered -E "$SEARCH_PATTERN" | while read -r line; do
    ((success_count++))
    
    total_tokens=$(echo "scale=2; $success_count * 1.47456" | bc)
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Update single terminal line in-place
    printf "\r\e[K[\e[32m✓\e[0m] %s | Total Rounds: \e[1;36m%d\e[0m | Total Contribution: \e[1;32m%sM\e[0m tokens" \
           "$current_time" "$success_count" "$total_tokens"
done
