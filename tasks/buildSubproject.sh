#!/usr/bin/env bash
set -eo pipefail

IS_REMOTE=false;
LOG_PATH="$(pwd)/build.log";
MAIN_ARGS=$@;

function log {
    echo "$1" >&2;
    echo "$1" >> "$LOG_PATH";
}

function loadEnv {
    set -o allexport
    source "$1";
    set +o allexport
}

if [ -f "env/.env" ]; then
    loadEnv "env/.env";
    echo ""
    echo "⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠ [DEPRECATION NOTICE] ⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠"
    echo " Plz copy your file env/.env to the .env"
    echo "⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠ [/DEPRECATION NOTICE] ⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠⚠"

    echo ""
    echo ""
fi;

if [ -f ".env" ]; then
    loadEnv ".env";
fi;

if [ -z "$ROOT_DIR" ]; then
    echo "Missing [ROOT_DIR] inside env/.env file, to create one plz open the link below";
    echo "You will find inside an ex of the config."
    echo "https://github.com/ProtonMail/protonmail-settings#where-should-i-should-i-clone-them-"
    echo '  - You can debug via using export ROOT_DIR="$(pwd)"'
    echo
    exit 1;
fi;

WEBCLIENT_DIR="$ROOT_DIR/${WEBCLIENT_APP:-Angular}";

# Extract API flag and fallback default if it doesn't exist
API_FLAG=$(echo "$@" | awk 'match($0, /--api=(\w{3,4})/) {
    print substr($0, RSTART, RLENGTH)
}' | awk -F '=' '{print $2}');
API="${API_FLAG:-build}";

# Output dir where we will store the dist version of protonmail-settings.
# dist/settings will allow us to access to mail.protonmail.com/settings with protonmail-settings
SETTINGS_DIST_DIR="dist/settings";
CONTACTS_DIST_DIR="dist/contacts";
CALENDAR_DIST_DIR="dist/calendar";
DRIVE_DIST_DIR="dist/drive";
GIT_SUBPROJECT_URL="";
ARGS="$*";


log "[sub.build] $(date) MAIN_ARGS: $MAIN_ARGS"
log "[sub.build] api:$API, API_FLAG was $API_FLAG"
log "[init.project] remote $ARGS"
log "[init.project] path webclient $WEBCLIENT_DIR";
log "[init.project] current path $(pwd)";

ls -lh

function checkEnv {
    if [ "$1" = 'pm-settings' ] &&  [ -z "$PM_SETTINGS_GIT" ]; then
        echo '[env] Missing variable PM_SETTINGS_GIT inside your env';
        exit 1;
    fi;

    if [ "$1" = 'contacts' ] &&  [ -z "$CONTACTS_GIT" ]; then
        echo '[env] Missing variable CONTACTS_GIT inside your env'
        exit 1;
    fi;

    if [ "$1" = 'calendar' ] &&  [ -z "$CALENDAR_GIT" ]; then
        echo '[env] Missing variable CALENDAR_GIT inside your env'
        exit 1;
    fi;

    if [ "$1" = 'drive' ] &&  [ -z "$DRIVE_DIST_DIR" ]; then
        echo '[env] Missing variable DRIVE_DIST_DIR inside your env'
        exit 1;
    fi;
}

function getRemote {
    cd /tmp;
    rm -rf "/tmp/$1" || echo true;
    log "[clone] from $GIT_SUBPROJECT_URL {"${GIT_SUBPROJECT_BRANCH:-master}"} $(pwd)/$1"
    # --> Main branch is develop
    git clone --depth 1 "$GIT_SUBPROJECT_URL" "$1" --branch "${GIT_SUBPROJECT_BRANCH:-master}";
}

