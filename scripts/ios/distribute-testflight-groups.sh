#!/usr/bin/env bash
# Complete TestFlight distribution only after Apple's processing is complete.
set -euo pipefail
umask 077

APP_ID="com.calebfeliciano.magicmobile"
BUILD_NUMBER=""
APP_VERSION=""
RELEASE_ROOT=""
EXTERNAL_GROUP_ID="${TESTFLIGHT_EXTERNAL_GROUP_ID:-72b71a7a-bf62-43b5-8eda-b12a62e5c3eb}"

usage() {
  echo "Usage: $0 --version VERSION --build-number NUMBER --release-root DIRECTORY" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|--build-number|--release-root)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "Missing value for $1" >&2; usage; exit 2
      fi
      if [[ "$1" == --version ]]; then
        [[ -z "$APP_VERSION" ]] || { echo "Duplicate --version" >&2; exit 2; }
        APP_VERSION="$2"
      elif [[ "$1" == --build-number ]]; then
        [[ -z "$BUILD_NUMBER" ]] || { echo "Duplicate --build-number" >&2; exit 2; }
        BUILD_NUMBER="$2"
      else
        [[ -z "$RELEASE_ROOT" ]] || { echo "Duplicate --release-root" >&2; exit 2; }
        RELEASE_ROOT="$2"
      fi
      shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$APP_VERSION" || -z "$BUILD_NUMBER" || -z "$RELEASE_ROOT" ]]; then
  usage; exit 2
