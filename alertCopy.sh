#!/bin/bash
# ./alertCopy.sh bearerOrginal bearerCopy urlOrginal urlCopy

t_provided=0
T_provided=0
s_provided=0
S_provided=0
target_address=""
target_bearer=""
source_address=""
source_bearer=""

while getopts 't:T:s:S:' OPTION; do
    case "$OPTION" in
        t)
            target_address="$OPTARG"
            t_provided=1
            ;;
        T)
            target_bearer="$OPTARG"
            T_provided=1
            ;;
        s)
            source_address="$OPTARG"
            s_provided=1
            ;;
        S)
            source_bearer="$OPTARG"
            S_provided=1
            ;;
        ?)
            usage
            ;;
    esac
done
shift "$(($OPTIND -1))"

usage() {
    echo "Usage: $0 -t <target_address> -T <target_bearer> -s <source_address> -S <source_bearer>"
    exit 1
}

if [ "$t_provided" -eq 0 ] || [ "$T_provided" -eq 0 ] || [ "$s_provided" -eq 0 ] || [ "$S_provided" -eq 0 ]; then
    echo "Error: All options must be provided."
    echo "You must specify target and source URLs and bearers."
    usage
fi

verify_token() {
    local source_bearer=$1
    local source_address=$2
    local target_bearer=$3
    local target_address=$4
    source_response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $source_bearer" "https://$source_address/api/v1/provisioning/contact-points")
    target_response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $target_bearer" "https://$target_address/api/v1/provisioning/contact-points")
    if [ "$source_response" == 404 ]; then
        echo "404 Error: Source URL is incorrect."
        exit 1
    elif [ "$source_response" == 401 ]; then
        echo "401 Error: Source token is incorrect."
        exit 1
    fi
    if [ "$target_response" == 404 ]; then
        echo "404 Error: Target URL is incorrect."
        exit 1
    elif [ "$target_response" == 401 ]; then
        echo "401 Error: Target token is incorrect."
        exit 1
    fi
}

#Function to copy contact points from source instance to target instance. Adds contact points that exist in the source instance but not in the target instance. Keeps contact points that only exists in the target instance. If a contact point with the same name already exists in the target instance, it will be replaced by the source instance contact point.
copy_contact_points() {
    # Define local variables for source and target Grafana instances
    local source_bearer=$1
    local source_address=$2
    local target_bearer=$3
    local target_address=$4

    # Fetch contact points from source Grafana instance
    source_contact_points="$(curl -s \
        -H "Authorization: Bearer $source_bearer" \
        "https://$source_address/api/v1/provisioning/contact-points"
    )"

    # Fetch contact points from target Grafana instance
    target_contact_points="$(curl -s \
        -H "Authorization: Bearer $target_bearer" \
        "https://$target_address/api/v1/provisioning/contact-points"
    )"

    # Declare an associative array to map contact point names to their UIDs in the target instance
    declare -A target_contact_name_to_uid

    # Filter out the "email receiver" contact point from the target contact points
    filtered_contact_points=$(echo "$target_contact_points" | jq -r -c 'del(.[] | select(.name == "email receiver")) | .[]')

    # If there are any contact points left, map their names to their UIDs
    if [ -n "$filtered_contact_points" ]; then
        while read -r target_contact_point;
        do 
            name="$(echo "$target_contact_point" | jq -r '.name' | xargs)"
            uid="$(echo "$target_contact_point" | jq -r '.uid' | xargs)"
            target_contact_name_to_uid[$name]=$uid
        done <<< "$filtered_contact_points"
    fi

    # For each source contact point (excluding "email receiver"), import it to the target instance
    echo "$source_contact_points" | jq -r -c 'del(.[] | select(.name == "email receiver")) | .[]' | while read -r source_contact_point;
    do  
        source_contact_point_name=$(echo "$source_contact_point" | jq -r '.name' | xargs)
        source_contact_point_export="$(echo $source_contact_point | jq -r 'del(.uid)')"

        # Import the source contact point to the target instance. Source contact point already exists in the target it will be added as a contact point integration.
        curl -s \
            -d "$source_contact_point_export" \
            -H 'X-Disable-Provenance: true' \
            -H 'Content-Type: application/json' \
            cd .. \
            -H "Authorization: Bearer $target_bearer" \
            "https://$target_address/api/v1/provisioning/contact-points"
        
        # If the source contact point already exists in the target instance, delete it.(Now, the contact point integration that was added replaces the orginal contact point)
        if [[ -v "target_contact_name_to_uid[$source_contact_point_name]" ]]; then
            curl -s \
                --request "DELETE" \
                -H "Authorization: Bearer $target_bearer" \
                "https://$target_address/api/v1/provisioning/contact-points/${target_contact_name_to_uid[$source_contact_point_name]}"
        fi
    done
}

