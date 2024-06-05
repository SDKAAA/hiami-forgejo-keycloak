#! /bin/bash

# # in order to copy this file to the container:
# docker cp ./keycloak/cli_init/ $(docker container ls --all --quiet --filter "name=^keycloak$"):/opt/keycloak/
# # make executable
# docker exec --privileged -i keycloak chmod 755 -R /opt/keycloak/cli_init
# # connect to the docker container and then run /opt/keycloak/cli_init/init.sh
# docker exec --privileged -i keycloak sh /opt/keycloak/cli_init/init.sh

# Keycloak Admin CLI documentation is available here: https://www.keycloak.org/docs/latest/server_admin/index.html


# Clients names/IDs start with the app name followed by the instance name
# Groups names start with instance name followed by the group name

#Loading .env variables
set -o allexport
source $(dirname "$0")/2.env
set +o allexport

# Adding Kecloak Path to the path during this session
# export PATH=$PATH:/opt/keycloak/bin
export PATH=$PATH:$keycloak_path

# Config credentials to connect to the keycloak instance
# /opt/keycloak/bin/kcadm.sh config credentials --server "http://localhost:53531" --realm master --user "admin" --password "admin"
kcadm.sh config credentials --server "$keycloak_url" \
  --realm master --user "$KEYCLOAK_ADMIN" --password "$KEYCLOAK_ADMIN_PASSWORD"

# Check if the realm exists already and delete if requiried
# /opt/keycloak/bin/kcadm.sh get realms/Humanitarians --fields id,realm,enabled #--format csv
# realm_check=$(kcadm.sh get realms/Humanitarians --fields id,realm,enabled)
realm_check=$(kcadm.sh get realms/$REALM --fields id,realm,enabled)
# echo $realm_check
if [ -z "$realm_check" ]; then
  echo "Realm '$REALM' does not exist"
else
  echo "Realm '$REALM' already exists"
  # Deleting the realm
  if [ $delete_realm = "true" ]; then
    echo "Deleting realm '$REALM'"
    # kcadm.sh delete realms/Humanitarians
    kcadm.sh delete realms/$REALM
  else
    echo "Not deleting realm!"
  fi
fi

# Create the realm
if [ $create_realm = "true" ]; then
  echo "Creating realm '$REALM'"
  RID=$(kcadm.sh create realms \
    -s realm=$REALM \
    -s enabled=true \
    -s registrationAllowed=true \
    -s resetPasswordAllowed=false \
    -s rememberMe=true \
    -s registrationEmailAsUsername=false \
    -s loginWithEmailAllowed=true \
    -s duplicateEmailsAllowed=false \
    -s verifyEmail=false \
    -s editUsernameAllowed=false \
    -i \
    )
    # 
  echo "Realm '$RID' Created"
else
  echo "Not creating realm!"
fi

# Create Client
echo "Creating client for app '$app_name' instance '$instance'"
CID=$(kcadm.sh create clients \
  -r $REALM \
  -s clientId=$app_name"_"$instance \
  -s enabled=true \
  -s publicClient=false \
  -s 'redirectUris=["'$client_redirect_uris'"]' \
  -s 'webOrigins=["'$client_web_origins'"]' \
  -s protocol=openid-connect \
  -s directAccessGrantsEnabled=true \
  -s serviceAccountsEnabled=true \
  -s authorizationServicesEnabled=true \
  -i
  )
  # -s secret=$client_secret \  # Replaced with secret generation command kcadm.sh create clients/$CID/client-secret -r $REALM

# Generate a New Secret for the client
kcadm.sh create clients/$CID/client-secret -r $REALM

# Update the secret for the sake of not needing to change the FJ config. to be removed for PROD
kcadm.sh update clients/$CID -s "secret=$client_secret" -r $REALM

echo "Client '$app_name"_"$instance' with ID: '$CID' Created"

# Create Group
echo "Creating Group '$group_name' for app '$app_name' instance '$instance'"
GROUP_ID=$(kcadm.sh create groups -r $REALM -s name=$instance"_"$group_name -i)
echo "Group '$instance"_"$group_name' with ID: '$GROUP_ID' Created"

# Add Attribute to group
kcadm.sh update groups/$GROUP_ID -s 'attributes.'$group_attribute_key'=["'$group_attribute_value'"]' -r $REALM

# Create user1 and user 2
echo "Creating User '$user1'"
user1_id=$(kcadm.sh create users -r $REALM -s username=$user1 -s enabled=true -i)
kcadm.sh update users/$user1_id -r $REALM -s 'attributes.email=["'$user1_email'"]' # Currently Not working - Awaiting Community Feedback then Bug Reportk
kcadm.sh update users/$user1_id -r $REALM -s 'attributes.firstName=["'$user1'"]'
kcadm.sh update users/$user1_id -r $REALM -s 'attributes.lastName=["'$user1'"]'
kcadm.sh update users/$user1_id/reset-password -r $REALM -s type=password -s value=$user1_pwd -s temporary=false -n
echo "User '$user1' with ID '$user1_id' created and password set"

