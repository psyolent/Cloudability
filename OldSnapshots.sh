#!/bin/bash

# This script will output a list of AWS EBS snapshots that exist in your environment that are > 30 days old
# Note the dataset is from two days prior to account for data ingestion & global TZ differences.  
# You must have JQ installed and in your path for this to function.

# Cloudability API endpoint and credentials
API_ENDPOINT="https://api.cloudability.com/v3/internal/reporting/cost/run"
api_auth="cldy_api_key:"

# Dates for filtering
today=$(date -v-1d +%Y-%m-%d)
yesterday=$(date -v-2d +%Y-%m-%d)
two_days_ago=$(date -v-3d +%Y-%m-%d)
thirty_days_ago=$(date -v-31d +"%Y-%m-%d")

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found, please install jq."
    exit 1
fi

# Function to get report data
get_report_data() {
    local token=$1
    local url="$API_ENDPOINT"
    
    if [ -n "$token" ]; then
        url="$url&tokenId=$token"
    fi
    
    curl -s -G \
        -u "$api_auth" \
        -H "Content-Type: application/json" \
        --data-urlencode "dimensions=resource_identifier" \
        --data-urlencode "dimensions=date" \
        --data-urlencode "end=$today" \
        --data-urlencode "filters=resource_identifier=@snapshot/snap-" \
        --data-urlencode "limit=1000" \
        --data-urlencode "metrics=unblended_cost" \
        --data-urlencode "start=$thirty_days_ago" \
        --data-urlencode "viewId=0" \
        "$url"
}

# Fetch and aggregate all paginated data
all_data="[]"
token=""

while true; do
    response=$(get_report_data "$token")
    
    if [[ -z "$response" ]]; then
        echo "No data received from the API."
        exit 1
    fi
    
    # Extract rows and add to all_data
    rows=$(echo "$response" | jq '.rows')
    all_data=$(echo "$all_data" | jq --argjson rows "$rows" '. + $rows')
    
    # Check for next pagination token
    token=$(echo "$response" | jq -r '.pagination.next // empty')
    if [[ -z "$token" ]]; then
        break
    fi
done

# Save the aggregated data to a JSON file
echo "$all_data" > report_data.json

# Process the data
snapshots_recent=$(echo "$all_data" | jq -r --arg today "$today" --arg yesterday "$yesterday" --arg two_days_ago "$two_days_ago" '[.[] | select(.dimensions[1] == $today or .dimensions[1] == $yesterday or .dimensions[1] == $two_days_ago) | .dimensions[0]] | unique' 2>error.log)
snapshots_thirty_days_ago=$(echo "$all_data" | jq -r --arg thirty_days_ago "$thirty_days_ago" '[.[] | select(.dimensions[1] == $thirty_days_ago) | .dimensions[0]] | unique' 2>>error.log)

# Compare snapshots
existing_snapshots=()
snapshots_recent_array=($(echo "$snapshots_recent" | jq -r '.[]'))
snapshots_thirty_days_ago_array=($(echo "$snapshots_thirty_days_ago" | jq -r '.[]'))

for snapshot_id in "${snapshots_recent_array[@]}"; do
    if [[ " ${snapshots_thirty_days_ago_array[@]} " =~ " ${snapshot_id} " ]]; then
        existing_snapshots+=("$snapshot_id")
    fi
done

# Output the results
echo "The following Snapshots are > 30 days old:"
for snapshot_id in "${existing_snapshots[@]}"; do
    echo "$snapshot_id"
done

# Clean up
rm report_data.json

# Check for errors
if [ -s error.log ]; then
    echo "Errors occurred during processing. Check error.log for details."
    rm error.log
fi
