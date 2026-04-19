#!/usr/bin/env bash

# Exports Configuration Status Account Report to CSV

OWNER="raqueldosil"
REPO="scrum-template"
LABEL="change request"
OUTPUT="csar.csv"

FIELDS=("Status" "Priority" "Estimate" "Sprint" "Assignee" "Affected CI" "Affected CI version" "Target CI version")

# Cabeceira CSV
HEADER="issue_number,title,url,project"
for f in "${FIELDS[@]}"; do
  HEADER="$HEADER,$f"
done
echo "$HEADER" > "$OUTPUT"

read -r -d '' QUERY <<'EOF'
query($owner: String!, $repo: String!, $label: String!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    issues(first: 50, labels: [$label], after: $cursor) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        number
        title
        url
        projectItems(first: 10) {
          nodes {
            project {
              title
            }
            fieldValues(first: 50) {
              nodes {
                ... on ProjectV2ItemFieldTextValue {
                  text
                  field { ... on ProjectV2FieldCommon { name } }
                }
                ... on ProjectV2ItemFieldSingleSelectValue {
                  name
                  field { ... on ProjectV2FieldCommon { name } }
                }
                ... on ProjectV2ItemFieldNumberValue {
                  number
                  field { ... on ProjectV2FieldCommon { name } }
                }
                ... on ProjectV2ItemFieldDateValue {
                  date
                  field { ... on ProjectV2FieldCommon { name } }
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF

CURSOR=null

while :; do
  RESPONSE=$(gh api graphql \
    -f query="$QUERY" \
    -f owner="$OWNER" \
    -f repo="$REPO" \
    -f label="$LABEL" \
    -F cursor="$CURSOR")

  echo "$RESPONSE" | jq -r --argjson fields "$(printf '%s\n' "${FIELDS[@]}" | jq -R . | jq -s .)" '
    .data.repository.issues.nodes[]? as $issue |
    $issue.projectItems.nodes[]? as $item |

    # Construír mapa campo -> valor (seguro contra nulls)
    (
      reduce ($item.fieldValues.nodes[]?) as $fv ({}; 
        if ($fv.field? and $fv.field.name?) then
          . + {
            ($fv.field.name): (
              $fv.text // 
              $fv.name // 
              ($fv.number|tostring) // 
              $fv.date // ""
            )
          }
        else
          .
        end
      )
    ) as $map |

    [
      $issue.number,
      ($issue.title | gsub(","; " ")),
      $issue.url,
      ($item.project.title // "")
    ] + ($fields | map($map[.] // ""))

    | @csv
  ' >> "$OUTPUT"

  HAS_NEXT=$(echo "$RESPONSE" | jq -r '.data.repository.issues.pageInfo.hasNextPage')
  if [ "$HAS_NEXT" != "true" ]; then
    break
  fi

  CURSOR=$(echo "$RESPONSE" | jq -r '.data.repository.issues.pageInfo.endCursor')
done

echo "Export completado en $OUTPUT"