fi
[[ "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "Invalid marketing version" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "Invalid build number: $BUILD_NUMBER" >&2; exit 2; }
[[ "$EXTERNAL_GROUP_ID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || {
  echo "TESTFLIGHT_EXTERNAL_GROUP_ID must be one group UUID" >&2; exit 2;
}
if [[ ! -d "$RELEASE_ROOT" ]]; then
  echo "Release evidence directory does not exist: $RELEASE_ROOT" >&2; exit 2
fi
command -v asc >/dev/null || { echo "Required desktop tool missing: asc" >&2; exit 2; }

# Validate ASC JSON, not merely command exit status. Membership uses ASC 5's
# structured lookup (including all-build access), not a JSON:API data array.
validate() {
  /usr/bin/python3 - "$@" <<'PY'
import json
import sys

mode, path, *args = sys.argv[1:]
def require(condition, message):
    if not condition:
        raise ValueError(message)

try:
    with open(path) as source:
        result = json.load(source)
    if mode == "build":
        builds = result["data"]
        require(len(builds) == 1, "Expected one unique build")
        build = builds[0]
        require(build["attributes"]["version"] == args[0], "Wrong build number")
        require(build["attributes"]["processingState"] == "VALID", "Build is not VALID")
        require(build.get("id") and build["type"] == "builds", "Missing build identity")
        version_id = build["relationships"]["preReleaseVersion"]["data"]["id"]
        versions = [v for v in result.get("included", []) if v.get("type") == "preReleaseVersions" and v.get("id") == version_id]
        require(len(versions) == 1 and versions[0]["attributes"]["version"] == args[1], "Wrong marketing version")
        print(build["id"])
    elif mode == "internal":
        groups = result["data"]
        require(groups and not result.get("links", {}).get("next"), "App groups missing or incomplete")
        require(all(g.get("id") and type(g["attributes"]["isInternalGroup"]) is bool for g in groups),
                "Invalid app group records")
        internal = [g for g in groups if g["attributes"]["isInternalGroup"]]
        require(internal, "Internal groups missing")
        with open(args[0], "w") as output:
            json.dump({"data": internal}, output)
    elif mode == "review":
        review = result["data"]
        require(review.get("id") and review["type"] == "betaAppReviewSubmissions", "Missing review identity")
        state = review["attributes"]["betaReviewState"]
        require(state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "APPROVED"), "Unacceptable review state: " + str(state))
        linkage = review.get("relationships", {}).get("build", {}).get("data")
        require(linkage is None or linkage.get("id") == args[0], "Review belongs to another build")
        print(state)
    elif mode == "groups":
        build_id, external_id, internal_path = args
        require(result["buildId"] == build_id, "Membership belongs to another build")
        require(result["complete"] is True and result.get("failures", []) == [], "Incomplete membership lookup")
        groups = result["groups"]
        require(result["groupCount"] == len(groups), "Inconsistent group count")
        with open(internal_path) as source:
            internal_ids = {g["id"] for g in json.load(source)["data"]}
        def contains(group_id, kind):
            return any(g["id"] == group_id and g["type"] == kind and
                       g["membership"] in ("explicit", "all-builds", "explicit-and-all-builds")
                       for g in groups)
        require(contains(external_id, "external"), "Expected External group membership missing")
        require(all(contains(i, "internal") for i in internal_ids), "Expected Internal group membership missing")
except (ValueError, KeyError, TypeError, AttributeError, OSError) as error:
    sys.exit("Invalid " + mode + " evidence: " + str(error))
PY
}

asc builds wait --app "$APP_ID" --version "$APP_VERSION" --build-number "$BUILD_NUMBER" --platform IOS \
  --timeout 30m --poll-interval 30s --fail-on-invalid --output json > "$RELEASE_ROOT/apple-processing.json"
asc builds list --app "$APP_ID" --version "$APP_VERSION" --build-number "$BUILD_NUMBER" --platform IOS --paginate \
  --output json > "$RELEASE_ROOT/apple-build.json"
BUILD_ID="$(validate build "$RELEASE_ROOT/apple-build.json" "$BUILD_NUMBER" "$APP_VERSION")"
# Preserve ASC's default: the configured External group plus all Internal groups.
# Apple's top-level filtered betaGroups endpoint can return 500 while the
# app-scoped endpoint works. Fetch every page there, then select internal groups.
asc testflight groups list --app "$APP_ID" --paginate --output json > "$RELEASE_ROOT/testflight-app-groups.json"
validate internal "$RELEASE_ROOT/testflight-app-groups.json" "$RELEASE_ROOT/testflight-internal-groups.json"

SUBMIT_ARGS=()
if asc builds beta-app-review-submission view --build-id "$BUILD_ID" --output json \
    > "$RELEASE_ROOT/beta-app-review-before.json" 2> "$RELEASE_ROOT/beta-app-review-before.stderr"; then
  validate review "$RELEASE_ROOT/beta-app-review-before.json" "$BUILD_ID" >/dev/null
else
  # ASC distinguishes a missing submission from an upstream 404/auth/network error.
  # Only its explicit missing-submission diagnostic permits a new submission.
  if ! grep -Fq "builds beta-app-review-submission view: no beta app review submission found for build \"$BUILD_ID\"" \
      "$RELEASE_ROOT/beta-app-review-before.stderr"; then
    cat "$RELEASE_ROOT/beta-app-review-before.stderr" >&2
    exit 1
  fi
  SUBMIT_ARGS=(--submit --confirm)
fi
asc builds add-groups --build-id "$BUILD_ID" --group "$EXTERNAL_GROUP_ID" \
  ${SUBMIT_ARGS[@]+"${SUBMIT_ARGS[@]}"} --output json > "$RELEASE_ROOT/testflight-distribution.json"
asc builds groups list --build-id "$BUILD_ID" --output json > "$RELEASE_ROOT/testflight-groups.json"
validate groups "$RELEASE_ROOT/testflight-groups.json" "$BUILD_ID" "$EXTERNAL_GROUP_ID" "$RELEASE_ROOT/testflight-internal-groups.json"
asc builds beta-app-review-submission view --build-id "$BUILD_ID" --output json > "$RELEASE_ROOT/beta-app-review.json"
REVIEW_STATE="$(validate review "$RELEASE_ROOT/beta-app-review.json" "$BUILD_ID")"
echo "TestFlight build $BUILD_NUMBER is assigned to Internal and External groups; Beta App Review state: $REVIEW_STATE."