#Function to copy notification policies from source instance to target instance. All notification policies in the target instance(doesn't matter the policy) will be replaced by the source instance notification policies.
copy_notification_policies() {
    # Define local variables for source and target Grafana instances
    local source_bearer=$1
    local source_address=$2
    local target_bearer=$3
    local target_address=$4

    # Fetch notification policy tree from source Grafana instance
    source_notification_policies_export="$(curl -s \
        -H 'Accept: application/json' \
        -H "Authorization: Bearer $source_bearer" \
        "https://$source_address/api/v1/provisioning/policies" )"

    # Push the fetched notification policy tree to the target Grafana instance. It replaces the notification policy tree in the target instance.
    curl -s \
        --request "PUT"\
        -d "$source_notification_policies_export"\
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -H 'X-Disable-Provenance: true' \
        -H "Authorization: Bearer $target_bearer" \
        "https://$target_address/api/v1/provisioning/policies"
}

#Function to copy folders from source instance to target instance. Adds folders that exist in the source instance but not in the target instance. Keeps folders that only exists in the target instance.
copy_folders() {
    # Define local variables for source and target Grafana instances
    local source_bearer=$1
    local source_address=$2
    local target_bearer=$3
    local target_address=$4

    # Fetch all folders from source Grafana instance
    source_folders="$(curl -s \
        -H "Authorization: Bearer $source_bearer" \
        "https://$source_address/api/folders")"

    # For each folder in the source Grafana instance
    echo "$source_folders" | jq -r -c '.[]' | while read -r source_folder;
    do  
        # Extract the folder title
        source_folder_title=$(echo "$source_folder" | jq -r '.title' | xargs)
        
        # Create a new folder with the same title in the target Grafana instance. If a folder with the same title already exists nothing will happen.
        curl -s \
            -d '{"title": "'"$source_folder_title"'"}' \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json' \
            -H "Authorization: Bearer $target_bearer" \
            "https://$target_address/api/folders"
    done
}

#Function to copy alerts from source instance to target instance. Adds alerts that exist in the source instance but not in the target instance. Keeps alerts that only exists in the target instance. If an alert with the same title and folder UID already exists in the target instance, it will be replaced by the source instance alert.
copy_alerts() {
    # Define local variables for source and target Grafana instances
    local source_bearer=$1
    local source_address=$2
    local target_bearer=$3
    local target_address=$4

    # Fetch all folders from target Grafana instance
    target_folders="$(curl -s \
        -H "Authorization: Bearer $target_bearer" \
        "https://$target_address/api/folders")"

    # Fetch all alert rules from source Grafana instance
    source_alerts="$(curl -s \
        -H "Authorization: Bearer $source_bearer" \
        "https://$source_address/api/v1/provisioning/alert-rules")"

    # Fetch all alert rules from target Grafana instance
    target_alerts="$(curl -s \
        -H "Authorization: Bearer $target_bearer" \
        "https://$target_address/api/v1/provisioning/alert-rules")"

    # For each alert rule in the source Grafana instance
    echo "$source_alerts" | jq -r -c '.[]' | while read -r source_alert;
    do  
        # Extract the alert title and folder UID
        source_alert_title="$(echo "$source_alert" | jq -r '.title')"
        source_folder_uid="$(echo "$source_alert" | jq -r '.folderUID')"

        # Find the title of the folder that contains the alert
        source_folder_title="$(echo "$source_folders" | jq -r --arg folder_uid "$source_folder_uid" '.[] | select(.uid==$folder_uid) | .title' | xargs)"

        # Find the UID of the folder in the target Grafana instance that has the same title
        target_folder_uid="$(echo "$target_folders" | jq -r --arg folder_title "$source_folder_title" '.[] | select(.title == $folder_title) | .uid' | xargs)"

        # Update the folder UID in the alert rule and remove unnecessary fields
        source_alert_export="$(echo "$source_alert" | jq -r -c 'del(.uid, .updated) | .folderUID=$new_folder_uid' --arg new_folder_uid "$target_folder_uid")"

        # Check if an alert rule with the same title and folder UID already exists in the target Grafana instance
        target_alert_uid="$(echo "$target_alerts" | jq -r --arg folder_uid "$target_folder_uid" --arg alert_title "$source_alert_title" '.[] | select(.title == $alert_title and .folderUID == $folder_uid) | .uid' | xargs)"

        # If such an alert rule exists in target instance, delete it
        if [ "$target_alert_uid" != "null" ] && [ "$target_alert_uid" != "" ]; then
            curl -s \
                --request "DELETE" \
                -H "Authorization: Bearer $target_bearer" \
                "https://$target_address/api/v1/provisioning/alert-rules/$target_alert_uid"
        fi

        # Import the modified alert rule into the target Grafana instance
        curl -s \
            -d "$source_alert_export" \
            -H 'X-Disable-Provenance: true' \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json' \
            -H "Authorization: Bearer $target_bearer" \
            "https://$target_address/api/v1/provisioning/alert-rules"
    done
}

verify_token "$source_bearer" "$source_address" "$target_bearer" "$target_address"
copy_contact_points "$source_bearer" "$source_address" "$target_bearer" "$target_address"
copy_notification_policies "$source_bearer" "$source_address" "$target_bearer" "$target_address"
copy_folders "$source_bearer" "$source_address" "$target_bearer" "$target_address"
copy_alerts "$source_bearer" "$source_address" "$target_bearer" "$target_address"
