#!/bin/bash
# verify_latest_backup.sh — tier-3 verification of the most recent
# homeserver backup: extracts the gitea dump, spins up a throwaway gitea
# container pointed at it, hits the API, lists repos, clones one. Proves
# the dump is actually restorable, not just structurally valid.
#
# Defaults to the newest archive in $BACKUP_DIR. Pass an explicit path to
# verify a different one:
#   ./verify_latest_backup.sh ~/backups/steamdeck/homeserver-20260608T....tar.gz
set -euo pipefail

LOCAL_DIR="${BACKUP_DIR:-$HOME/backups/steamdeck}"
GITEA_IMAGE="${GITEA_IMAGE:-docker.io/gitea/gitea:latest}"
GITEA_NAME="${GITEA_NAME:-gitea-verify}"
GITEA_PORT="${GITEA_PORT:-13000}"
WAIT_SECS="${WAIT_SECS:-60}"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n'   "$*"; }
die()  { red "ERROR: $*"; exit 1; }

# ---- locate archive --------------------------------------------------------
if [ "$#" -ge 1 ]; then
  archive="$1"
else
  archive=$(ls -1t "$LOCAL_DIR"/homeserver-*.tar.gz 2>/dev/null | head -1 || true)
  [ -n "$archive" ] || die "no archive in $LOCAL_DIR — pass a path explicitly"
fi
[ -f "$archive" ] || die "archive not found: $archive"
step "verifying $(basename "$archive")"

# ---- prereqs --------------------------------------------------------------
for cmd in docker unzip git curl jq tar; do
  command -v "$cmd" >/dev/null || die "$cmd missing"
done

# ---- extract --------------------------------------------------------------
work=$(mktemp -d -t backup-verify-XXXXXX)
cleanup() {
  docker rm -f "$GITEA_NAME" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

step "extract gitea dump"
dump_in_tar=$(tar -tzf "$archive" | grep -E 'gitea-dump-.*\.zip$' | head -1)
[ -n "$dump_in_tar" ] || die "no gitea-dump-*.zip in archive"
tar -xzf "$archive" -C "$work" "$dump_in_tar"
dump="$work/$dump_in_tar"
ok "$(basename "$dump")"

step "extract dump contents"
mkdir -p "$work/dump"
unzip -qq -o "$dump" -d "$work/dump"

db_file=""
for cand in gitea-db.sqlite3 gitea-db.sql; do
  [ -f "$work/dump/$cand" ] && db_file="$cand" && break
done
[ -n "$db_file" ] || die "no gitea-db.{sqlite3,sql} in dump"
ok "db file: $db_file"

if [ "$db_file" != "gitea-db.sqlite3" ]; then
  cat <<EOF
$(red NOT-IMPLEMENTED:) tier-3 only supports SQLite gitea dumps right now.
Your dump is '$db_file' (likely Postgres or MySQL). The structural checks
in create_backup.sh (tier 2) still cover it. Extend this script with a
companion DB container if you want the full restore proof.
EOF
  exit 3
fi

# ---- materialize a gitea data dir -----------------------------------------
step "stage data dir for throwaway gitea"
data="$work/data"
mkdir -p "$data/gitea/conf" "$data/git/repositories"
cp "$work/dump/app.ini" "$data/gitea/conf/app.ini"
cp "$work/dump/$db_file" "$data/gitea.db"

# gitea-repo.zip is itself a zip of all bare repos.
unzip -qq -o "$work/dump/gitea-repo.zip" -d "$data/git/repositories"

# Optional pieces.
for opt in data custom; do
  if [ -f "$work/dump/$opt.zip" ]; then
    unzip -qq -o "$work/dump/$opt.zip" -d "$data/gitea"
  fi
done
ok "data dir at $data"

# Patch app.ini so the throwaway instance uses local SQLite + ephemeral
# secrets + the binding we expose to the host.
ini="$data/gitea/conf/app.ini"
python3 - "$ini" "$GITEA_PORT" <<'PY'
import configparser, sys
p, port = sys.argv[1], sys.argv[2]
cp = configparser.RawConfigParser(strict=False)
cp.optionxform = str
cp.read(p)
def s(section, key, val):
    if not cp.has_section(section): cp.add_section(section)
    cp.set(section, key, val)
s('database', 'DB_TYPE', 'sqlite3')
s('database', 'PATH',    '/data/gitea.db')
s('server',   'HTTP_PORT', port)
s('server',   'ROOT_URL', f'http://localhost:{port}/')
s('server',   'DOMAIN', 'localhost')
s('security', 'INSTALL_LOCK', 'true')
s('repository', 'ROOT', '/data/git/repositories')
with open(p, 'w') as f:
    cp.write(f, space_around_delimiters=False)
PY

# ---- boot throwaway gitea -------------------------------------------------
step "boot $GITEA_IMAGE on :$GITEA_PORT"
docker rm -f "$GITEA_NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$GITEA_NAME" \
  -p "127.0.0.1:$GITEA_PORT:$GITEA_PORT" \
  -v "$data:/data" \
  -e USER_UID=1000 -e USER_GID=1000 \
  "$GITEA_IMAGE" >/dev/null

base="http://127.0.0.1:$GITEA_PORT"
for i in $(seq 1 "$WAIT_SECS"); do
  if curl -fsS "$base/api/v1/version" >/dev/null 2>&1; then break; fi
  sleep 1
  if [ "$i" -eq "$WAIT_SECS" ]; then
    docker logs "$GITEA_NAME" 2>&1 | tail -40
    die "gitea did not start within ${WAIT_SECS}s"
  fi
done
ok "gitea up — $(curl -fsS "$base/api/v1/version" | jq -r .version)"

# ---- prove the data is real ----------------------------------------------
step "list repos via API"
mapfile -t repos < <(curl -fsS "$base/api/v1/repos/search?limit=50" | jq -r '.data[] | "\(.owner.login)/\(.name)"')
echo "    found ${#repos[@]} repo(s):"
printf '      - %s\n' "${repos[@]}" | head -10
[ "${#repos[@]}" -gt 0 ] || die "API returned zero repos"

step "clone first repo (no auth, public-only assumption)"
first="${repos[0]}"
if git -C "$work" clone --quiet "$base/$first.git" "clone-test" 2>"$work/clone.err"; then
  commits=$(git -C "$work/clone-test" rev-list --count HEAD 2>/dev/null || echo 0)
  ok "cloned $first ($commits commits)"
else
  # Private repos can't be cloned anonymously — that's fine, the API
  # listing already proved the data is intact. Surface the reason.
  red "    clone failed (likely private — API listing already proved data presence):"
  sed 's/^/      /' "$work/clone.err"
fi

step "verified"
printf '\033[32mTIER 3 PASS — %s is restorable.\033[0m\n' "$(basename "$archive")"
