#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

project_dir="$(cd "$(dirname "$0")" && pwd)"
service_name='Convert MOV to MP4'
bundle_id='local.mov-to-mp4.quick-action'
services_dir="$HOME/Library/Services"
destination="$services_dir/$service_name.workflow"
staging_dir=''

cleanup() {
    [ -z "$staging_dir" ] || /bin/rm -rf "$staging_dir"
}
trap cleanup EXIT

if [ "$(/usr/bin/uname -s)" != Darwin ]; then
    printf 'This Quick Action requires macOS.\n' >&2
    exit 1
fi
if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
    printf 'Install FFmpeg first: brew install ffmpeg\n' >&2
    exit 1
fi
/bin/bash -n "$project_dir/convert-mov-to-mp4.sh"
/bin/mkdir -p "$services_dir"
staging_dir=$(/usr/bin/mktemp -d "$services_dir/.mov-to-mp4-install.XXXXXX")
bundle="$staging_dir/$service_name.workflow"
/bin/mkdir -p "$bundle/Contents/Resources"

/bin/cat >"$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>local.mov-to-mp4.quick-action</string>
    <key>CFBundleName</key><string>Convert MOV to MP4</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>NSServices</key><array><dict>
        <key>NSMenuItem</key><dict><key>default</key><string>Convert MOV to MP4</string></dict>
        <key>NSMessage</key><string>runWorkflowAsService</string>
        <key>NSRequiredContext</key><dict>
            <key>NSApplicationIdentifier</key><string>com.apple.finder</string>
        </dict>
        <key>NSSendFileTypes</key><array><string>com.apple.quicktime-movie</string></array>
    </dict></array>
</dict></plist>
PLIST

/bin/cat >"$bundle/Contents/Resources/document.wflow" <<'WORKFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>AMDocumentVersion</key><string>2</string>
    <key>actions</key><array><dict><key>action</key><dict>
        <key>ActionBundlePath</key><string>/System/Library/Automator/Run Shell Script.action</string>
        <key>ActionName</key><string>Run Shell Script</string>
        <key>ActionParameters</key><dict>
            <key>COMMAND_STRING</key><string></string>
            <key>CheckedForUserDefaultShell</key><true/>
            <key>inputMethod</key><integer>1</integer>
            <key>shell</key><string>/bin/bash</string>
            <key>source</key><string></string>
        </dict>
        <key>AMAccepts</key><dict>
            <key>Container</key><string>List</string>
            <key>Optional</key><true/>
            <key>Types</key><array><string>com.apple.cocoa.string</string></array>
        </dict>
        <key>AMProvides</key><dict>
            <key>Container</key><string>List</string>
            <key>Types</key><array><string>com.apple.cocoa.string</string></array>
        </dict>
        <key>AMActionVersion</key><string>2.0.3</string>
        <key>Application</key><array><string>Automator</string></array>
        <key>BundleIdentifier</key><string>com.apple.RunShellScript</string>
        <key>CanShowWhenRun</key><false/>
        <key>ShowWhenRun</key><false/>
        <key>Class Name</key><string>RunShellScriptAction</string>
        <key>InputUUID</key><string>74105B7C-E022-4943-9444-405B073BE068</string>
        <key>OutputUUID</key><string>502726E8-0729-4D39-B041-45CDA1DBF1EB</string>
        <key>UUID</key><string>13AC884B-C31A-4A66-AB77-4BC29320EC2D</string>
    </dict></dict></array>
    <key>connectors</key><dict/>
    <key>workflowMetaData</key><dict>
        <key>serviceApplicationBundleID</key><string>com.apple.finder</string>
        <key>serviceApplicationPath</key><string>/System/Library/CoreServices/Finder.app</string>
        <key>serviceInputTypeIdentifier</key><string>com.apple.Automator.fileSystemObject.movie</string>
        <key>serviceOutputTypeIdentifier</key><string>com.apple.Automator.nothing</string>
        <key>serviceProcessesInput</key><integer>0</integer>
        <key>workflowTypeIdentifier</key><string>com.apple.Automator.servicesMenu</string>
        <key>serviceName</key><string>Convert MOV to MP4</string>
        <key>useAutomaticInputType</key><false/>
    </dict>
</dict></plist>
WORKFLOW

# Embed the script, so the installed action works after moving this project.
/usr/bin/plutil -replace actions.0.action.ActionParameters.COMMAND_STRING \
    -string "$(/bin/cat "$project_dir/convert-mov-to-mp4.sh")" \
    "$bundle/Contents/Resources/document.wflow"
/usr/bin/plutil -lint "$bundle/Contents/Info.plist" "$bundle/Contents/Resources/document.wflow"

# Back up previous versions, including bundles with an older localized name.
backup_slot=''
for installed_bundle in "$services_dir"/*.workflow; do
    [ -e "$installed_bundle" ] || continue
    installed_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
        "$installed_bundle/Contents/Info.plist" 2>/dev/null || true)
    if [ "$installed_bundle" = "$destination" ] || [ "$installed_id" = "$bundle_id" ]; then
        if [ -z "$backup_slot" ]; then
            backup_dir="$HOME/Library/Application Support/MOV-to-MP4/Backups"
            /bin/mkdir -p "$backup_dir"
            backup_slot=$(/usr/bin/mktemp -d "$backup_dir/$(/bin/date '+%Y%m%d-%H%M%S').XXXXXX")
        fi
        /bin/mv "$installed_bundle" "$backup_slot/"
    fi
done
/bin/mv "$bundle" "$destination"
/System/Library/CoreServices/pbs -update
printf '\nInstalled: %s\n' "$destination"
printf 'Finder → right-click a MOV file → Quick Actions / Services → %s\n' "$service_name"
