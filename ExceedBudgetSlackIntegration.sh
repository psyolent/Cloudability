#!/bin/bash

# Budget Alert Code
# Pre-Requisites - JQ must be available and in your path
# Need a valid Cloudability API Key
# Need a defined Slack Channel and Incoming Webhook URL

# Configuration
API_AUTH="TOKEN:"
LOG_FILE="/path/to/log/file/logfile.log"
OUTPUT_FILE="./estimates.json"
VIEW_API_ENDPOINT="https://api.cloudability.com/v3/views"
ESTIMATE_API_ENDPOINT="https://api.cloudability.com/v3/estimate"
BUDGET_API_ENDPOINT="https://api.cloudability.com/v3/budgets"
SLACK_WEBHOOK_URL="INCOMING_SLACK_WEBHOOK"

# Function for Logging
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

# Function to send Slack notifications
send_slack_notification() {
    local message="$1"
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$message\"}" "$SLACK_WEBHOOK_URL"
}

# Function to make API call and retry if throttled
make_api_call() {
    local url="$1"
    local response

    response=$(curl -s -u "$API_AUTH" -H "Accept: application/json" "$url")
    if [[ -z "$response" ]]; then
        log "API call to $url failed. Retrying after a delay..."
        sleep 10
        response=$(curl -s -u "$API_AUTH" -H "Accept: application/json" "$url")
    fi

    echo "$response"
}

log "Starting API call to retrieve budgets."

# Make the API call to retrieve budgets
budget_response=$(make_api_call "$BUDGET_API_ENDPOINT")

# Check if the response is not empty
if [[ -z "$budget_response" ]]; then
    log "Failed to retrieve budget data."
    exit 1
fi

log "Budget API call successful. Processing JSON data."

# Extract current month in YYYY-MM format
current_month=$(date +"%Y-%m")

# Loop through each budget
echo "$budget_response" | jq -c '.result[]' | while read -r budget; do
    view_id=$(echo "$budget" | jq -r '.viewId')
    threshold=$(echo "$budget" | jq -r --arg current_month "$current_month" '.months[] | select(.month == $current_month) | .threshold')
    budget_name=$(echo "$budget" | jq -r '.name')
    
    # Skip if no threshold is found for the current month
    if [[ -z "$threshold" ]]; then
        continue
    fi

    # Retrieve the view name using the viewId
    view_response=$(make_api_call "${VIEW_API_ENDPOINT}?id=${view_id}")

    view_name=$(echo "$view_response" | jq -r --arg view_id "$view_id" '.result[] | select(.id == $view_id) | .title')

    # Call the estimates API endpoint using the viewId
    todays_date=$(date +"%Y-%m-%d")
    estimate_url="${ESTIMATE_API_ENDPOINT}?basis=adjustedAmortized&date=${todays_date}&newStructure=true&viewId=${view_id}"
    estimate_response=$(make_api_call "$estimate_url")
    
    estimated_spend=$(echo "$estimate_response" | jq -r '.result.estimatedSpend')

    # Compare the estimated spend with the threshold
    if [[ -n "$estimated_spend" && $(echo "$estimated_spend > $threshold" | bc -l) -eq 1 ]]; then
        message="Alert: Estimated spend (\$${estimated_spend}) for view ID ${view_id} (${view_name}) exceeds the budget threshold (\$${threshold}) for budget ${budget_name} for the current month (${current_month})."
        send_slack_notification "$message"
        log "$message"
    fi
done

log "Script execution finished."
