#!/bin/bash

# This script will create views with singular or multiple filters based on tags, dimensions or business mappings
# You must know the tag number, the business mapping category number or the absolute dimension name as inputs to this script
# For example in tag mappings, if your first tag mapping was called Name, then you would reference that as tag1
# A business mapping will be referred to as categoryX where X is the reference to it - in Business Mappings UI click on the mapping and in your address bar the URL will have a number after /detail/ - this represents X
# A dimension absolute name can be found from your address bar when running a report - example Account Name is vendor_account_name 
# You will then need to provide a operator, which can be == (equals) != (not equals) =@ (contains) !=@ (not contains)
# Then a value to match against in the filter
# These will be stored in a CSV files called data.csv which needs to be stored (or the path modified in the code below) alongside with this script
# Example of data file (View Name, Filter Name, Operator, Value)
# Domain - ABC,category11,==,123456,tag1,!=,ABC,vendor_account_name,==,FGH
# Domain - XYZ,tag2,==,789012,vendor_account_name,!=,ABC
# Domain - GFZ,tag1,==,Domain,vendor_account_name,==,Test Account
# You must also add your Cloudability API Key at the bottom of the script after the -u ensuring that the : is left at the end
# Note if you have an already existing View with the same name a 400 error will be received during output, otherwise sucess is depicted by a return code of 201
# The script will also handle CR or LF and , in Excel when a CSV is created in there. If using Excel file must be saved as "CSV UTF-8 (Comma-delimited) (.csv)"

# Read the CSV file
CSV_FILE="data.csv"
if [[ ! -f "$CSV_FILE" ]]; then
    echo "CSV file not found!"
    exit 1
fi

# Debug statement to indicate the start of processing
echo "Starting to process the CSV file: $CSV_FILE"

# Initialize counters for success and failure
success_count=0
failure_count=0

# Read and discard the first line (header)
read -r header < "$CSV_FILE"
echo "Header found and ignored: $header"  # Debug statement

# Read the CSV file line by line, starting from the second line
while IFS= read -r line || [[ -n "$line" ]]; do
    # Remove any trailing whitespace, including spaces, tabs, and carriage returns
    line=$(echo "$line" | sed 's/[[:space:]]*$//')
    echo "Full line read: $line"  # Debug statement

    # Split the line into an array
    IFS=',' read -ra fields <<< "$line"
    
    # Ensure the first field (view name) is not empty
    if [[ -z "${fields[0]}" ]]; then
        echo "Skipping invalid line (empty view name): $line"  # Debug statement
        continue
    fi
    
    # Extract the view name (first field)
    view_name="${fields[0]}"
    echo "Processing view: $view_name"  # Debug statement

    # Initialize filters array
    filters=()

    # Process the rest of the fields for filters
    for ((i=1; i<${#fields[@]}; i+=3)); do
        dimension="${fields[i]}"
        operator="${fields[i+1]}"
        value="${fields[i+2]}"

        # Ensure all parts are valid (including zero)
        if [[ -n "$dimension" || "$dimension" == "0" ]] && [[ -n "$operator" || "$operator" == "0" ]] && [[ -n "$value" || "$value" == "0" ]]; then
            echo "Adding filter - dimension: $dimension, operator: $operator, value: $value"  # Debug statement
            filters+=("{\"field\":\"$dimension\",\"comparator\":\"$operator\",\"value\":\"$value\"}")
        else
            echo "Invalid filter parts found (ignoring): dimension='$dimension', operator='$operator', value='$value'"  # Debug statement
        fi
    done

    # Join the filters array into a JSON array string
    filters_json=$(printf ",%s" "${filters[@]}")
    filters_json="[${filters_json:1}]"

    # Create JSON payload
    json_payload=$(cat <<EOF
{
    "title": "$view_name",
    "sharedWithOrganization": true,
    "sharedWithUsers": [],
    "filters": $filters_json
}
EOF
)
    
    # Debugging output
    echo "JSON payload: $json_payload"
    
    # Create API POST request for each row
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.cloudability.com/v3/views" \
        -H "Content-Type: application/json" \
        -u "APIKEY:" \
        -d "$json_payload")
    
    # Check the API response code
    if [[ "$response" -eq 201 ]]; then
        echo "View created successfully: $view_name"  # Debug statement
        ((success_count++))
    else
        echo "Failed to create view: $view_name (HTTP status code: $response)"  # Debug statement
        ((failure_count++))
    fi

done < <(tail -n +2 "$CSV_FILE")

# Output the summary of successes and failures
echo "Views processing completed!"
echo "Total views successfully created: $success_count"
echo "Total views failed to create: $failure_count"






