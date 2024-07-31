#!/bin/bash

# Slack Anomaly Integration
# Pre-Requisite - must have JQ installed
# Must have a Slack Incoming Webhook setup to receive the alerts
# Get via API the previous days anomalies
# Endpoint https://api.cloudability.com/v3/anomalies?endDate=CurrentDayinUSFormat&startDate=PreviousDayinUSFormat&viewId=0

# Configuration
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/SLACKWEBHOOK"
LOG_FILE="/path/to/logfile/logfile.log"
API_AUTH="CLDYAPIKEY:"

# Function to get the current and previous day in YYYY-MM-DD format
get_dates() {
    current_day=$(date +"%Y-%m-%d")
    
    # Check if GNU date is available
    if date --version >/dev/null 2>&1; then
        previous_day=$(date -d "yesterday" +"%Y-%m-%d")
    else
        previous_day=$(date -v-1d +"%Y-%m-%d")
    fi
}

# Call the function to set date variables
get_dates

# Define the API endpoint with dynamic dates
API_ENDPOINT="https://api.cloudability.com/v3/anomalies?endDate=${current_day}&startDate=${previous_day}&viewId=0"

# Logging function
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

log "Starting API to Slack script."

# Log the API endpoint being used
log "API endpoint: $API_ENDPOINT"

# Make the API call and store the response
response=$(curl -s -u "$API_AUTH" "$API_ENDPOINT")
http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$API_AUTH" "$API_ENDPOINT")

# Log the full response for debugging
log "API response: $response"

# Check if the API call was successful (HTTP status code 200)
if [[ "$http_code" -eq 200 ]]; then
    # Parse the response to extract relevant information
    length=$(echo "$response" | jq '.result | length')

    for ((i=0; i<$length; i++)); do
        date=$(echo "$response" | jq -r ".result[$i].date")
        type=$(echo "$response" | jq -r ".result[$i].type")
        enhancedServiceName=$(echo "$response" | jq -r ".result[$i].enhancedServiceName")
        usageFamily=$(echo "$response" | jq -r ".result[$i].usageFamily")
        unblendedCost=$(echo "$response" | jq -r ".result[$i].unblendedCost")
        unusualSpend=$(echo "$response" | jq -r ".result[$i].unusualSpend")
        vendorAccountName=$(echo "$response" | jq -r ".result[$i].vendorAccountName")
        
        # Format the message
        message="*AWS Spend Alert*\n
                 *Date:* $date\n
                 *Type:* $type\n
                 *Service Name:* $enhancedServiceName\n
                 *Usage Family:* $usageFamily\n
                 *Unblended Cost:* \$$unblendedCost\n
                 *Unusual Spend:* \$$unusualSpend\n
                 *Vendor Account:* $vendorAccountName"
        
        # Send the message to Slack
        curl -X POST -H 'Content-type: application/json' \
             --data "{\"text\":\"$message\"}" \
             "$SLACK_WEBHOOK_URL"
        log "Message sent to Slack for anomaly $i."
    done
else
    log "Failed to retrieve data. HTTP status code: $http_code"
    # Optionally send an error message to Slack
    curl -X POST -H 'Content-type: application/json' \
         --data "{\"text\":\"Failed to retrieve data. HTTP status code: $http_code\"}" \
         "$SLACK_WEBHOOK_URL"
fi

log "Script execution finished."
