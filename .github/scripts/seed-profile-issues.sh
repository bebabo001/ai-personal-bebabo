#!/usr/bin/env bash
# One-shot seeder for the personal profile archive.
# Safe to re-run: existing labels are updated, existing issue titles are kept.
set -euo pipefail

: "${REPO:?REPO is required, for example owner/name}"

create_label() {
  local name="$1"
  local color="$2"
  local description="$3"
  gh label create "$name" \
    --repo "$REPO" \
    --color "$color" \
    --description "$description" \
    --force >/dev/null
  echo "label: ${name}"
}

create_label "todo" "FBCA04" "待补充或待确认的档案内容"
create_label "profile" "0E8A16" "个人档案正文"
create_label "update" "1D76DB" "修订已有档案内容"

mapfile -t existing < <(gh issue list --repo "$REPO" --state all --limit 100 --json title --jq '.[].title')

has_title() {
  local title="$1"
  local item
  if [[ ${#existing[@]} -eq 0 ]]; then
    return 1
  fi
  for item in "${existing[@]}"; do
    if [[ "$item" == "$title" ]]; then
      return 0
    fi
  done
  return 1
}

issue_url() {
  local title="$1"
  gh issue list --repo "$REPO" --state all --limit 100 --json title,url \
    | jq -r --arg title "$title" '.[] | select(.title == $title) | .url' \
    | head -n 1
}

create_issue() {
  local title="$1"
  local section="$2"
  local url body

  if has_title "$title"; then
    url="$(issue_url "$title")"
    echo "exists: ${title} ${url}"
    return 0
  fi

  body=$(cat <<EOF
对应 README 章节：「${section}」。

当前该节只有标明「示例」的占位句，不是真实个人事实。请用可以公开、并且已经确认的内容替换占位句。

改完后关闭此 Issue。请用 Git 提交或 Pull Request 写入仓库，这样历史可追溯，也可以回退。参见 CONTRIBUTING.md。
EOF
)

  url="$(gh issue create \
    --repo "$REPO" \
    --title "$title" \
    --label "todo" \
    --label "profile" \
    --label "update" \
    --body "$body")"
  echo "created: ${title} ${url}"
  existing+=("$title")
}

create_issue "完善个人简介" "个人简介与背景"
create_issue "补充工作与学习习惯" "工作与学习习惯"
create_issue "明确沟通风格偏好" "沟通风格偏好"
create_issue "补充技术栈" "常用工具与技术栈"
create_issue "整理可公开的项目经验" "项目经验与成果"
create_issue "写下长期目标" "长期目标"

echo "=== project ==="
owner="${REPO%%/*}"
project_number=""
project_url=""

set +e
project_list="$(gh project list --owner "$owner" --limit 50 --format json 2>/tmp/project-list.err)"
list_status=$?
set -e

if [[ "$list_status" -ne 0 ]]; then
  echo "Project board was not created. Issues remain the tracker."
  cat /tmp/project-list.err || true
  exit 0
fi

project_number="$(printf '%s' "$project_list" | jq -r --arg title "个人档案待办" '
  (if type == "array" then . else (.projects // []) end)
  | map(select(.title == $title))
  | .[0].number // empty
')"
project_url="$(printf '%s' "$project_list" | jq -r --arg title "个人档案待办" '
  (if type == "array" then . else (.projects // []) end)
  | map(select(.title == $title))
  | .[0].url // empty
')"

if [[ -z "$project_number" ]]; then
  set +e
  project_create="$(gh project create --owner "$owner" --title "个人档案待办" --format json 2>/tmp/project-create.err)"
  create_status=$?
  set -e
  if [[ "$create_status" -ne 0 ]]; then
    echo "Project board was not created. Issues remain the tracker."
    cat /tmp/project-create.err || true
    exit 0
  fi
  project_number="$(printf '%s' "$project_create" | jq -r '.number // empty')"
  project_url="$(printf '%s' "$project_create" | jq -r '.url // empty')"
  echo "created project: ${project_url}"
else
  echo "exists project: ${project_url}"
fi

if [[ -z "$project_number" ]]; then
  echo "Project number missing. Issues remain the tracker."
  exit 0
fi

titles=(
  "完善个人简介"
  "补充工作与学习习惯"
  "明确沟通风格偏好"
  "补充技术栈"
  "整理可公开的项目经验"
  "写下长期目标"
)

for title in "${titles[@]}"; do
  url="$(issue_url "$title")"
  if [[ -z "$url" ]]; then
    echo "missing issue url: ${title}"
    continue
  fi
  set +e
  gh project item-add "$project_number" --owner "$owner" --url "$url" >/tmp/project-add.out 2>/tmp/project-add.err
  add_status=$?
  set -e
  if [[ "$add_status" -ne 0 ]]; then
    echo "could not add ${url}"
    cat /tmp/project-add.err || true
  else
    echo "added: ${url}"
  fi
done

echo "project: ${project_url}"
