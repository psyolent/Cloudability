#!/bin/bash

# Teams Anomaly Integration
# Get via API the previous days anomalies                   ``
# Endpoint https://api.cloudability.com/v3/anomalies?endDate=CurrentDayinUSFormat&startDate=PreviousDayinUSFormat&viewId=0
# Example Data
# {
#    "result": [
#        {
#            "date": "2024-07-04",
#            "type": "1-Day",
#            "enhancedServiceName": "AWS CloudWatch",
#            "usageFamily": "Data Transfer",
#            "unblendedCost": "25.00",
#            "unusualSpend": "20.00",
#            "vendorAccountName": "MyAWSTestAcount",
#            "tags": [],
#            "businessDimensions": []
#        }
#    ]
# }
# This requires a Workflow to be configured in MS Teams against a channel

# Configuration
TEAMS_WORKFLOW_URL="TEAMS HTTP URL"
LOG_FILE="/Users/path/to/logfile/logfile.log"
API_AUTH="CLDYAPITOKEN:"

# Function to get the current and previous day in YYYY-MM-DD format
get_dates() {
    current_day=$(date +"%Y-%m-%d")
    
    # Check if GNU date is available
    if date --version >/dev/null 2>&1; then
        previous_day=$(date -d "yesterday" +"%Y-%m-%d")
        start_date=$(date -d "30 days ago" +"%Y-%m-%d")
    else
        previous_day=$(date -v-1d +"%Y-%m-%d")
        start_date=$(date -v-30d +"%Y-%m-%d")
    fi
}

# URL encode function using jq
url_encode() {
    jq -nr --arg v "$1" '$v|@uri'
}

# Call the function to set date variables
get_dates

# Define the API endpoint with dynamic dates
API_ENDPOINT="https://api.cloudability.com/v3/anomalies?endDate=${current_day}&startDate=${previous_day}&viewId=0"

# Logging function
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

log "Starting API to Teams script."

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
        
        # URL encode the parameters
        encodedEnhancedServiceName=$(url_encode "$enhancedServiceName")
        encodedUsageFamily=$(url_encode "$usageFamily")
        encodedVendorAccountName=$(url_encode "$vendorAccountName")
        
        # Format the message using Markdown
        report_url="https://app-au.apptio.com/cloudability#/reports/report?dimensions=date,transaction_type,vendor_account_name&end_date=$current_day&filters=enhanced_service_name%3D%3D$encodedEnhancedServiceName&filters=usage_family%3D%3D$encodedUsageFamily&filters=vendor_account_name%3D%3D$encodedVendorAccountName&limit=0&metrics=unblended_cost&order=asc&sort_by=date&start_date=$start_date&title=Anomaly+Report"
        message="**Spend Alert**\n\n**Date:** $date\n\n**Type:** $type\n\n**Service Name:** $enhancedServiceName\n\n**Usage Family:** $usageFamily\n\n**Unblended Cost:** \$$unblendedCost\n\n**Unusual Spend:** \$$unusualSpend\n\n**Vendor Account:** $vendorAccountName\n\n[Click to View Details]($report_url)"
        
        # Send the message to Teams
        curl -X POST -H 'Content-Type: application/json' \
             --data "{\"text\":\"$message\"}" \
             "$TEAMS_WORKFLOW_URL"
        log "Message sent to Teams for anomaly $i."
    done
else
    log "Failed to retrieve data. HTTP status code: $http_code"
    # Optionally send an error message to Teams
    curl -X POST -H 'Content-Type: application/json' \
         --data "{\"text\":\"Failed to retrieve data. HTTP status code: $http_code\"}" \
         "$TEAMS_WORKFLOW_URL"
fi

log "Script execution finished."