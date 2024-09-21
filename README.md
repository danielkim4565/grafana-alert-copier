# grafana-alert-copier

This is a tool designed to copy alerting configurations from one Grafana instance to another. It uses the Grafana API to fetch and import contact points, notification policies and alerts.

## How it works

1. The tool first copies over the contact points from the source Grafana instance.

    - It fetches the contact points from the source Grafana instance and filters out the default created contact point, "email receiver".

    - For each contact point in the source Grafana instance, it exports the contact point (excluding the UID) and imports it to the target Grafana instance.

    - If the contact point already exists in the target Grafana instance, it importing the new one before deleting the existing contact point.

2. The tool then copies the notification policies from the source Grafana instance.

    - It fetches the notification policy tree from the source Grafana instance.

    - It pushs the fetched notification policy tree to the target Grafana instance. 
    
    - It completely replaces the notification policy tree in the target instance(No notification policy in the target instance is saved).

3. The tool then copies the folders from the source Grafana instance.

    - It fetches all folders from the source Grafana instance.

    - For each folder, it exports the folder (excluding the UID) and imports it to the target Grafana instance.

    - If the folder already exists in the target Grafana instance, it will deny the creation.    

4. It also fetches all alerts from the source Grafana instance. 

    * It fetches the export for all alerts in the source Grafana instance. For each alert export:
   
        * It finds the title of the folder that the alert belongs to in the source Grafana instance.

        * It finds the UID of the folder with the same title in the target Grafana instance.

        * It updates the alert export's `folderUID` to the UID of the folder in the target Grafana instance and removes the `uid` and `updated` fields from the alert export.

        * It checks if an alert with the same title and `folderUID` exists in the target Grafana instance. If it does, it deletes that alert.

        * Finally, it imports the updated alert export into the target Grafana instance.


## Prerequisites

- jq: a lightweight and flexible command-line JSON processor.
- curl: a command-line tool for getting or sending data including files using URL syntax.
- xargs: a command-line utility for building and executing command lines from standard input.

## Command Line Arguments

The script accepts the following command line arguments:

- `-S` or `--source-bearer`: The bearer token for the source Grafana instance.
- `-s` or `--source-address`: The address (hostname or IP) of the source Grafana instance.
- `-T` or `--target-bearer`: The bearer token for the target Grafana instance.
- `-t` or `--target-address`: The address (hostname or IP) of the target Grafana instance.

You can pass these arguments to the script in the following way:

```shell
./alertCopy.sh -S <source_bearer> -s <source_address> -T <target_bearer> -t <target_address>
```

## Example

```shell
./alertCopy.sh -S glsa_exampleGlMvU7 -s example.com/grafana -T glsa_exampleGlMvU7 -t example.com/grafana
```

## Note

This tool assumes that you have the necessary permissions to fetch and update the Grafana configurations. Also, it doesn't handle any errors that might occur during the process. You might want to add error handling based on your requirements.