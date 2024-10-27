#!/bin/bash

HEADERS=(
  -H "Authorization: Bearer $GH_TOKEN"
  -H "Content-Type: application/json"
)

fetch_sponsor_details() {
  local username="$1"
  local after_cursor="$2"
  local sponsors=()

  local query
  query=$(jq -n --arg user "$username" --argjson after "$after_cursor" \
    '{
      query: "
        query($user: String!, $after: String) {
          user(login: $user) {
            sponsors(first: 100, after: $after) {
              pageInfo {
                hasNextPage
                endCursor
              }
              nodes {
                ... on User {
                  login
                  name
                  sponsorshipForViewerAsSponsorable {
                    privacyLevel
                  }
                }
              }
            }
          }
        }",
      variables: {
        user: $user,
        after: $after
      }
    }')

  local response
  response=$(curl -s -X POST "${HEADERS[@]}" -d "$query" https://api.github.com/graphql)

  local has_next_page
  has_next_page=$(echo "$response" | jq -r '.data.user.sponsors.pageInfo.hasNextPage')
  local end_cursor
  end_cursor=$(echo "$response" | jq -r '.data.user.sponsors.pageInfo.endCursor')

  local new_sponsors
  new_sponsors=$(echo "$response" | jq -c '.data.user.sponsors.nodes[] | select(.sponsorshipForViewerAsSponsorable.privacyLevel == "PUBLIC") | {github: .login, name: .name}')
  sponsors+=($new_sponsors)

  if [[ "$has_next_page" == "true" && "$end_cursor" != "null" ]]; then
    after_cursor="\"$end_cursor\""
    sponsors+=($(fetch_sponsor_details "$username" "$after_cursor"))
  fi

  echo "${sponsors[@]}"
}

echo "Logging in..."
user_response=$(curl -s "${HEADERS[@]}" https://api.github.com/user)
username=$(echo "$user_response" | jq -r '.login')

if [[ -z "$username" || "$username" == "null" ]]; then
  echo "Failed to fetch user info. Is your token valid and has the read:user scope?"
  exit 1
fi

echo "Logged in as: $username"

echo "Fetching sponsor details for $username..."
sponsors=$(fetch_sponsor_details "$username" "null")

echo "Saving sponsor details to sponsors.json..."
echo "$sponsors" | jq -s '.' > sponsors/credits.json
echo "Sponsor details saved to sponsors.json"