function loadProject {

    if [ ! -d "/tmp/app-config" ]; then
        git clone --depth 1 "$APP_CONFIG_REPOSITORY" /tmp/app-config
    fi;

    # Check if we need to clone the app because of a remote install
    if [[ "$ARGS" =~ "$1" ]]; then
        IS_REMOTE=true;

        log "[load.project] from remote $2"
        getRemote "$2";
        cd "/tmp/$2";

        log "[config.project] load from /tmp/$2"
        /tmp/app-config/install "/tmp/$2" --new --verbose --ignore-auto-pull
        log "[config.project] loaded"
        return 0;
    fi

    log "[load.project] local $2"
    cd "$ROOT_DIR/$2";
}

##
# Install and build a subproject then copy its bundle to our main app
# Angular. Inside the dist/directory.
# If
function addSubProject {

    # Seems like we need to force the load of the env inside a subproject
    # Else proton-i18n will have a cache of the env... from the OLD env even if when you run it it loads the env from the current repository,
    # magic
    source .env

    # If you build from locales we don't want to remove the node_modules
    if [ ! -d "./node_modules" ]; then

        if [ -s 'package-lsock.json' ]; then
            log "[install.project] npm ci"
            npm ci --no-color --no-audit;
        else
            log "[install.project] npm i"
            npm i --no-color --no-audit;
        fi
    fi;

    log "[build.project] npm run bundle -- $MAIN_ARGS --verbose"
    npm --no-color run bundle -- $MAIN_ARGS --no-lint --verbose


    # When we build from the CI we can split the build/job as it's faster
    # We have 2 options:
    #   --run-project all -> build Angular + calendar + contacts + settings
    #   --run-project <project> -> build only <project>
    #
    # With the 2sd option we can choose to build only one project instead of 4.
    # So we do not need ot move the output dist directory inside the WebClient's output dist directory; that's something done by the CI.
    # Idem we will manage the htacess via the CI
    if [[ "$ARGS" =~ --run-project ]] && [[ ! "$ARGS" =~ --run-project=all ]]; then
        cp -r dist "$WEBCLIENT_DIR/dist";
        return 0;
    fi;

    log "[build.project] Remove .htaccess to prevent directory listing";
    rm -rf dist/.htaccess || echo
    log "[build.project] Copy from $(pwd)/dist/ to $WEBCLIENT_DIR/$1";
    cp -r dist/ "$WEBCLIENT_DIR/$1";
}

if [[ "$*" == *--deploy-subproject=settings* ]]; then
    log "[build] settings"
    checkEnv 'pm-settings'
    GIT_SUBPROJECT_URL="$PM_SETTINGS_GIT";
    loadProject "--remote-pm-settings" "${SETTINGS_APP:-proton-mail-settings}";
    addSubProject "$SETTINGS_DIST_DIR";
fi

if [[ "$*" == *--deploy-subproject=contacts* ]]; then
    log "[build] contacts"
    checkEnv 'contacts'
    GIT_SUBPROJECT_URL="$CONTACTS_GIT";
    loadProject "--remote-contacts" "${CONTACTS_APP:-proton-contacts}";
    addSubProject "$CONTACTS_DIST_DIR";
fi

if [[ "$*" == *--deploy-subproject=calendar* ]]; then
    log "[build] calendar"
    checkEnv 'calendar'
    GIT_SUBPROJECT_URL="$CALENDAR_GIT";
    loadProject "--remote-calendar" "${CALENDAR_APP:-proton-calendar}";
    addSubProject "$CALENDAR_DIST_DIR";
fi

if [[ "$*" == *--deploy-subproject=drive* ]]; then
    log "[build] drive"
    checkEnv 'drive'
    GIT_SUBPROJECT_URL="$DRIVE_GIT";
    loadProject "--remote-drive" "${DRIVE_APP:-proton-drive}";
    addSubProject "$DRIVE_DIST_DIR";
fi

echo -e "\n" >> build.log
echo -e "\n" >> build.log
echo "[awk] $(awk --version)" >> build.log
echo -e "\n" >> build.log
