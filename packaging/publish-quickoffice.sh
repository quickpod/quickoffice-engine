#!/usr/bin/env bash
# Publish the three Quick Office apps to quickopen.ai.
#
#   packaging/publish-quickoffice.sh
#
# WHY THIS IS NOT publish-app.sh
# The fleet's publisher drives a Windows CI build, Authenticode-signs the exe,
# repacks the Inno installer and only then registers the release. Quick Office
# has none of that yet: the engine is built from source on a dedicated host and
# the Windows half is a separate lead time. What it DOES have is Linux
# artifacts that are already built, signed and verified - so this script starts
# at the point publish-app.sh reaches after signing: GitHub release -> R2 ->
# register -> publish.
#
# Artifacts per app:
#   <App>-<ver>.usi   PRIMARY. One-click, CMS-signed, verified by the AIQuick
#                     Install Gate; the payload deb pulls the shared engine
#                     from the AIQuick apt repo.
#   quickopen-<slug>_<ver>_all.deb   the same payload for apt users.
#
# The ENGINE deb is deliberately NOT registered as an app artifact: it is a
# shared runtime that apt resolves, not something a user downloads. It lives in
# the apt pool and (for Windows) on R2.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_REPO="$(cd "$HERE/.." && pwd)"
REPOS="$(cd "$ENGINE_REPO/.." && pwd)"
ROOT="$(cd "$REPOS/.." && pwd)"
DIST="$ENGINE_REPO/dist"
USI_DIR="$ROOT/ca/dist/usi"
API="https://api.quickpod.org/quickopen"
GETMEANAI_ENV="/home/ubuntu/getmeanai/api.getmeanai.com/.env"
VER="$(awk -F= '/^version=/{print $2}' "$ENGINE_REPO/pin.txt" | tr -d ' ')"
TAG="v$VER"
APPS=(quick-document quick-spreadsheet quick-presentation)

getv(){ awk -F= -v k="$1" '$1==k{v=substr($0,index($0,"=")+1); gsub(/\r/,"",v); print v}' "$GETMEANAI_ENV" | tail -1; }
say(){ printf '== %s\n' "$*"; }

PW="$(awk -F= '/^QUICKOPEN_ADMIN_PASSWORD=/{print $2}' "$ROOT/backend/.admin-credentials")"
AT="$(curl -s -X POST $API/update/auth/login -H 'Content-Type: application/json' \
      -d "{\"email\":\"aksansanwal@hotmail.com\",\"password\":\"$PW\"}" \
      | python3 -c "import json,sys;print(json.load(sys.stdin)['authToken'])")"
[ -n "$AT" ] || { echo "portal login failed"; exit 1; }

export R2_ACCOUNT_ID="$(getv R2_ACCOUNT_ID)"
export AWS_ACCESS_KEY_ID="$(getv R2_ACCESS_KEY_ID)"
export AWS_SECRET_ACCESS_KEY="$(getv R2_SECRET_ACCESS_KEY)"

for slug in "${APPS[@]}"; do
  APP="$REPOS/$slug"
  NAME="$(python3 -c "import json;print(json.load(open('$APP/.quickopen.json'))['name'])")"
  EXE="$(python3 -c "print(''.join(w.capitalize() for w in '$slug'.split('-')))")"
  USI="$USI_DIR/$EXE-$VER.usi"
  DEB="$DIST/quickopen-${slug}_${VER}-1_all.deb"
  [ -f "$USI" ] || { echo "!! missing $USI"; exit 1; }
  [ -f "$DEB" ] || { echo "!! missing $DEB"; exit 1; }

  say "$NAME $TAG"
  # 1. GitHub release
  gh release view "$TAG" --repo "quickpod/$slug" >/dev/null 2>&1 \
    && gh release upload "$TAG" "$USI" "$DEB" --repo "quickpod/$slug" --clobber >/dev/null \
    || gh release create "$TAG" "$USI" "$DEB" --repo "quickpod/$slug" \
         --title "$NAME $VER" --notes "AIQuick / Linux: double-click the .usi one-click installer (CMS-signed, verified against the QuickOpen Root CA), or \`apt install quickopen-$slug\` from the AIQuick repository. Both pull the shared Quick Office engine automatically. Windows installers follow.

Engine: a derivative of LibreOffice, MPL-2.0. Source and attribution: https://github.com/quickpod/quickoffice-engine" >/dev/null
  echo "   github release ok"

  # 2. R2 + 3. register the release on the portal
  python3 - "$USI" "$DEB" "$slug" "$NAME" "$VER" <<'PY'
import hashlib, json, os, sys
import boto3
from botocore.config import Config
usi, deb, slug, name, ver = sys.argv[1:6]
tag = "v" + ver
s3 = boto3.client("s3",
    endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
    region_name="auto", config=Config(signature_version="s3v4"))
bucket = "quickopen-artifacts"
arts = []
for path, primary, platform in ((usi, True, "linux"), (deb, False, "linux")):
    fn = os.path.basename(path)
    body = open(path, "rb").read()
    key = f"{slug}/{tag}/{fn}"
    s3.put_object(Bucket=bucket, Key=key, Body=body,
                  ContentType="application/octet-stream")
    arts.append({"filename": fn, "platform": platform, "arch": "x64",
                 "sizeBytes": len(body),
                 "sha256": hashlib.sha256(body).hexdigest(),
                 "r2Key": key, "primary": primary})
json.dump({"tag": tag, "name": f"{name} {ver}",
           "notes": "AIQuick / Linux: double-click the .usi one-click installer "
                    "(CMS-signed, verified against the QuickOpen Root CA), or "
                    f"`apt install quickopen-{slug}` from the AIQuick "
                    "repository. Both pull the shared Quick Office engine "
                    "automatically. Windows installers follow.",
           "prerelease": False, "artifacts": arts},
          open(f"/tmp/rel-{slug}.json", "w"))
print("   R2: %d artifacts" % len(arts))
PY

  PAYLOAD="$(python3 -c "
import json
m = json.load(open('$APP/.quickopen.json'))
print(json.dumps({'slug': m['slug'], 'name': m['name'], 'tagline': m['tagline'],
  'description': m['description'], 'categorySlug': m['categorySlug'],
  'license': m['license'], 'githubOwner': 'quickpod', 'githubRepo': m['slug'],
  'defaultBranch': 'main',
  'website': 'https://github.com/quickpod/' + m['slug'],
  'aiStack': m['aiStack']}))")"
  curl -s -X POST $API/update/admin/projects -H "Authorization: Bearer $AT" \
       -H 'Content-Type: application/json' -d "$PAYLOAD" >/dev/null
  curl -s -X POST $API/update/admin/projects/$slug/releases -H "Authorization: Bearer $AT" \
       -H 'Content-Type: application/json' -d @/tmp/rel-$slug.json >/dev/null
  curl -s -X POST $API/update/admin/projects/$slug/status -H "Authorization: Bearer $AT" \
       -H 'Content-Type: application/json' -d '{"status":"published"}' >/dev/null

  STATUS="$(curl -s $API/v1/projects/$slug | python3 -c "
import json,sys
p = json.load(sys.stdin); print(p.get('status'), p.get('latestVersion'))")"
  echo "   portal: $STATUS -> https://quickopen.ai/projects/$slug"
done

say "icons + screenshots"
for slug in "${APPS[@]}"; do
  "$ROOT/publish/scripts/upload-icons.sh" "$slug" >/dev/null 2>&1 && echo "   icon: $slug" || echo "   !! icon upload failed: $slug"
  "$ROOT/publish/scripts/refresh-screenshots.sh" "$slug" 2>&1 | tail -1
done
