#!/bin/bash

# Pre-Requisite. You must have JQ installed for this code to work. 
# API_AUTH must have a valid Cldy API key remember the : on the end.
# LOG_FILE must have a valid path for output.
# You must have an incoming webhook destination setup in Slack as well to accept the message

# Configuration
API_ENDPOINT="https://api.cloudability.com/v3/reservations/aws/portfolio/savingsPlan"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/SLACKINCOMINGWEBHOOK"
LOG_FILE="/path/to/logile/logfile.log"
API_AUTH="APIKEY:"

# Logging function
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

log "Starting API to Slack script."

# Make API call and put into response var
response=$(curl -s -u "$API_AUTH" -H "Accept: application/json" "$API_ENDPOINT")

# Make sure we got data
if [[ -z "$response" ]]; then
    log "Failed to retrieve JSON data."
    exit 1
fi

log "API call successful. Processing JSON data."

# Optional - un remark the next line to output the response into the logfile
# log "JSON response: $response"

# Get today's date in epoch 
today_epoch=$(date +%s)

# Check that the SP is active and parse with JQ
echo "$response" | jq -c '.result[] | select(.state == "active") | {accountName: .accountName, vendorAccountId: .vendorAccountId, savingsPlanId: .savingsPlanId, description: .description, end: .end}' | while read -r item; do
    end_date=$(echo "$item" | jq -r '.end')
    days_left=$(( (end_date / 1000 - today_epoch) / 86400 ))

    if [[ "$days_left" -lt 30 ]]; then
        account_name=$(echo "$item" | jq -r '.accountName')
        account_id=$(echo "$item" | jq -r '.vendorAccountId')
        savings_plan_id=$(echo "$item" | jq -r '.savingsPlanId')
        description=$(echo "$item" | jq -r '.description')

        # Convert epoch to normal date time format
        end_date_human=$(date -r $((end_date / 1000)) "+%Y-%m-%d")

        message="*Savings Plan Expiry Alert*\n
                 *Account Name:* $account_name\n
                 *Account ID:* $account_id\n
                 *Savings Plan ID:* $savings_plan_id\n
                 *Description:* $description\n
                 *End Date:* $end_date_human\n
                 *Days Left:* $days_left"

        # Send to Slack
        curl -s -o /dev/null -X POST -H 'Content-type: application/json' \
             --data "{\"text\":\"$message\"}" \
             "$SLACK_WEBHOOK_URL"
        log "Message sent to Slack for savings plan $savings_plan_id."
    fi
done

log "Script execution finished."