echo "Creating User '$user2'"
user2_id=$(kcadm.sh create users -r $REALM -s username=$user2 -s enabled=true -i)
kcadm.sh update users/$user2_id -r $REALM -s 'attributes.email=["'$user2_email'"]' # Currently Not working - Awaiting Community Feedback then Bug Report
kcadm.sh update users/$user2_id -r $REALM -s 'attributes.firstName=["'$user2'"]'
kcadm.sh update users/$user2_id -r $REALM -s 'attributes.lastName=["'$user2'"]'
kcadm.sh update users/$user2_id/reset-password -r $REALM -s type=password -s value=$user2_pwd -s temporary=false -n
echo "User '$user2' with ID '$user2_id' created and password set"

# Check the list of users and their info before adding groups/roles
echo "Listing all users in Realm '$REALM' before adding to groups/roles"
kcadm.sh get users -r $REALM --offset 0 --limit 5

# Add user1 to Group $group_name
echo "Adding user $user1 ($user1_id) to group $instance"_"$group_name ($GROUP_ID)"
kcadm.sh update users/$user1_id/groups/$GROUP_ID -r $REALM -s realm=$REALM -s userId=$user1_id -s groupId=$GROUP_ID -n

# Check group membership of users after adding groups/roles
echo "Listing all groups for user $user1 after adding to groups/roles"
kcadm.sh get users/$user1_id/groups -r $REALM
echo "Listing all groups for user $user2 after adding to groups/roles"
kcadm.sh get users/$user2_id/groups -r $REALM

# Create Client Scope
echo "Creating Client Scope $client_scope"
client_scope_id=$(kcadm.sh create -x "client-scopes" -r $REALM -s name=$client_scope -s protocol=openid-connect -i)
echo "Created new Client Scope $client_scope with id '$client_scope_id'"

# Create 2 Client Scope Mappers
echo "Creating mapper $client_scope_mapper_1_name of type $client_scope_mapper_1_type"
kcadm.sh create client-scopes/$client_scope_id/protocol-mappers/models \
  -r $REALM \
  -s protocol="openid-connect" \
	-s protocolMapper=$client_scope_mapper_1_type \
  -s name=$client_scope_mapper_1_name \
	-s config='{"claim.name" : "'$client_scope_mapper_1_token_claim_name'",
              "full.path" : true,
              "id.token.claim" : true,
              "access.token.claim" : true,
              "lightweight.claim" : false,
              "userinfo.token.claim" : true,
              "introspection.token.claim" : true}'

echo "Creating mapper $client_scope_mapper_2_name of type $client_scope_mapper_2_type"
kcadm.sh create client-scopes/$client_scope_id/protocol-mappers/models \
  -r $REALM \
  -s protocol="openid-connect" \
	-s protocolMapper=$client_scope_mapper_2_type \
  -s name=$client_scope_mapper_2_name \
	-s config='{"user.attribute" : "'$client_scope_mapper_2_user_attribute'",
              "claim.name" : "'$client_scope_mapper_2_token_claim_name'",
              "jsonType.label" : "String",
              "id.token.claim" : true,
              "access.token.claim" : true,
              "lightweight.claim" : true,
              "userinfo.token.claim" : true,
              "introspection.token.claim" : true,
              "multivalued" : false,
              "aggregate.attrs" : false
              }'

# Add Client to client Scopes
echo "Adding Scope $client_scope ($client_scope_id) to client $app_name"_"$instance ($CID)"
kcadm.sh update clients/$CID/default-client-scopes/$client_scope_id  -r $REALM






#########################################
# the below is for reference. to be deleted later

# # Create a group
# GROUP_NAME=$APP-users
# kcadm.sh create groups -r $REALM -s name=$GROUP_NAME 2>&1 | tee "$TMPFILE"
# GROUP_ID=`cat "$TMPFILE" | cut "-d'" -f2`

# # Create a realm role
# ROLE_NAME=$APP-users
# kcadm.sh create roles -r $REALM -s name=$ROLE_NAME -s "description=Regular $APP user"

# # Add a role to a group
# kcadm.sh add-roles -r $REALM --gname $GROUP_NAME --rolename $ROLE_NAME

# # Create a user
# USER_NAME=sebastian
# kcadm.sh create users -r $REALM -s username=$USER_NAME -s enabled=true  2>&1 | tee "$TMPFILE"
# USER_ID=`cat "$TMPFILE" | cut "-d'" -f2`

# ## Delete a user
# # kcadm.sh delete users/$USER_ID -r $REALM

# # Add a user to a group
# echo "Adding user $USER_NAME ($USER_ID) to group $GROUP_NAME ($GROUP_ID)"
# kcadm.sh update users/$USER_ID/groups/$GROUP_ID -r $REALM -s realm=$REALM \
#   -s userId=$USER_ID -s groupId=$GROUP_ID -n

# ## Remove a user from a group
# # kcadm.sh delete users/$USER_ID/groups/$GROUP_ID -r $REALM

# # TODO: Create/configure a default group for new (all?) users

# # TODO: Add group to another group