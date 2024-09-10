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

# Export contact points from source Grafana instance
source_contact_points="$(curl -s \
    -H "Authorization: Bearer $source_bearer" \
    "https://$source_address/grafana/api/v1/provisioning/contact-points"
)"

# Contact points in the target Grafana
target_contact_points="$(curl -s \
    -H "Authorization: Bearer $target_bearer" \
    "https://$target_address/grafana/api/v1/provisioning/contact-points"
)"

declare -A target_contact_name_to_uid

filtered_contact_points=$(echo "$target_contact_points" | jq -r -c 'del(.[] | select(.name == "email receiver")) | .[]')

if [ -n "$filtered_contact_points" ]; then
    while read -r target_contact_point;
    do 
        name="$(echo "$target_contact_point" | jq -r '.name' | xargs)"
        uid="$(echo "$target_contact_point" | jq -r '.uid' | xargs)"
        echo $name
        echo $uid
        target_contact_name_to_uid[$name]=$uid
    done <<< "$filtered_contact_points"
fi

echo "$source_contact_points" | jq -r -c 'del(.[] | select(.name == "email receiver")) | .[]' | while read -r source_contact_point;
do  
    source_contact_point_name=$(echo "$source_contact_point" | jq -r '.name' | xargs)
    source_contact_point_export="$(echo $source_contact_point | jq -r 'del(.uid)')"
    
    # Import contact points
    curl -s \
        -d "$source_contact_point_export" \
        -H 'X-Disable-Provenance: true' \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -H "Authorization: Bearer $target_bearer" \
        "https://$target_address/grafana/api/v1/provisioning/contact-points"
    
    if [[ -v "target_contact_name_to_uid[$source_contact_point_name]" ]]; then
        curl -s \
            --request "DELETE" \
            -H "Authorization: Bearer $target_bearer" \
            "https://$target_address/grafana/api/v1/provisioning/contact-points/${target_contact_name_to_uid[$source_contact_point_name]}"
    fi
done

# Get all folders from source Grafana
source_folders="$(curl -s \
    -H "Authorization: Bearer $source_bearer" \
    "https://$source_address/grafana/api/folders")"

# Get all the target folders
target_folders="$(curl -s \
    -H "Authorization: Bearer $target_bearer" \
    "https://$target_address/grafana/api/folders")"

echo "$source_folders" | jq -r -c '.[]' | while read -r source_folder;
do  
    source_folder_title=$(echo "$source_folder" | jq -r '.title' | xargs)
    curl -s \
        -d '{"title": "'"$source_folder_title"'"}' \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -H "Authorization: Bearer $target_bearer" \
        "https://$target_address/grafana/api/folders"
done

source_alerts="$(curl -s \
    -H "Authorization: Bearer $source_bearer" \
    "https://$source_address/grafana/api/v1/provisioning/alert-rules")"

target_alerts="$(curl -s \
    -H "Authorization: Bearer $target_bearer" \
    "https://$target_address/grafana/api/v1/provisioning/alert-rules")"

echo "$source_alerts" | jq -r -c '.[]' | while read -r source_alert;
do  
    source_alert_title="$(echo "$source_alert" | jq -r '.title')"
    source_folder_uid="$(echo "$source_alert" | jq -r '.folderUID')"
    source_folder_title="$(echo "$source_folders" | jq -r --arg folder_uid "$source_folder_uid" '.[] | select(.uid==$folder_uid) | .title' | xargs)"

    # Ensure target_folder_uid is retrieved correctly
    target_folder_uid="$(echo "$target_folders" | jq -r --arg folder_title "$source_folder_title" '.[] | select(.title == $folder_title) | .uid' | xargs)"

    # Update source_alert with the new folderUID and remove unnecessary fields
    source_alert_export="$(echo "$source_alert" | jq -r -c 'del(.uid, .updated) | .folderUID=$new_folder_uid' --arg new_folder_uid "$target_folder_uid")"

    # Fetch existing target_alert_uid if it exists
    target_alert_uid="$(echo "$target_alerts" | jq -r --arg folder_uid "$target_folder_uid" --arg alert_title "$source_alert_title" '.[] | select(.title == $alert_title and .folderUID == $folder_uid) | .uid' | xargs)"

    # Conditional deletion of the existing alert if its UID is found
    if [ "$target_alert_uid" != "null" ] && [ "$target_alert_uid" != "" ]; then
        curl -s \
            --request "DELETE" \
            -H "Authorization: Bearer $target_bearer" \
            "https://$target_address/grafana/api/v1/provisioning/alert-rules/$target_alert_uid"
    fi

    # Import the modified alert
    curl -s \
        -d "$source_alert_export" \
        -H 'X-Disable-Provenance: true' \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -H "Authorization: Bearer $target_bearer" \
        "https://$target_address/grafana/api/v1/provisioning/alert-rules"
done
